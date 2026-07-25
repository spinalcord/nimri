proc frontendFromJson[T](node: JsonNode, _: typedesc[T]): T =
  when T is string:
    if node.kind != JString:
      raise newException(ValueError, "Frontend string value expected")
    result = node.getStr()
  elif T is bool:
    if node.kind != JBool:
      raise newException(ValueError, "Frontend boolean value expected")
    result = node.getBool()
  elif T is SomeInteger:
    if node.kind != JInt:
      raise newException(ValueError, "Frontend integer value expected")
    let value = node.getBiggestInt()
    if value < -MaxSafeJavaScriptInteger or value > MaxSafeJavaScriptInteger:
      raise newException(ValueError,
        "Frontend integers must be within JavaScript's safe integer range")
    when T is SomeUnsignedInt:
      if value < 0:
        raise newException(
          ValueError, "Frontend unsigned integer must be positive")
    when sizeof(T) < 8:
      if value < BiggestInt(low(T)) or value > BiggestInt(high(T)):
        raise newException(
          ValueError, "Frontend integer is outside its Nim range")
    result = T(value)
  elif T is SomeFloat:
    if node.kind notin {JInt, JFloat}:
      raise newException(ValueError, "Frontend number value expected")
    result = T(node.getFloat())
    if classify(result) in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError,
        "Frontend floating-point values must be finite")
  elif T is enum:
    if node.kind != JString:
      raise newException(ValueError,
        "Frontend enum values must be encoded as symbols")
    result = parseEnum[T](node.getStr())
  elif T is Option:
    type Inner = typeof(default(T).get)
    if node.kind == JNull:
      result = none(Inner)
    else:
      result = some(frontendFromJson(node, Inner))
  elif T is seq:
    type Inner = typeof(default(T)[0])
    if node.kind != JArray:
      raise newException(ValueError, "Frontend sequence values must be arrays")
    for index in 0 ..< node.len:
      result.add(frontendFromJson(node[index], Inner))
  elif T is array:
    type Inner = typeof(default(T)[0])
    if node.kind != JArray or node.len != result.len:
      raise newException(ValueError,
        "Frontend fixed array must contain exactly " & $result.len & " values")
    for index in 0 ..< result.len:
      result[index] = frontendFromJson(node[index], Inner)
  elif T is object:
    if node.kind != JObject:
      raise newException(ValueError, "Frontend object values must be objects")
    for fieldName, field in fieldPairs(result):
      if not node.hasKey(fieldName):
        raise newException(ValueError,
          "Missing required object field '" & fieldName & "'")
      field = frontendFromJson(node[fieldName], typeof(field))
  else:
    {.error: "unsupported frontend input type".}

proc frontendToJson[T](value: T): JsonNode =
  when T is Option:
    if value.isSome:
      result = frontendToJson(value.get)
    else:
      result = newJNull()
  elif T is enum:
    result = %($value)
  elif T is object:
    result = newJObject()
    for fieldName, field in fieldPairs(value):
      result[fieldName] = frontendToJson(field)
  elif T is seq or T is array:
    result = newJArray()
    for item in value:
      result.add(frontendToJson(item))
  elif T is SomeFloat:
    if classify(value) in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError,
        "Frontend floating-point values must be finite")
    result = %value
  elif T is SomeInteger:
    when T is SomeUnsignedInt:
      if uint64(value) > uint64(MaxSafeJavaScriptInteger):
        raise newException(ValueError,
          "Frontend integers must be within JavaScript's safe integer range")
    else:
      if int64(value) < -MaxSafeJavaScriptInteger or
          int64(value) > MaxSafeJavaScriptInteger:
        raise newException(ValueError,
          "Frontend integers must be within JavaScript's safe integer range")
    result = %value
  elif T is bool or T is string:
    result = %value
  else:
    {.error: "unsupported frontend result type".}
