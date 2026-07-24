import std/[json, options, strutils, unittest]
import ../backend/core/frontend_rpc

{.push warning[UnusedImport]: off.}
import fixtures/frontend_rpc/first
import fixtures/frontend_rpc/second
{.pop.}

type
  TestGreeting* = object
    message*: string
    length*: int

  Mood* = enum
    calm, busy

proc testGreeting(name: string): TestGreeting {.accessible.} =
  TestGreeting(message: "Hello, " & name, length: name.len)

proc add(left, right: int): int {.accessible.} =
  left + right

proc alwaysFails(reason: string): string {.accessible.} =
  raise newException(ValueError, "Command failed: " & reason)

var recordedEvent = ""

proc recordEvent(alter: int, hello: bool) {.accessible.} =
  recordedEvent = $alter & ":" & $hello

proc echoMood(mood: Mood): Mood {.accessible.} =
  mood

proc optionalLength(value: Option[string]): Option[int] {.accessible.} =
  if value.isSome:
    some(value.get.len)
  else:
    none(int)

proc greetingWithDefault(name: string = "World"): string {.accessible.} =
  "Hello, " & name

proc dependentDefault(first: int, second: int = first + 1): int {.accessible.} =
  second

proc responseFor(command: string, args: JsonNode): JsonNode =
  parseJson(dispatchFrontendRequest($(%* {
    "command": command,
    "args": args,
  })))

suite "frontend RPC":
  test "registered command converts arguments and returns an object":
    let response = responseFor(
      "test_frontend_rpc.testGreeting", %* {"name": "Mara"})

    check response["ok"].getBool()
    check response["value"]["message"].getStr() == "Hello, Mara"
    check response["value"]["length"].getInt() == 4

  test "multiple named arguments are converted":
    let response = responseFor(
      "test_frontend_rpc.add", %* {"left": 20, "right": 22})

    check response["ok"].getBool()
    check response["value"].getInt() == 42

  test "commands without a return type produce JSON null":
    recordedEvent = ""
    let response = responseFor(
      "test_frontend_rpc.recordEvent", %* {"alter": 32, "hello": true})

    check response["ok"].getBool()
    check response["value"].kind == JNull
    check recordedEvent == "32:true"

  test "unknown commands are rejected":
    let response = responseFor("notRegistered", newJObject())

    check not response["ok"].getBool()
    check "Unknown frontend command" in response["error"].getStr()

  test "invalid JSON is rejected":
    let response = parseJson(dispatchFrontendRequest("not JSON"))

    check not response["ok"].getBool()
    check response.hasKey("error")

  test "missing arguments are rejected":
    let response = responseFor("test_frontend_rpc.testGreeting", newJObject())

    check not response["ok"].getBool()
    check "Missing required argument 'name'" in response["error"].getStr()

  test "missing default arguments use their Nim default":
    let response =
      responseFor("test_frontend_rpc.greetingWithDefault", newJObject())

    check response["ok"].getBool()
    check response["value"].getStr() == "Hello, World"

  test "explicit arguments override their Nim default":
    let response = responseFor(
      "test_frontend_rpc.greetingWithDefault", %* {"name": "Mara"})

    check response["ok"].getBool()
    check response["value"].getStr() == "Hello, Mara"

  test "defaults can reference earlier parameters":
    let response = responseFor(
      "test_frontend_rpc.dependentDefault", %* {"first": 41})

    check response["ok"].getBool()
    check response["value"].getInt() == 42

  test "explicit null does not activate a default":
    let response = responseFor(
      "test_frontend_rpc.greetingWithDefault", %* {"name": nil})

    check not response["ok"].getBool()
    check "Frontend string value expected" in response["error"].getStr()

  test "wrongly typed arguments are rejected":
    let response = responseFor(
      "test_frontend_rpc.add", %* {"left": "twenty", "right": 22})

    check not response["ok"].getBool()
    check response.hasKey("error")

  test "command exceptions become error responses":
    let response = responseFor(
      "test_frontend_rpc.alwaysFails", %* {"reason": "expected"})

    check not response["ok"].getBool()
    check response["error"].getStr() == "Command failed: expected"

  test "enums use their symbols on the wire":
    let response = responseFor(
      "test_frontend_rpc.echoMood", %* {"mood": "busy"})

    check response["ok"].getBool()
    check response["value"].getStr() == "busy"

  test "options map JSON null and values":
    let noneResponse = responseFor(
      "test_frontend_rpc.optionalLength", %* {"value": nil})
    let someResponse = responseFor(
      "test_frontend_rpc.optionalLength", %* {"value": "Nim"})

    check noneResponse["ok"].getBool()
    check noneResponse["value"].kind == JNull
    check someResponse["ok"].getBool()
    check someResponse["value"].getInt() == 3

  test "same procedure names in different modules remain distinct":
    let firstResponse = responseFor("first.same_name", %* {"value": 7})
    let secondResponse = responseFor("second.same_name", %* {"value": 7})

    check firstResponse["value"].getStr() == "first:7"
    check secondResponse["value"].getStr() == "second:7"

  test "legacy unqualified command names are not registered":
    let response = responseFor("add", %* {"left": 20, "right": 22})

    check not response["ok"].getBool()
    check "Unknown frontend command" in response["error"].getStr()
