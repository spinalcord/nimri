proc typeIdentity(symbol: NimNode): string {.compileTime.} =
  let location = symbol.getImpl.lineInfoObj
  result = location.filename.normalizedPath & ":" &
    $location.line & ":" & symbol.strVal

proc findType(identity: string): int {.compileTime.} =
  for index, declaration in collectedTypes:
    if declaration.identity == identity:
      return index
  result = -1

proc ensureNamedType(typeNode: NimNode): string {.compileTime.}

proc unsupportedType(typeNode: NimNode; detail = "") {.compileTime.} =
  var message = "unsupported frontend type '" & typeNode.repr & "'"
  if detail.len > 0:
    message.add(": " & detail)
  error(message, typeNode)

proc arrayTypeLength(indexType: NimNode): int {.compileTime.} =
  case indexType.kind
  of nnkIntLit .. nnkUInt64Lit:
    result = int(indexType.intVal)
  of nnkInfix:
    if indexType.len == 3 and indexType[0].strVal == ".." and
        indexType[1].kind in {nnkIntLit .. nnkUInt64Lit} and
        indexType[2].kind in {nnkIntLit .. nnkUInt64Lit}:
      result = int(indexType[2].intVal - indexType[1].intVal + 1)
    else:
      unsupportedType(indexType,
        "fixed array bounds must resolve to an integer range")
  else:
    unsupportedType(indexType,
      "fixed array length must resolve to an integer literal or range")
  if result < 0:
    unsupportedType(indexType, "fixed array length cannot be negative")

proc tupleFields(tupleNode: NimNode): seq[FrontendField] {.compileTime.}

proc frontendType(typeNode: NimNode): FrontendType {.compileTime.} =
  if typeNode.kind == nnkEmpty:
    return FrontendType(kind: ftkVoid)

  let node =
    if typeNode.kind == nnkVarTy: typeNode[0]
    else: typeNode

  case node.kind
  of nnkBracketExpr:
    let container = node[0].strVal
    case container
    of "seq":
      if node.len != 2:
        unsupportedType(node)
      result = FrontendType(
        kind: ftkSequence,
        elementType: frontendType(node[1])
      )
    of "array":
      if node.len != 3:
        unsupportedType(node)
      result = FrontendType(
        kind: ftkArray,
        elementType: frontendType(node[2]),
        arrayLength: arrayTypeLength(node[1])
      )
    of "Option":
      if node.len != 2:
        unsupportedType(node)
      result = FrontendType(
        kind: ftkOption,
        elementType: frontendType(node[1])
      )
    of "Table", "OrderedTable":
      if node.len != 3:
        unsupportedType(node)
      if node[1].strVal != "string":
        unsupportedType(node,
          "frontend tables require string keys")
      result = FrontendType(
        kind: ftkTable,
        elementType: frontendType(node[2])
      )
    else:
      unsupportedType(node,
        "generics are not part of the frontend binding contract")
  of nnkSym, nnkIdent:
    let name = node.strVal
    case name
    of "void":
      result = FrontendType(kind: ftkVoid)
    of "bool":
      result = FrontendType(kind: ftkBoolean)
    of "string":
      result = FrontendType(kind: ftkString)
    of "int", "int8", "int16", "int32", "int64",
        "uint", "uint8", "uint16", "uint32", "uint64",
        "Natural", "Positive", "float", "float32", "float64":
      result = FrontendType(kind: ftkNumber)
    else:
      if node.kind != nnkSym:
        unsupportedType(node, "the type could not be resolved")
      let typeName = ensureNamedType(node)
      result = FrontendType(kind: ftkNamed, name: typeName)
  of nnkTupleTy:
    result = FrontendType(kind: ftkTuple, fields: tupleFields(node))
  of nnkTupleConstr:
    unsupportedType(node, "tuple values require an explicit named tuple type")
  of nnkRefTy:
    unsupportedType(node, "reference types are not supported")
  of nnkPtrTy:
    unsupportedType(node, "pointer types are not supported")
  else:
    unsupportedType(node)

proc tupleFields(tupleNode: NimNode): seq[FrontendField] {.compileTime.} =
  for field in tupleNode:
    if field.kind != nnkIdentDefs or field.len < 3:
      unsupportedType(tupleNode, "all tuple fields must be named")
    if field[^1].kind != nnkEmpty:
      unsupportedType(field, "tuple fields cannot have default values")
    for nameIndex in 0 ..< field.len - 2:
      let nameNode = field[nameIndex]
      if nameNode.kind notin {nnkIdent, nnkSym, nnkPostfix}:
        unsupportedType(nameNode, "all tuple fields must be named")
      result.add(FrontendField(
        name: commandName(nameNode),
        fieldType: frontendType(field[^2])
      ))

proc enumMemberName(node: NimNode): string {.compileTime.} =
  case node.kind
  of nnkIdent, nnkSym:
    result = node.strVal
  of nnkEnumFieldDef:
    result = node[0].strVal
  else:
    error("unsupported enum member in frontend type", node)

proc ensureNamedType(typeNode: NimNode): string {.compileTime.} =
  let
    identity = typeIdentity(typeNode)
    existingIndex = findType(identity)

  if existingIndex >= 0:
    return collectedTypes[existingIndex].name

  let definition = typeNode.getImpl
  if definition.kind != nnkTypeDef:
    unsupportedType(typeNode)
  if not isExportedName(definition[0]):
    error("frontend object, enum, and tuple types must be exported: '" &
      typeNode.strVal & "'", typeNode)

  let
    typeName = typeNode.strVal
    body = definition[2]

  for declaration in collectedTypes:
    if declaration.name == typeName and declaration.identity != identity:
      error("ambiguous frontend type name '" & typeName &
        "' is declared in more than one module", typeNode)

  # Install a placeholder first so recursive object fields terminate.
  collectedTypes.add(TypeDeclaration(identity: identity, name: typeName))
  let declarationIndex = collectedTypes.high

  case body.kind
  of nnkEnumTy:
    collectedTypes[declarationIndex].kind = fntEnum
    for index in 1 ..< body.len:
      collectedTypes[declarationIndex].members.add(
        enumMemberName(body[index]))
    if collectedTypes[declarationIndex].members.len == 0:
      error("frontend enums must contain at least one member", typeNode)
  of nnkObjectTy:
    collectedTypes[declarationIndex].kind = fntObject
    if body[1].kind != nnkEmpty:
      error("frontend objects cannot use inheritance", typeNode)
    let fields = body[2]
    if fields.kind != nnkRecList:
      error("unsupported frontend object layout for '" & typeName & "'",
        typeNode)

    for field in fields:
      if field.kind != nnkIdentDefs:
        error("frontend objects cannot contain variants or case fields",
          field)
      if field[^1].kind != nnkEmpty:
        error("frontend object fields cannot have default values", field)
      for nameIndex in 0 ..< field.len - 2:
        let fieldNameNode = field[nameIndex]
        if not isExportedName(fieldNameNode):
          error("frontend object field '" & commandName(fieldNameNode) &
            "' must be exported", fieldNameNode)
        collectedTypes[declarationIndex].fields.add(FrontendField(
          name: commandName(fieldNameNode),
          fieldType: frontendType(field[^2])
        ))
  of nnkTupleTy:
    collectedTypes[declarationIndex].kind = fntTuple
    collectedTypes[declarationIndex].fields = tupleFields(body)
  else:
    unsupportedType(typeNode,
      "only exported enums, plain objects, and named tuples are supported")

  result = typeName
