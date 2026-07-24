import std/[asyncdispatch, json, math, options, strutils, unittest]
import ../backend/core/nimri_rpc

{.push warning[UnusedImport]: off.}
import fixtures/nimri_rpc/first
import fixtures/nimri_rpc/second
{.pop.}

type
  TestGreeting* = object
    message*: string
    length*: int

  Mood* = enum
    calm, busy

  NestedArguments* = object
    values*: array[2, int]
    labels*: seq[string]
    mood*: Mood
    optional*: Option[int]

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

proc echoNested(arguments: NestedArguments): NestedArguments {.accessible.} =
  arguments

proc echoInteger(value: int64): int64 {.accessible.} =
  value

proc optionalLength(value: Option[string]): Option[int] {.accessible.} =
  if value.isSome:
    some(value.get.len)
  else:
    none(int)

proc greetingWithDefault(name: string = "World"): string {.accessible.} =
  "Hello, " & name

proc dependentDefault(first: int, second: int = first + 1): int {.accessible.} =
  second

type ManualStringFuture = Future[string]

proc asyncGreeting(name: string): Future[TestGreeting] {.
    async, accessible.} =
  await sleepAsync(1)
  result = TestGreeting(message: "Async hello, " & name, length: name.len)

proc asyncString(value: string): Future[string] {.accessible, async.} =
  await sleepAsync(1)
  result = value

proc manualFuture(value: string): ManualStringFuture {.accessible.} =
  result = newFuture[string]("manualFuture")
  result.complete(value)

proc asyncEvent(value: string): Future[void] {.async, accessible.} =
  await sleepAsync(1)
  recordedEvent = value

proc failsBeforeAwait(): Future[string] {.async, accessible.} =
  raise newException(ValueError, "Failure before await")

proc failsAfterAwait(): Future[string] {.async, accessible.} =
  await sleepAsync(1)
  raise newException(ValueError, "Failure after await")

proc invalidAsyncNumber(): Future[float] {.async, accessible.} =
  await sleepAsync(1)
  result = Inf

proc delayedValue(value: string, delay: int): Future[string] {.
    async, accessible.} =
  await sleepAsync(delay)
  result = value

proc responseFor(command: string, args: JsonNode): JsonNode =
  parseJson(dispatchFrontendRequest($(%* {
    "command": command,
    "args": args,
  })))

proc asyncResponseFor(command: string, args: JsonNode): Future[JsonNode] {.
    async.} =
  result = parseJson(await dispatchFrontendRequestAsync($(%* {
    "command": command,
    "args": args,
  })))

suite "frontend RPC":
  test "registered command converts arguments and returns an object":
    let response = responseFor(
      "test_nimri_rpc.testGreeting", %* {"name": "Mara"})

    check response["ok"].getBool()
    check response["value"]["message"].getStr() == "Hello, Mara"
    check response["value"]["length"].getInt() == 4

  test "multiple named arguments are converted":
    let response = responseFor(
      "test_nimri_rpc.add", %* {"left": 20, "right": 22})

    check response["ok"].getBool()
    check response["value"].getInt() == 42

  test "commands without a return type produce JSON null":
    recordedEvent = ""
    let response = responseFor(
      "test_nimri_rpc.recordEvent", %* {"alter": 32, "hello": true})

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

  test "invalid request shapes are rejected":
    let nonObjectResponse =
      parseJson(dispatchFrontendRequest("[]"))
    let missingCommandResponse =
      parseJson(dispatchFrontendRequest($(%* {"args": {}})))
    let wrongCommandTypeResponse =
      parseJson(dispatchFrontendRequest($(%* {"command": 42})))
    let wrongArgsTypeResponse =
      parseJson(dispatchFrontendRequest($(%* {
        "command": "test_nimri_rpc.add",
        "args": [],
      })))

    check not nonObjectResponse["ok"].getBool()
    check "Request must be a JSON object" in
      nonObjectResponse["error"].getStr()
    check not missingCommandResponse["ok"].getBool()
    check "Request field 'command' must be a string" in
      missingCommandResponse["error"].getStr()
    check not wrongCommandTypeResponse["ok"].getBool()
    check "Request field 'command' must be a string" in
      wrongCommandTypeResponse["error"].getStr()
    check not wrongArgsTypeResponse["ok"].getBool()
    check "Request field 'args' must be a JSON object" in
      wrongArgsTypeResponse["error"].getStr()

  test "omitted args default to an empty object":
    let response = parseJson(dispatchFrontendRequest($(%* {
      "command": "test_nimri_rpc.greetingWithDefault",
    })))

    check response["ok"].getBool()
    check response["value"].getStr() == "Hello, World"

  test "missing arguments are rejected":
    let response = responseFor("test_nimri_rpc.testGreeting", newJObject())

    check not response["ok"].getBool()
    check "Missing required argument 'name'" in response["error"].getStr()

  test "missing default arguments use their Nim default":
    let response =
      responseFor("test_nimri_rpc.greetingWithDefault", newJObject())

    check response["ok"].getBool()
    check response["value"].getStr() == "Hello, World"

  test "explicit arguments override their Nim default":
    let response = responseFor(
      "test_nimri_rpc.greetingWithDefault", %* {"name": "Mara"})

    check response["ok"].getBool()
    check response["value"].getStr() == "Hello, Mara"

  test "defaults can reference earlier parameters":
    let response = responseFor(
      "test_nimri_rpc.dependentDefault", %* {"first": 41})

    check response["ok"].getBool()
    check response["value"].getInt() == 42

  test "explicit null does not activate a default":
    let response = responseFor(
      "test_nimri_rpc.greetingWithDefault", %* {"name": nil})

    check not response["ok"].getBool()
    check "Frontend string value expected" in response["error"].getStr()

  test "wrongly typed arguments are rejected":
    let response = responseFor(
      "test_nimri_rpc.add", %* {"left": "twenty", "right": 22})

    check not response["ok"].getBool()
    check response.hasKey("error")

  test "command exceptions become error responses":
    let response = responseFor(
      "test_nimri_rpc.alwaysFails", %* {"reason": "expected"})

    check not response["ok"].getBool()
    check response["error"].getStr() == "Command failed: expected"

  test "enums use their symbols on the wire":
    let response = responseFor(
      "test_nimri_rpc.echoMood", %* {"mood": "busy"})

    check response["ok"].getBool()
    check response["value"].getStr() == "busy"

  test "nested objects, arrays, sequences, enums, and options round-trip":
    let response = responseFor(
      "test_nimri_rpc.echoNested", %* {
        "arguments": {
          "values": [3, 5],
          "labels": ["nim", "svelte"],
          "mood": "busy",
          "optional": 7,
        },
      })

    check response["ok"].getBool()
    check response["value"]["values"].kind == JArray
    check response["value"]["values"][0].getInt() == 3
    check response["value"]["values"][1].getInt() == 5
    check response["value"]["labels"] == %*["nim", "svelte"]
    check response["value"]["mood"].getStr() == "busy"
    check response["value"]["optional"].getInt() == 7

  test "fixed arrays reject the wrong number of values":
    let response = responseFor(
      "test_nimri_rpc.echoNested", %* {
        "arguments": {
          "values": [3],
          "labels": [],
          "mood": "calm",
          "optional": nil,
        },
      })

    check not response["ok"].getBool()
    check "Frontend fixed array must contain exactly 2 values" in
      response["error"].getStr()

  test "integers stay within JavaScript's safe integer range":
    let safeResponse = responseFor(
      "test_nimri_rpc.echoInteger", %* {"value": 9007199254740991})
    let unsafeResponse = responseFor(
      "test_nimri_rpc.echoInteger", %* {"value": 9007199254740992})

    check safeResponse["ok"].getBool()
    check safeResponse["value"].getBiggestInt() == 9007199254740991
    check not unsafeResponse["ok"].getBool()
    check "safe integer range" in unsafeResponse["error"].getStr()

  test "options map JSON null and values":
    let noneResponse = responseFor(
      "test_nimri_rpc.optionalLength", %* {"value": nil})
    let someResponse = responseFor(
      "test_nimri_rpc.optionalLength", %* {"value": "Nim"})

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

  test "synchronous dispatch clearly rejects asynchronous commands":
    let response = responseFor(
      "test_nimri_rpc.asyncString", %* {"value": "Nim"})

    check not response["ok"].getBool()
    check "is asynchronous" in response["error"].getStr()

  test "asynchronous commands serialize strings and objects":
    let stringResponse = waitFor asyncResponseFor(
      "test_nimri_rpc.asyncString", %* {"value": "Nim"})
    let objectResponse = waitFor asyncResponseFor(
      "test_nimri_rpc.asyncGreeting", %* {"name": "Mara"})
    let manualResponse = waitFor asyncResponseFor(
      "test_nimri_rpc.manualFuture", %* {"value": "manual"})

    check stringResponse["ok"].getBool()
    check stringResponse["value"].getStr() == "Nim"
    check objectResponse["ok"].getBool()
    check objectResponse["value"]["message"].getStr() == "Async hello, Mara"
    check manualResponse["value"].getStr() == "manual"

  test "Future void commands serialize JSON null":
    recordedEvent = ""
    let response = waitFor asyncResponseFor(
      "test_nimri_rpc.asyncEvent", %* {"value": "finished"})

    check response["ok"].getBool()
    check response["value"].kind == JNull
    check recordedEvent == "finished"

  test "asynchronous exceptions before and after await become errors":
    let beforeResponse = waitFor asyncResponseFor(
      "test_nimri_rpc.failsBeforeAwait", newJObject())
    let afterResponse = waitFor asyncResponseFor(
      "test_nimri_rpc.failsAfterAwait", newJObject())

    check not beforeResponse["ok"].getBool()
    check beforeResponse["error"].getStr() == "Failure before await"
    check not afterResponse["ok"].getBool()
    check afterResponse["error"].getStr() == "Failure after await"

  test "asynchronous argument and serialization failures become errors":
    let argumentResponse = waitFor asyncResponseFor(
      "test_nimri_rpc.asyncString", %* {"value": 42})
    let serializationResponse = waitFor asyncResponseFor(
      "test_nimri_rpc.invalidAsyncNumber", newJObject())

    check not argumentResponse["ok"].getBool()
    check "Frontend string value expected" in
      argumentResponse["error"].getStr()
    check not serializationResponse["ok"].getBool()
    check "must be finite" in serializationResponse["error"].getStr()

  test "asynchronous dispatch rejects unknown commands":
    let response = waitFor asyncResponseFor("unknown.async", newJObject())

    check not response["ok"].getBool()
    check "Unknown frontend command" in response["error"].getStr()

  test "concurrent futures can finish in reverse order":
    let
      slower = asyncResponseFor(
        "test_nimri_rpc.delayedValue",
        %* {"value": "slower", "delay": 30})
      faster = asyncResponseFor(
        "test_nimri_rpc.delayedValue",
        %* {"value": "faster", "delay": 1})
    var completionOrder: seq[string]
    slower.addCallback(proc() {.gcsafe.} =
      {.cast(gcsafe).}:
        completionOrder.add("slower")
    )
    faster.addCallback(proc() {.gcsafe.} =
      {.cast(gcsafe).}:
        completionOrder.add("faster")
    )

    while not slower.finished or not faster.finished:
      poll()

    check completionOrder == @["faster", "slower"]
    check slower.read["value"].getStr() == "slower"
    check faster.read["value"].getStr() == "faster"
