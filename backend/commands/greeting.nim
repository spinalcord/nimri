import frontend_rpc
import tinydialogs

type Greeting* = object
  some_message*: string

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(some_message: "Hello, " & name & " – directly from Nim!")
