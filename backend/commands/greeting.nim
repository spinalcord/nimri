import nimri_rpc

type Greeting* = object
  message*: string

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(message: "Hello, " & name & " – directly from Nim!")
