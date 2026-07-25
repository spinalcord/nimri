type FrontendBridgeResponseKind = enum
  fbrAccepted

var
  frontendRequestQueue: Channel[string]
  frontendWakeEvent: AsyncEvent
  frontendWindowOpen: Atomic[bool]
  frontendRuntimeInitialized = false
  frontendLocksInitialized = false
  activeRequestIds = initHashSet[string]()
  activeRequestIdsLock: Lock
  frontendWakeLock: Lock

proc bridgeResponseKindName(kind: FrontendBridgeResponseKind): string =
  case kind
  of fbrAccepted: "accepted"

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

proc completionScript(requestId, response: string): string =
  let arguments = %*[requestId, parseJson(response)]
  result = "window.__nimriRpcComplete?.(..." & $arguments & ");"

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

    var queuedRequestId = ""
    try:
      let (request, _, _) = frontendRequest(queued.msg)
      queuedRequestId = requestId(request)
      let response = dispatchFrontendRequestAsync(queued.msg)
      let completionRequestId = queuedRequestId
      response.addCallback(proc() {.gcsafe.} =
        {.cast(gcsafe).}:
          completeFrontendRequest(window, completionRequestId, response)
      )
    except CatchableError as exception:
      if queuedRequestId.len > 0:
        let failedResponse = newFuture[string]("startQueuedFrontendRequests")
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
    # FIX: A finite ceiling lets asyncdispatch honor its next timer deadline.
    poll(int32.high.int)

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
  finally:
    release(activeRequestIdsLock)
