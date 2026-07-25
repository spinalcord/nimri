proc frontendTypeKindName(kind: FrontendTypeKind): string =
  case kind
  of ftkVoid: "void"
  of ftkBoolean: "boolean"
  of ftkString: "string"
  of ftkNumber: "number"
  of ftkNamed: "named"
  of ftkSequence: "sequence"
  of ftkArray: "array"
  of ftkOption: "option"
  of ftkTable: "table"
  of ftkTuple: "tuple"

proc namedTypeKindName(kind: FrontendNamedTypeKind): string =
  case kind
  of fntObject: "object"
  of fntEnum: "enum"
  of fntTuple: "tuple"

proc commandKindName(kind: FrontendCommandKind): string =
  case kind
  of fckSynchronous: "synchronous"
  of fckAsynchronous: "asynchronous"

proc parseCommandKind(name, path: string): FrontendCommandKind =
  case name
  of "synchronous": fckSynchronous
  of "asynchronous": fckAsynchronous
  else:
    raise newException(ValueError,
      "Invalid frontend RPC metadata: unknown command kind '" & name &
      "' at " & path)

proc frontendTypeJson(frontendType: FrontendType): JsonNode =
  result = newJObject()
  result["kind"] = %frontendTypeKindName(frontendType.kind)
  case frontendType.kind
  of ftkNamed:
    result["name"] = %frontendType.name
  of ftkSequence, ftkArray, ftkOption, ftkTable:
    result["elementType"] = frontendTypeJson(frontendType.elementType)
    if frontendType.kind == ftkArray:
      result["length"] = %frontendType.arrayLength
  of ftkTuple:
    result["fields"] = newJArray()
    for field in frontendType.fields:
      result["fields"].add(%* {
        "name": field.name,
        "type": frontendTypeJson(field.fieldType),
      })
  else:
    discard

proc frontendBindingsJson(model: FrontendBindingsModel): JsonNode =
  result = newJObject()
  result["schemaVersion"] = %3
  result["commands"] = newJArray()
  for binding in model.commands:
    var command = newJObject()
    command["commandKind"] = %commandKindName(binding.commandKind)
    command["modulePath"] = %binding.modulePath
    command["nimName"] = %binding.nimName
    command["tsName"] = %binding.tsName
    command["wireName"] = %binding.wireName
    command["parameters"] = newJArray()
    for parameter in binding.parameters:
      var parameterNode = newJObject()
      parameterNode["nimName"] = %parameter.nimName
      parameterNode["tsName"] = %parameter.tsName
      parameterNode["hasDefault"] = %parameter.hasDefault
      parameterNode["type"] = frontendTypeJson(parameter.parameterType)
      command["parameters"].add(parameterNode)
    command["returnType"] = frontendTypeJson(binding.returnType)
    result["commands"].add(command)

  result["types"] = newJArray()
  for declaration in model.types:
    var typeNode = newJObject()
    typeNode["name"] = %declaration.name
    typeNode["kind"] = %namedTypeKindName(declaration.kind)
    case declaration.kind
    of fntObject, fntTuple:
      typeNode["fields"] = newJArray()
      for field in declaration.fields:
        var fieldNode = newJObject()
        fieldNode["name"] = %field.name
        fieldNode["type"] = frontendTypeJson(field.fieldType)
        typeNode["fields"].add(fieldNode)
    of fntEnum:
      typeNode["members"] = %declaration.members
    result["types"].add(typeNode)

proc relativeImport(modulePath, target: string): string =
  let depth = modulePath.count('/')
  result = "../".repeat(depth + 1) & target

proc relativeTypesImport(modulePath: string): string =
  let depth = modulePath.count('/')
  if depth == 0:
    result = "./types"
  else:
    result = "../".repeat(depth) & "types"

proc frontendBindingsOutputDirectory(): string =
  result =
    if FrontendBindingsOutput.len > 0: FrontendBindingsOutput
    else: FrontendRpcProjectRoot / "frontend" / "commands"

proc safeGeneratedPath(relativePath: string): bool =
  if relativePath.len == 0 or relativePath.isAbsolute or
      not relativePath.endsWith(".ts"):
    return false
  for component in relativePath.split({'/', '\\'}):
    if component.len == 0 or component == "." or component == "..":
      return false
  result = true

proc renderedManifest(files: openArray[(string, string)]): string =
  var expectedPaths: seq[string]
  for item in files:
    if not safeGeneratedPath(item[0]):
      raise newException(ValueError,
        "Refusing unsafe generated frontend path '" & item[0] & "'")
    expectedPaths.add(item[0])
  expectedPaths.sort()
  result = GeneratedHeader & expectedPaths.join("\n") & "\n"

proc updateGeneratedFiles(files: openArray[(string, string)]) =
  let
    outputDirectory = frontendBindingsOutputDirectory()
    manifestPath = outputDirectory / ".frontend-bindings-manifest"
    manifest = renderedManifest(files)
  var expectedPaths: seq[string]

  for item in files:
    expectedPaths.add(item[0])
  expectedPaths.sort()

  createDir(outputDirectory)

  var stalePaths: seq[string]
  if fileExists(manifestPath):
    for line in readFile(manifestPath).splitLines:
      if safeGeneratedPath(line) and line notin expectedPaths:
        stalePaths.add(line)

  for stalePath in stalePaths:
    let destination = outputDirectory / stalePath
    if fileExists(destination):
      removeFile(destination)

  for item in files:
    let destination = outputDirectory / item[0]
    createDir(destination.parentDir)
    if not fileExists(destination) or readFile(destination) != item[1]:
      writeFile(destination, item[1])

  if not fileExists(manifestPath) or readFile(manifestPath) != manifest:
    writeFile(manifestPath, manifest)

proc requireField(node: JsonNode; name, path: string;
    kind: JsonNodeKind): JsonNode =
  if node.kind != JObject or not node.hasKey(name):
    raise newException(ValueError,
      "Invalid frontend RPC metadata: missing " & path & "." & name)
  result = node[name]
  if result.kind != kind:
    raise newException(ValueError,
      "Invalid frontend RPC metadata: " & path & "." & name &
      " has the wrong JSON type")

proc parseFrontendType(node: JsonNode; path: string): FrontendType =
  let kindName = requireField(node, "kind", path, JString).getStr()
  case kindName
  of "void":
    result = FrontendType(kind: ftkVoid)
  of "boolean":
    result = FrontendType(kind: ftkBoolean)
  of "string":
    result = FrontendType(kind: ftkString)
  of "number":
    result = FrontendType(kind: ftkNumber)
  of "named":
    result = FrontendType(
      kind: ftkNamed,
      name: requireField(node, "name", path, JString).getStr()
    )
  of "sequence", "array", "option", "table":
    let element = requireField(node, "elementType", path, JObject)
    let kind =
      case kindName
      of "sequence": ftkSequence
      of "array": ftkArray
      of "option": ftkOption
      else: ftkTable
    result = FrontendType(
      kind: kind,
      elementType: parseFrontendType(element, path & ".elementType")
    )
    if kind == ftkArray:
      result.arrayLength = requireField(node, "length", path, JInt).getInt()
  of "tuple":
    result = FrontendType(kind: ftkTuple)
    let fields = requireField(node, "fields", path, JArray)
    for index in 0 ..< fields.len:
      let
        field = fields[index]
        fieldPath = path & ".fields[" & $index & "]"
      result.fields.add(FrontendField(
        name: requireField(field, "name", fieldPath, JString).getStr(),
        fieldType: parseFrontendType(
          requireField(field, "type", fieldPath, JObject),
          fieldPath & ".type")
      ))
  else:
    raise newException(ValueError,
      "Invalid frontend RPC metadata: unknown type kind '" & kindName & "'")

proc readFrontendBindingsModel(): FrontendBindingsModel =
  if not fileExists(FrontendRpcMetadataPath):
    raise newException(IOError,
      "Frontend RPC metadata is missing. Run `./app.sh serialize` first.")

  let root =
    try:
      parseJson(readFile(FrontendRpcMetadataPath))
    except JsonParsingError as exception:
      raise newException(ValueError,
        "Invalid frontend RPC metadata JSON: " & exception.msg)

  let schemaVersion = requireField(
    root, "schemaVersion", "root", JInt).getInt()
  if schemaVersion != 3:
    raise newException(ValueError,
      "Unsupported frontend RPC metadata schema version " & $schemaVersion)

  let commands = requireField(root, "commands", "root", JArray)
  for index in 0 ..< commands.len:
    let commandNode = commands[index]
    let path = "commands[" & $index & "]"
    var binding = FrontendBinding(
      commandKind: parseCommandKind(
        requireField(commandNode, "commandKind", path, JString).getStr(),
        path & ".commandKind"),
      modulePath: requireField(
        commandNode, "modulePath", path, JString).getStr(),
      nimName: requireField(commandNode, "nimName", path, JString).getStr(),
      tsName: requireField(commandNode, "tsName", path, JString).getStr(),
      wireName: requireField(commandNode, "wireName", path, JString).getStr(),
      returnType: parseFrontendType(
        requireField(commandNode, "returnType", path, JObject),
        path & ".returnType")
    )
    let parameters = requireField(
      commandNode, "parameters", path, JArray)
    for parameterIndex in 0 ..< parameters.len:
      let parameterNode = parameters[parameterIndex]
      let parameterPath =
        path & ".parameters[" & $parameterIndex & "]"
      binding.parameters.add(BindingParameter(
        nimName: requireField(
          parameterNode, "nimName", parameterPath, JString).getStr(),
        tsName: requireField(
          parameterNode, "tsName", parameterPath, JString).getStr(),
        hasDefault: requireField(
          parameterNode, "hasDefault", parameterPath, JBool).getBool(),
        parameterType: parseFrontendType(
          requireField(parameterNode, "type", parameterPath, JObject),
          parameterPath & ".type")
      ))
    result.commands.add(binding)

  let types = requireField(root, "types", "root", JArray)
  for index in 0 ..< types.len:
    let typeNode = types[index]
    let
      path = "types[" & $index & "]"
      kindName = requireField(typeNode, "kind", path, JString).getStr()
    var declaration = TypeDeclaration(
      name: requireField(typeNode, "name", path, JString).getStr()
    )
    case kindName
    of "object", "tuple":
      declaration.kind =
        if kindName == "object": fntObject
        else: fntTuple
      let fields = requireField(typeNode, "fields", path, JArray)
      for fieldIndex in 0 ..< fields.len:
        let fieldNode = fields[fieldIndex]
        let fieldPath = path & ".fields[" & $fieldIndex & "]"
        declaration.fields.add(FrontendField(
          name: requireField(
            fieldNode, "name", fieldPath, JString).getStr(),
          fieldType: parseFrontendType(
            requireField(fieldNode, "type", fieldPath, JObject),
            fieldPath & ".type")
        ))
    of "enum":
      declaration.kind = fntEnum
      let members = requireField(typeNode, "members", path, JArray)
      for memberIndex in 0 ..< members.len:
        let member = members[memberIndex]
        if member.kind != JString:
          raise newException(ValueError,
            "Invalid frontend RPC metadata: " & path & ".members[" &
            $memberIndex & "] has the wrong JSON type")
        declaration.members.add(member.getStr())
    else:
      raise newException(ValueError,
        "Invalid frontend RPC metadata: unknown named type kind '" &
        kindName & "'")
    result.types.add(declaration)

proc typeScriptType(frontendType: FrontendType): string =
  case frontendType.kind
  of ftkVoid: "void"
  of ftkBoolean: "boolean"
  of ftkString: "string"
  of ftkNumber: "number"
  of ftkNamed: frontendType.name
  of ftkSequence:
    "Array<" & typeScriptType(frontendType.elementType) & ">"
  of ftkArray:
    var elements = newSeq[string](frontendType.arrayLength)
    for index in 0 ..< elements.len:
      elements[index] = typeScriptType(frontendType.elementType)
    "[" & elements.join(", ") & "]"
  of ftkOption:
    typeScriptType(frontendType.elementType) & " | null"
  of ftkTable:
    "Record<string, " & typeScriptType(frontendType.elementType) & ">"
  of ftkTuple:
    var fields: seq[string]
    for field in frontendType.fields:
      fields.add(field.name & ": " & typeScriptType(field.fieldType))
    "{ " & fields.join("; ") & " }"

proc validateFields(fields: seq[FrontendField]; namedTypes: HashSet[string];
    path: string)

proc validateFrontendType(frontendType: FrontendType;
    namedTypes: HashSet[string]; allowVoid: bool; path: string) =
  case frontendType.kind
  of ftkVoid:
    if not allowVoid:
      raise newException(ValueError,
        "Invalid frontend RPC metadata: void is not allowed at " & path)
  of ftkNamed:
    if frontendType.name.len == 0 or frontendType.name notin namedTypes:
      raise newException(ValueError,
        "Invalid frontend RPC metadata: unknown named type '" &
        frontendType.name & "' at " & path)
  of ftkArray:
    if frontendType.arrayLength < 0:
      raise newException(ValueError,
        "Invalid frontend RPC metadata: negative array length at " & path)
    validateFrontendType(
      frontendType.elementType, namedTypes, false, path & ".elementType")
  of ftkSequence, ftkOption, ftkTable:
    validateFrontendType(
      frontendType.elementType, namedTypes, false, path & ".elementType")
  of ftkTuple:
    validateFields(frontendType.fields, namedTypes, path & ".fields")
  else:
    discard

proc validateFields(fields: seq[FrontendField]; namedTypes: HashSet[string];
    path: string) =
  var fieldNames = initHashSet[string]()
  for fieldIndex, field in fields:
    if field.name.len == 0 or field.name in fieldNames:
      raise newException(ValueError,
        "Invalid frontend RPC metadata: duplicate or empty field name at " &
        path & "[" & $fieldIndex & "]")
    fieldNames.incl(field.name)
    validateFrontendType(
      field.fieldType, namedTypes, false,
      path & "[" & $fieldIndex & "].type")

proc validateFrontendBindingsModel(model: FrontendBindingsModel) =
  var
    namedTypes = initHashSet[string]()
    wireNames = initHashSet[string]()
    moduleCommandNames = initHashSet[string]()

  for typeIndex, declaration in model.types:
    if declaration.name.len == 0 or declaration.name in namedTypes:
      raise newException(ValueError,
        "Invalid frontend RPC metadata: duplicate or empty type name at types[" &
        $typeIndex & "]")
    namedTypes.incl(declaration.name)

  for typeIndex, declaration in model.types:
    let path = "types[" & $typeIndex & "]"
    case declaration.kind
    of fntObject, fntTuple:
      validateFields(declaration.fields, namedTypes, path & ".fields")
    of fntEnum:
      if declaration.members.len == 0:
        raise newException(ValueError,
          "Invalid frontend RPC metadata: enum " & declaration.name &
          " has no members")
      var members = initHashSet[string]()
      for memberIndex, member in declaration.members:
        if member.len == 0 or member in members:
          raise newException(ValueError,
            "Invalid frontend RPC metadata: duplicate or empty enum member at " &
            path & ".members[" & $memberIndex & "]")
        members.incl(member)

  for commandIndex, binding in model.commands:
    let
      path = "commands[" & $commandIndex & "]"
      outputPath = binding.modulePath & ".ts"
      moduleCommandName = binding.modulePath & "\0" & binding.tsName
    if binding.modulePath.len == 0 or not safeGeneratedPath(outputPath):
      raise newException(ValueError,
        "Invalid frontend RPC metadata: unsafe module path at " & path)
    if binding.nimName.len == 0 or binding.tsName.len == 0 or
        binding.wireName.len == 0:
      raise newException(ValueError,
        "Invalid frontend RPC metadata: empty command name at " & path)
    if binding.wireName in wireNames:
      raise newException(ValueError,
        "Invalid frontend RPC metadata: duplicate wire name '" &
        binding.wireName & "'")
    if moduleCommandName in moduleCommandNames:
      raise newException(ValueError,
        "Invalid frontend RPC metadata: duplicate TypeScript command '" &
        binding.tsName & "' in module '" & binding.modulePath & "'")
    wireNames.incl(binding.wireName)
    moduleCommandNames.incl(moduleCommandName)

    var
      parameterNames = initHashSet[string]()
      parameterTsNames = initHashSet[string]()
    for parameterIndex, parameter in binding.parameters:
      if parameter.nimName.len == 0 or parameter.tsName.len == 0 or
          parameter.nimName in parameterNames or
          parameter.tsName in parameterTsNames:
        raise newException(ValueError,
          "Invalid frontend RPC metadata: duplicate or empty parameter at " &
          path & ".parameters[" & $parameterIndex & "]")
      parameterNames.incl(parameter.nimName)
      parameterTsNames.incl(parameter.tsName)
      validateFrontendType(
        parameter.parameterType, namedTypes, false,
        path & ".parameters[" & $parameterIndex & "].type")
    validateFrontendType(
      binding.returnType, namedTypes, true, path & ".returnType")

proc collectReferencedTypeNames(frontendType: FrontendType;
    names: var seq[string]) =
  case frontendType.kind
  of ftkNamed:
    if frontendType.name notin names:
      names.add(frontendType.name)
  of ftkSequence, ftkArray, ftkOption, ftkTable:
    collectReferencedTypeNames(frontendType.elementType, names)
  of ftkTuple:
    for field in frontendType.fields:
      collectReferencedTypeNames(field.fieldType, names)
  else:
    discard

proc renderCommandModule(modulePath: string;
    bindings: seq[FrontendBinding]): string =
  var referencedTypes: seq[string]
  for binding in bindings:
    for parameter in binding.parameters:
      collectReferencedTypeNames(parameter.parameterType, referencedTypes)
    collectReferencedTypeNames(binding.returnType, referencedTypes)
  referencedTypes.sort()

  var commandViews = newJArray()
  for bindingIndex, binding in bindings:
    var
      parameterDeclarations: seq[string]
      argumentFields: seq[string]
    for parameterIndex, parameter in binding.parameters:
      let parameterType = typeScriptType(parameter.parameterType)
      if parameter.hasDefault:
        var hasRequiredParameterAfter = false
        for laterIndex in parameterIndex + 1 ..< binding.parameters.len:
          if not binding.parameters[laterIndex].hasDefault:
            hasRequiredParameterAfter = true
            break
        if hasRequiredParameterAfter:
          parameterDeclarations.add(
            parameter.tsName & ": " & parameterType & " | undefined")
        else:
          parameterDeclarations.add(
            parameter.tsName & "?: " & parameterType)
      else:
        parameterDeclarations.add(parameter.tsName & ": " & parameterType)
      if parameter.nimName == parameter.tsName:
        argumentFields.add(parameter.tsName)
      else:
        argumentFields.add(parameter.nimName & ": " & parameter.tsName)

    commandViews.add(%* {
      "tsName": binding.tsName,
      "parameters": parameterDeclarations.join(", "),
      "returnType": typeScriptType(binding.returnType),
      "wireName": binding.wireName,
      "arguments": argumentFields.join(", "),
      "last": bindingIndex == bindings.high,
    })

  let context = newContext()
  context["hasTypeImports"] = referencedTypes.len > 0
  context["typeImports"] = referencedTypes.join(", ")
  context["typesImport"] = relativeTypesImport(modulePath)
  context["rpcImport"] = relativeImport(modulePath, "rpc")
  context["commands"] = commandViews
  result = CommandModuleTemplate.render(context)

proc renderTypesFile(types: seq[TypeDeclaration]): string =
  var typeViews = newJArray()
  for typeIndex, declaration in types:
    var typeView = %* {
      "name": declaration.name,
      "isObject": declaration.kind == fntObject,
      "isEnum": declaration.kind == fntEnum,
      "isTuple": declaration.kind == fntTuple,
      "last": typeIndex == types.high,
    }
    case declaration.kind
    of fntObject, fntTuple:
      typeView["fields"] = newJArray()
      for field in declaration.fields:
        typeView["fields"].add(%* {
          "name": field.name,
          "type": typeScriptType(field.fieldType),
        })
    of fntEnum:
      var members: seq[string]
      for member in declaration.members:
        members.add("'" & member & "'")
      typeView["members"] = %members.join(" | ")
    typeViews.add(typeView)

  let context = newContext()
  context["hasTypes"] = types.len > 0
  context["types"] = typeViews
  result = TypesTemplate.render(context)

proc generateFrontendFiles() =
  let model = readFrontendBindingsModel()
  validateFrontendBindingsModel(model)
  var
    files: seq[(string, string)]
    modulePaths: seq[string]
  for binding in model.commands:
    if binding.modulePath notin modulePaths:
      modulePaths.add(binding.modulePath)
  modulePaths.sort()

  for modulePath in modulePaths:
    var moduleBindings: seq[FrontendBinding]
    for binding in model.commands:
      if binding.modulePath == modulePath:
        moduleBindings.add(binding)
    files.add((modulePath & ".ts",
      renderCommandModule(modulePath, moduleBindings)))

  files.add(("types.ts", renderTypesFile(model.types)))
  files.sort(proc(left, right: (string, string)): int =
    cmp(left[0], right[0]))
  updateGeneratedFiles(files)

proc updateSerializedFrontendBindings(contents: string) =
  createDir(FrontendRpcMetadataPath.parentDir)
  if not fileExists(FrontendRpcMetadataPath) or
      readFile(FrontendRpcMetadataPath) != contents:
    writeFile(FrontendRpcMetadataPath, contents)

macro defineFrontendBindings*(): untyped =
  var bindings = collectedBindings
  bindings.sort(proc(left, right: FrontendBinding): int =
    result = cmp((left.modulePath, left.tsName), (right.modulePath, right.tsName))
  )

  var types = collectedTypes
  types.sort(proc(left, right: TypeDeclaration): int =
    result = cmp(left.name, right.name)
  )
  let serializedModel = newLit($(frontendBindingsJson(
    FrontendBindingsModel(commands: bindings, types: types))))
  result = quote do:
    proc serializeFrontendBindings*() =
      updateSerializedFrontendBindings(`serializedModel`)

    proc generateFrontendBindings*() =
      generateFrontendFiles()
