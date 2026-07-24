import std/asyncdispatch
import frontend_rpc
import tinydialogs

type Greeting* = object
  some_message*: string

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(some_message: "Hello, " & name & " – directly from Nim!")

proc loadGreeting*(name: string): Future[Greeting] {.
    async, accessible.} =
  await sleepAsync(2000)
  result = Greeting(some_message: "Hello, " & name & " – directly from Nim!")
