import nimri_rpc
import ../types

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(message: "Hello, " & name & " – directly from Nim!")
