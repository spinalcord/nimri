import std/[asyncdispatch, asyncstreams]
import nimri_rpc
import ../types

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(message: "Hello, " & name & " – directly from Nim!")


proc determineEnumType(someEnumType: SomeEnumType): Future[string] {.
    async, accessible.} =
  await sleepAsync(1)
  if someEnumType == SomeEnumType.Foo:
    return "Foo"
  elif someEnumType == SomeEnumType.Bar:
    return "Bar"
  else: return "test"


proc produceStreamMessages(stream: FutureStream[string]): Future[void] {.async.} =
  try:
    for message in ["First message", "Second message", "Third message"]:
      await stream.write(message)
      await sleepAsync(500)
    stream.complete()
  except ValueError:
    discard
  except CatchableError as exception:
    stream.fail(exception)


proc streamMessages*(): FutureStream[string] {.accessible.} =
  result = newFutureStream[string]("belongsto-streamMessages")
  asyncCheck produceStreamMessages(result)
