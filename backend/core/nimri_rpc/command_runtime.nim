type
  FrontendSyncCommand = proc(args: JsonNode): JsonNode {.closure.}
  FrontendAsyncCommand =
    proc(args: JsonNode): Future[JsonNode] {.closure.}

  FrontendCommand = object
    kind: FrontendCommandKind
    syncAdapter: FrontendSyncCommand
    asyncAdapter: FrontendAsyncCommand

var frontendCommands = initTable[string, FrontendCommand]()

proc registerFrontendCommand(name: string, command: FrontendCommand) =
  if frontendCommands.hasKey(name):
    raise newException(ValueError,
      "A frontend command named '" & name & "' is already registered")
  frontendCommands[name] = command

proc registerFrontendSyncCommand(name: string, command: FrontendSyncCommand) =
  registerFrontendCommand(name, FrontendCommand(
    kind: fckSynchronous,
    syncAdapter: command
  ))

proc registerFrontendAsyncCommand(
    name: string, command: FrontendAsyncCommand) =
  registerFrontendCommand(name, FrontendCommand(
    kind: fckAsynchronous,
    asyncAdapter: command
  ))

proc errorResponse(message: string): string =
  $(%* {"ok": false, "error": message})

proc asyncErrorMessage(exception: ref Exception): string =
  const TracebackMarker = "\nAsync traceback:"
  let markerIndex = exception.msg.find(TracebackMarker)
  if markerIndex >= 0:
    result = exception.msg[0 ..< markerIndex]
  else:
    result = exception.msg

proc frontendRequest(requestJson: string): tuple[
    request: JsonNode, commandName: string, args: JsonNode] =
  let request = parseJson(requestJson)
  if request.kind != JObject:
    raise newException(ValueError, "Request must be a JSON object")
  if not request.hasKey("command") or request["command"].kind != JString:
    raise newException(ValueError, "Request field 'command' must be a string")

  let args = if request.hasKey("args"): request["args"] else: newJObject()
  if args.kind != JObject:
    raise newException(ValueError, "Request field 'args' must be a JSON object")

  result = (request, request["command"].getStr(), args)

proc dispatchFrontendRequest*(requestJson: string): string =
  ## Dispatches one JSON request. Exported so the protocol can be tested
  ## without opening a browser window.
  try:
    let (_, commandName, args) = frontendRequest(requestJson)
    if not frontendCommands.hasKey(commandName):
      return errorResponse("Unknown frontend command '" & commandName & "'")

    let command = frontendCommands[commandName]
    if command.kind == fckAsynchronous:
      return errorResponse(
        "Frontend command '" & commandName & "' is asynchronous; use " &
        "dispatchFrontendRequestAsync")

    let value = command.syncAdapter(args)
    result = $(%* {"ok": true, "value": value})
  except CatchableError as exception:
    result = errorResponse(exception.msg)

proc dispatchFrontendRequestAsync*(
    requestJson: string): Future[string] {.async.} =
  ## Dispatches either command kind on the current async dispatcher.
  try:
    let (_, commandName, args) = frontendRequest(requestJson)
    if not frontendCommands.hasKey(commandName):
      return errorResponse("Unknown frontend command '" & commandName & "'")

    let command = frontendCommands[commandName]
    let value =
      case command.kind
      of fckSynchronous:
        command.syncAdapter(args)
      of fckAsynchronous:
        await command.asyncAdapter(args)
    result = $(%* {"ok": true, "value": value})
  except CatchableError as exception:
    result = errorResponse(asyncErrorMessage(exception))
