import nimri_rpc
import ../types

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(message: "Hello, " & name & " – directly from Nim!")


proc determineEnumType(someEnumType: SomeEnumType): string {.accessible.} =
  if someEnumType == SomeEnumType.Foo:
    echo "Foo"
    return "Foo"
  elif someEnumType == SomeEnumType.Bar:
    echo "Bar"
    return "Bar"
  else: return "test"