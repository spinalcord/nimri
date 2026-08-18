import std/[asyncdispatch, asyncstreams]
import nimri_rpc
import ../types

proc frameworkInfo*(): ShowcaseOverview {.accessible.} =
  ShowcaseOverview(
    application: "Nimri minimal showcase",
    framework: "Nim 2 + Svelte",
    transport: "Typed RPC over standard I/O",
    detail: "The synchronous command returned immediately from the Nim sidecar."
  )

proc loadOverview*(): Future[ShowcaseOverview] {.async, accessible.} =
  await sleepAsync(700)
  ShowcaseOverview(
    application: "Nimri minimal showcase",
    framework: "Nim 2 + Svelte",
    transport: "Generated TypeScript bindings",
    detail: "The Future resolved after a simulated asynchronous data fetch."
  )

proc produceActivity(stream: FutureStream[ActivityEvent]): Future[void] {.async.} =
  try:
    let events = [
      ActivityEvent(
        phase: queued,
        message: "The typed stream is ready.",
        elapsedMilliseconds: 0
      ),
      ActivityEvent(
        phase: connecting,
        message: "Nim is preparing the next activity update.",
        elapsedMilliseconds: 350
      ),
      ActivityEvent(
        phase: processing,
        message: "The frontend is receiving a typed event.",
        elapsedMilliseconds: 700
      ),
      ActivityEvent(
        phase: completed,
        message: "The activity stream completed normally.",
        elapsedMilliseconds: 1050
      )
    ]
    for event in events:
      await stream.write(event)
      await sleepAsync(350)
    stream.complete()
  except ValueError:
    # Cancellation closes the stream and makes later writes fail.
    discard
  except CatchableError as exception:
    stream.fail(exception)

proc streamActivity*(): FutureStream[ActivityEvent] {.accessible.} =
  result = newFutureStream[ActivityEvent]("showcase.streamActivity")
  asyncCheck produceActivity(result)
