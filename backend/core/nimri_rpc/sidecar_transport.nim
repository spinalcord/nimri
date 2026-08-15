type
  SidecarInputKind = enum
    sikLine
    sikEndOfInput

  SidecarInput = object
    case kind: SidecarInputKind
    of sikLine:
      line: string
    of sikEndOfInput:
      discard

  SidecarRequestKind = enum
    srkInvoke
    srkCancel

  ActiveFrontendStream = ref object
    stream: FrontendStream
    canceled: bool

var
  sidecarInputQueue: Channel[SidecarInput]
  sidecarWakeEvent: AsyncEvent
  sidecarRunning = false
  activeRequestIds = initHashSet[string]()
  activeFrontendStreams = initTable[string, ActiveFrontendStream]()

proc readSidecarInput() {.thread.} =
  var line: string
  while stdin.readLine(line):
    sidecarInputQueue.send(SidecarInput(kind: sikLine, line: line))
    sidecarWakeEvent.trigger()

  sidecarInputQueue.send(SidecarInput(kind: sikEndOfInput))
  sidecarWakeEvent.trigger()

proc writeProtocolMessage(message: JsonNode) =
  stdout.writeLine($message)
  stdout.flushFile()

proc sidecarRequestKind(message: JsonNode): SidecarRequestKind =
  if not message.hasKey("kind") or message["kind"].kind != JString:
    raise newException(ValueError, "Request field 'kind' must be a string")

  case message["kind"].getStr()
  of "invoke": srkInvoke
  of "cancel": srkCancel
  else:
    raise newException(ValueError,
      "Unknown sidecar message kind '" & message["kind"].getStr() & "'")

proc sidecarRequestId(message: JsonNode): string =
  if not message.hasKey("requestId") or
      message["requestId"].kind != JString:
    raise newException(
      ValueError, "Request field 'requestId' must be a string")
  result = message["requestId"].getStr()
  if result.len == 0:
    raise newException(
      ValueError, "Request field 'requestId' must not be empty")

proc sendResult(requestId, responseJson: string) =
  var response = parseJson(responseJson)
  response["kind"] = %"result"
  response["requestId"] = %requestId
  writeProtocolMessage(response)

proc sendError(requestId, message: string) =
  sendResult(requestId, errorResponse(message))

proc sendAccepted(requestId: string) =
  writeProtocolMessage(%* {
    "kind": "accepted",
    "requestId": requestId,
  })

proc releaseFrontendStream(
    requestId: string, activeStream: ActiveFrontendStream) =
  if activeFrontendStreams.hasKey(requestId) and
      activeFrontendStreams[requestId] == activeStream:
    activeFrontendStreams.del(requestId)
    activeRequestIds.excl(requestId)

proc forwardFrontendStream(requestId: string,
    activeStream: ActiveFrontendStream): Future[void] {.async.} =
  try:
    while not activeStream.canceled:
      let item = await activeStream.stream.readNext()
      if activeStream.canceled:
        return
      if not item.hasValue:
        writeProtocolMessage(%* {
          "kind": "streamComplete",
          "requestId": requestId,
        })
        return
      writeProtocolMessage(%* {
        "kind": "streamValue",
        "requestId": requestId,
        "value": item.value,
      })
  except CatchableError as exception:
    if not activeStream.canceled:
      activeStream.canceled = true
      activeStream.stream.cancel()
      writeProtocolMessage(%* {
        "kind": "streamError",
        "requestId": requestId,
        "error": asyncErrorMessage(exception),
      })
  finally:
    releaseFrontendStream(requestId, activeStream)

proc cancelFrontendStream(requestId: string) =
  if not activeFrontendStreams.hasKey(requestId):
    return

  let activeStream = activeFrontendStreams[requestId]
  activeStream.canceled = true
  activeStream.stream.cancel()
  releaseFrontendStream(requestId, activeStream)

proc cancelAllFrontendStreams() =
  var requestIds: seq[string]
  for requestId in activeFrontendStreams.keys:
    requestIds.add(requestId)
  for requestId in requestIds:
    cancelFrontendStream(requestId)

proc completeFrontendRequest(requestId: string, response: Future[string]) =
  activeRequestIds.excl(requestId)
  if response.failed:
    sendError(requestId, asyncErrorMessage(response.error))
  else:
    sendResult(requestId, response.read)

proc invokeFrontendCommand(message: JsonNode) =
  let
    requestId = sidecarRequestId(message)
    requestJson = $message
    (_, commandName, _) = frontendRequest(requestJson)

  if requestId in activeRequestIds:
    sendError(requestId, "Duplicate frontend request ID '" & requestId & "'")
    return
  if not frontendCommands.hasKey(commandName):
    sendError(requestId, "Unknown frontend command '" & commandName & "'")
    return

  activeRequestIds.incl(requestId)
  let command = frontendCommands[commandName]
  case command.kind
  of fckSynchronous:
    sendResult(requestId, dispatchFrontendRequest(requestJson))
    activeRequestIds.excl(requestId)
  of fckAsynchronous:
    let response = dispatchFrontendRequestAsync(requestJson)
    let completionRequestId = requestId
    response.addCallback(proc() {.gcsafe.} =
      {.cast(gcsafe).}:
        completeFrontendRequest(completionRequestId, response)
    )
    sendAccepted(requestId)
  of fckStreaming:
    try:
      let activeStream = ActiveFrontendStream(
        stream: openFrontendStream(requestJson)
      )
      activeFrontendStreams[requestId] = activeStream
      sendAccepted(requestId)
      asyncCheck forwardFrontendStream(requestId, activeStream)
    except CatchableError as exception:
      activeRequestIds.excl(requestId)
      sendError(requestId, exception.msg)

proc cancelFrontendCommand(message: JsonNode) =
  let requestId = sidecarRequestId(message)
  cancelFrontendStream(requestId)
  sendResult(requestId, $(%* {"ok": true, "value": nil}))

proc handleSidecarLine(line: string) =
  var
    message: JsonNode
    requestId = ""
  try:
    message = parseJson(line)
    if message.kind != JObject:
      raise newException(ValueError, "Request must be a JSON object")
    if message.hasKey("requestId") and message["requestId"].kind == JString:
      requestId = message["requestId"].getStr()

    case sidecarRequestKind(message)
    of srkInvoke:
      invokeFrontendCommand(message)
    of srkCancel:
      cancelFrontendCommand(message)
  except CatchableError as exception:
    if requestId.len > 0:
      sendError(requestId, exception.msg)
    else:
      stderr.writeLine("Rejected sidecar message: " & exception.msg)

proc processSidecarInput() =
  while true:
    let queued = sidecarInputQueue.tryRecv()
    if not queued.dataAvailable:
      break

    case queued.msg.kind
    of sikLine:
      handleSidecarLine(queued.msg.line)
    of sikEndOfInput:
      cancelAllFrontendStreams()
      sidecarRunning = false

proc serveFrontendRpc*() =
  ## Serves Electron RPC over newline-delimited JSON on standard IO.
  if sidecarRunning:
    raise newException(ValueError, "The sidecar RPC runtime is already active")

  sidecarInputQueue.open()
  sidecarWakeEvent = newAsyncEvent()
  sidecarRunning = true
  sidecarWakeEvent.addEvent(proc(_: AsyncFD): bool {.gcsafe.} =
    {.cast(gcsafe).}:
      processSidecarInput()
    false
  )

  var inputThread: Thread[void]
  createThread(inputThread, readSidecarInput)
  writeProtocolMessage(%* {"kind": "ready"})

  while sidecarRunning:
    poll(int32.high.int)

  joinThread(inputThread)
  cancelAllFrontendStreams()
  activeRequestIds.clear()
  sidecarWakeEvent.unregister()
  sidecarWakeEvent.close()
  sidecarInputQueue.close()
