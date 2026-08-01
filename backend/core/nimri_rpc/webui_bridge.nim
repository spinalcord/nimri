type FrontendBridgeResponseKind = enum
  fbrAccepted

type FrontendStreamEventKind = enum
  fseValue
  fseComplete
  fseError

type ActiveFrontendStream = ref object
  stream: FrontendStream
  canceled: bool

var
  frontendRequestQueue: Channel[string]
  frontendWakeEvent: AsyncEvent
  frontendWindowOpen: Atomic[bool]
  frontendRuntimeInitialized = false
  frontendLocksInitialized = false
  activeRequestIds = initHashSet[string]()
  canceledStreamRequestIds = initHashSet[string]()
  activeFrontendStreams = initTable[string, ActiveFrontendStream]()
  activeRequestIdsLock: Lock
  frontendWakeLock: Lock

proc bridgeResponseKindName(kind: FrontendBridgeResponseKind): string =
  case kind
  of fbrAccepted: "accepted"

proc streamEventKindName(kind: FrontendStreamEventKind): string =
  case kind
  of fseValue: "value"
  of fseComplete: "complete"
  of fseError: "error"

proc requestId(request: JsonNode): string =
  if not request.hasKey("requestId") or request["requestId"].kind != JString:
    raise newException(
      ValueError, "Request field 'requestId' must be a string")
  result = request["requestId"].getStr()
  if result.len == 0:
    raise newException(
      ValueError, "Request field 'requestId' must not be empty")

proc reserveRequestId(requestId: string): bool =
  acquire(activeRequestIdsLock)
  try:
    if requestId notin activeRequestIds:
      activeRequestIds.incl(requestId)
      result = true
  finally:
    release(activeRequestIdsLock)

proc releaseRequestId(requestId: string) =
  acquire(activeRequestIdsLock)
  try:
    activeRequestIds.excl(requestId)
  finally:
    release(activeRequestIdsLock)

proc requestStreamCancellation(requestId: string): bool =
  acquire(activeRequestIdsLock)
  try:
    if requestId in activeRequestIds:
      canceledStreamRequestIds.incl(requestId)
      result = true
  finally:
    release(activeRequestIdsLock)

proc streamCancellationRequested(requestId: string): bool =
  acquire(activeRequestIdsLock)
  try:
    result = requestId in canceledStreamRequestIds
  finally:
    release(activeRequestIdsLock)

proc clearStreamCancellation(requestId: string) =
  acquire(activeRequestIdsLock)
  try:
    canceledStreamRequestIds.excl(requestId)
  finally:
    release(activeRequestIdsLock)

proc queueFrontendRequest(requestJson: string): bool =
  acquire(frontendWakeLock)
  try:
    if not frontendRuntimeInitialized or
        not frontendWindowOpen.load(moAcquire):
      return false
    frontendRequestQueue.send(requestJson)
    frontendWakeEvent.trigger()
    result = true
  finally:
    release(frontendWakeLock)

proc acceptedResponse(requestId: string): string =
  $(%* {
    "kind": bridgeResponseKindName(fbrAccepted),
    "requestId": requestId,
  })

proc cancellationResponse(): string =
  $(%* {"ok": true})

proc completionScript(requestId, response: string): string =
  let arguments = %*[requestId, parseJson(response)]
  result = "window.__nimriRpcComplete?.(..." & $arguments & ");"

proc streamEventScript(requestId: string, event: JsonNode): string =
  let arguments = %*[requestId, event]
  result = "window.__nimriRpcStreamEvent?.(..." & $arguments & ");"

proc sendFrontendStreamEvent(
    window: Window, requestId: string, event: JsonNode) =
  acquire(frontendWakeLock)
  try:
    if frontendRuntimeInitialized and frontendWindowOpen.load(moAcquire):
      window.run(streamEventScript(requestId, event))
  finally:
    release(frontendWakeLock)

proc releaseFrontendStream(
    requestId: string, activeStream: ActiveFrontendStream) =
  if activeFrontendStreams.hasKey(requestId) and
      activeFrontendStreams[requestId] == activeStream:
    activeFrontendStreams.del(requestId)
    releaseRequestId(requestId)
  clearStreamCancellation(requestId)

proc forwardFrontendStream(window: Window, requestId: string,
    activeStream: ActiveFrontendStream): Future[void] {.async.} =
  try:
    while not activeStream.canceled:
      let item = await activeStream.stream.readNext()
      if activeStream.canceled:
        return
      if not item.hasValue:
        sendFrontendStreamEvent(window, requestId, %* {
          "kind": streamEventKindName(fseComplete),
        })
        return
      sendFrontendStreamEvent(window, requestId, %* {
        "kind": streamEventKindName(fseValue),
        "value": item.value,
      })
  except CatchableError as exception:
    if not activeStream.canceled:
      activeStream.canceled = true
      activeStream.stream.cancel()
      sendFrontendStreamEvent(window, requestId, %* {
        "kind": streamEventKindName(fseError),
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

proc cancelRequestedFrontendStreams() =
  var requestIds: seq[string]
  for requestId in activeFrontendStreams.keys:
    if streamCancellationRequested(requestId):
      requestIds.add(requestId)
  for requestId in requestIds:
    cancelFrontendStream(requestId)

proc cancelAllFrontendStreams() =
  var requestIds: seq[string]
  for requestId in activeFrontendStreams.keys:
    requestIds.add(requestId)
  for requestId in requestIds:
    cancelFrontendStream(requestId)

proc completeFrontendRequest(
    window: Window, requestId: string, response: Future[string]) =
  releaseRequestId(requestId)

  let responseJson =
    if response.failed:
      errorResponse(asyncErrorMessage(response.error))
    else:
      response.read

  acquire(frontendWakeLock)
  try:
    if frontendRuntimeInitialized and frontendWindowOpen.load(moAcquire):
      window.run(completionScript(requestId, responseJson))
  finally:
    release(frontendWakeLock)

proc startQueuedFrontendRequests(window: Window) =
  while true:
    let queued = frontendRequestQueue.tryRecv()
    if not queued.dataAvailable:
      break

    var
      queuedRequestId = ""
      queuedCommandName = ""
    try:
      let (request, commandName, _) = frontendRequest(queued.msg)
      queuedRequestId = requestId(request)
      queuedCommandName = commandName
      let command = frontendCommands[commandName]
      if command.kind == fckStreaming:
        if streamCancellationRequested(queuedRequestId):
          clearStreamCancellation(queuedRequestId)
          releaseRequestId(queuedRequestId)
          continue

        let activeStream = ActiveFrontendStream(
          stream: openFrontendStream(queued.msg)
        )
        activeFrontendStreams[queuedRequestId] = activeStream
        if streamCancellationRequested(queuedRequestId):
          cancelFrontendStream(queuedRequestId)
        else:
          asyncCheck forwardFrontendStream(
            window, queuedRequestId, activeStream)
      else:
        let response = dispatchFrontendRequestAsync(queued.msg)
        let completionRequestId = queuedRequestId
        response.addCallback(proc() {.gcsafe.} =
          {.cast(gcsafe).}:
            completeFrontendRequest(window, completionRequestId, response)
        )
    except CatchableError as exception:
      if queuedRequestId.len > 0:
        if frontendCommands.hasKey(queuedCommandName) and
            frontendCommands[queuedCommandName].kind == fckStreaming:
          releaseRequestId(queuedRequestId)
          clearStreamCancellation(queuedRequestId)
          sendFrontendStreamEvent(window, queuedRequestId, %* {
            "kind": streamEventKindName(fseError),
            "error": exception.msg,
          })
        else:
          let failedResponse =
            newFuture[string]("startQueuedFrontendRequests")
          failedResponse.complete(errorResponse(exception.msg))
          completeFrontendRequest(window, queuedRequestId, failedResponse)

proc bindFrontendCommands*(window: Window) =
  ## Installs the single WebUI binding used by every frontend command.
  if frontendRuntimeInitialized:
    raise newException(
      ValueError, "Frontend RPC is already bound to a window")

  if not frontendLocksInitialized:
    initLock(activeRequestIdsLock)
    initLock(frontendWakeLock)
    frontendLocksInitialized = true

  frontendRequestQueue.open()
  frontendWakeEvent = newAsyncEvent()
  frontendWindowOpen.store(true, moRelease)
  frontendRuntimeInitialized = true
  frontendWakeEvent.addEvent(
    proc(_: AsyncFD): bool {.gcsafe.} =
      false
  )

  window.bind("__invoke", proc(event: Event): string =
    let requestJson = event.getString()
    try:
      let (request, commandName, _) = frontendRequest(requestJson)
      if not frontendCommands.hasKey(commandName) or
          frontendCommands[commandName].kind == fckSynchronous:
        return dispatchFrontendRequest(requestJson)

      let id = requestId(request)
      if not reserveRequestId(id):
        return errorResponse("Duplicate frontend request ID '" & id & "'")
      if not queueFrontendRequest(requestJson):
        releaseRequestId(id)
        return errorResponse("The frontend RPC window is closed")
      result = acceptedResponse(id)
    except CatchableError as exception:
      result = errorResponse(exception.msg)
  )

  window.bind("__nimriRpcCancel", proc(event: Event): string =
    let id = event.getString()
    if id.len == 0:
      return errorResponse("Frontend stream request ID must not be empty")

    if requestStreamCancellation(id):
      acquire(frontendWakeLock)
      try:
        if frontendRuntimeInitialized and frontendWindowOpen.load(moAcquire):
          frontendWakeEvent.trigger()
      finally:
        release(frontendWakeLock)
    result = cancellationResponse()
  )

  window.bind("", proc(event: Event) =
    if event.eventType == EventsDisconnected:
      acquire(frontendWakeLock)
      try:
        if frontendRuntimeInitialized:
          frontendWindowOpen.store(false, moRelease)
          frontendWakeEvent.trigger()
      finally:
        release(frontendWakeLock)
  )

proc runFrontendEventLoop*(window: Window) =
  ## Runs queued async commands and their completions on the main thread.
  if not frontendRuntimeInitialized:
    raise newException(
      ValueError, "bindFrontendCommands must be called before the event loop")

  while frontendWindowOpen.load(moAcquire):
    if not window.shown:
      frontendWindowOpen.store(false, moRelease)
      break
    startQueuedFrontendRequests(window)
    cancelRequestedFrontendStreams()
    # FIX: A finite ceiling lets asyncdispatch honor its next timer deadline.
    poll(int32.high.int)

  cancelAllFrontendStreams()

  acquire(frontendWakeLock)
  try:
    frontendRuntimeInitialized = false
    frontendWakeEvent.unregister()
    frontendWakeEvent.close()
    frontendRequestQueue.close()
  finally:
    release(frontendWakeLock)

  acquire(activeRequestIdsLock)
  try:
    activeRequestIds.clear()
    canceledStreamRequestIds.clear()
  finally:
    release(activeRequestIdsLock)
