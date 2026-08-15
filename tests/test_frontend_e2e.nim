import std/[json, os, osproc, streams, unittest]

const ExpectedGreeting = "Hello, Mara – directly from Nim!"

proc readMessage(process: Process): JsonNode =
  let line = process.outputStream.readLine()
  if line.len == 0:
    raise newException(IOError, "The sidecar closed its protocol output")
  result = parseJson(line)

proc sendMessage(process: Process, message: JsonNode) =
  process.inputStream.writeLine($message)
  process.inputStream.flush()

suite "Electron sidecar protocol":
  test "invokes commands and completes streams over standard IO":
    let sidecarPath = getEnv("NIMRI_TEST_SIDECAR")
    require sidecarPath.len > 0
    require fileExists(sidecarPath)

    let sidecar = startProcess(
      sidecarPath,
      workingDir = sidecarPath.parentDir,
      args = ["serve"],
      options = {poUsePath}
    )
    try:
      check readMessage(sidecar)["kind"].getStr() == "ready"

      sendMessage(sidecar, %* {
        "kind": "invoke",
        "requestId": "sync-request",
        "command": "greeting.greet",
        "args": {"name": "Mara"},
      })
      let resultMessage = readMessage(sidecar)
      check resultMessage["kind"].getStr() == "result"
      check resultMessage["requestId"].getStr() == "sync-request"
      check resultMessage["ok"].getBool()
      check resultMessage["value"]["message"].getStr() == ExpectedGreeting

      sendMessage(sidecar, %* {
        "kind": "invoke",
        "requestId": "future-request",
        "command": "greeting.determineEnumType",
        "args": {"someEnumType": "Bar"},
      })
      let futureAccepted = readMessage(sidecar)
      check futureAccepted["kind"].getStr() == "accepted"
      check futureAccepted["requestId"].getStr() == "future-request"
      let futureResult = readMessage(sidecar)
      check futureResult["kind"].getStr() == "result"
      check futureResult["requestId"].getStr() == "future-request"
      check futureResult["ok"].getBool()
      check futureResult["value"].getStr() == "Bar"

      sendMessage(sidecar, %* {
        "kind": "invoke",
        "requestId": "stream-request",
        "command": "greeting.streamMessages",
        "args": {},
      })
      let acceptedMessage = readMessage(sidecar)
      check acceptedMessage["kind"].getStr() == "accepted"
      check acceptedMessage["requestId"].getStr() == "stream-request"

      var values: seq[string]
      while true:
        let streamMessage = readMessage(sidecar)
        check streamMessage["requestId"].getStr() == "stream-request"
        if streamMessage["kind"].getStr() == "streamComplete":
          break
        check streamMessage["kind"].getStr() == "streamValue"
        values.add(streamMessage["value"].getStr())
      check values == @[
        "First message",
        "Second message",
        "Third message",
      ]

      sendMessage(sidecar, %* {
        "kind": "invoke",
        "requestId": "canceled-stream",
        "command": "greeting.streamMessages",
        "args": {},
      })
      check readMessage(sidecar)["kind"].getStr() == "accepted"
      sendMessage(sidecar, %* {
        "kind": "cancel",
        "requestId": "canceled-stream",
      })
      while true:
        let cancellationMessage = readMessage(sidecar)
        check cancellationMessage["requestId"].getStr() == "canceled-stream"
        if cancellationMessage["kind"].getStr() == "result":
          check cancellationMessage["ok"].getBool()
          break
        check cancellationMessage["kind"].getStr() == "streamValue"
    finally:
      sidecar.inputStream.close()
      check sidecar.waitForExit(2_000) == 0
      sidecar.close()
