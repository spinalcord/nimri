import std/[asyncdispatch, json, os, strutils]
import webui
import webui/bindings

# Importing the aggregator registers the production frontend commands.
{.push warning[UnusedImport]: off.}
import ../backend/core/commands
{.pop.}

import ../backend/core/frontend_rpc

when not defined(release):
  import std/[net, osproc]

const
  ProjectRoot = currentSourcePath().parentDir.parentDir
  FrontendDir = ProjectRoot / "frontend"
  WebUiBridgePort = 7681
  ExpectedGreeting = "Hello, Mara – directly from Nim!"
  ExpectedAsyncValue = "Async RPC completed"

when not defined(release):
  const
    DevServerHost = "127.0.0.1"
    DevServerPort = 5173

when not defined(release):
  proc portIsReady(port: int): bool =
    var socket = newSocket()
    try:
      socket.connect(DevServerHost, Port(port), timeout = 200)
      result = true
    except CatchableError:
      result = false
    finally:
      socket.close()

  proc waitForPort(process: Process, port: int) =
    for _ in 0 ..< 100:
      if not process.running:
        raise newException(IOError,
          "Vite stopped with exit code " & $process.peekExitCode)
      if portIsReady(port):
        return
      sleep(100)
    raise newException(IOError, "Timed out waiting for Vite")

proc delayedE2eValue(value: string): Future[string] {.async, accessible.} =
  await sleepAsync(150)
  result = value

let window = webui.newWindow()
window.hidden = true
window.port = WebUiBridgePort
bindFrontendCommands(window)

when defined(release):
  window.rootFolder = FrontendDir / "dist"
  doAssert window.show("index.html", bindings.Browsers.Chromium),
    "WebUI could not open the release frontend"
else:
  var viteProcess: Process
  try:
    viteProcess = startProcess(
      "node",
      workingDir = FrontendDir,
      args = ["node_modules/vite/bin/vite.js"],
      options = {poUsePath, poParentStreams}
    )
    waitForPort(viteProcess, DevServerPort)
    doAssert window.show(
      "http://" & DevServerHost & ":" & $DevServerPort,
      bindings.Browsers.Chromium
    ), "WebUI could not open the Vite frontend"
  except:
    if viteProcess != nil:
      if viteProcess.running:
        viteProcess.terminate()
        discard viteProcess.waitForExit(2_000)
      viteProcess.close()
    raise

proc verifyFrontend(): Future[void] {.async.} =
  try:
    let clickResult = window.script(
      "document.querySelector('button')?.click(); return true;",
      timeout = 2
    )
    doAssert not clickResult.error, "Could not click the RPC button"

    var renderedGreeting = ""
    for _ in 0 ..< 50:
      let response = window.script(
        "return document.querySelector('h1')?.textContent ?? '';",
        timeout = 2
      )
      if not response.error:
        renderedGreeting = response.data
        if ExpectedGreeting in renderedGreeting:
          break
      await sleepAsync(100)

    doAssert ExpectedGreeting in renderedGreeting,
      "Expected the Nim greeting, got: " & renderedGreeting & ". Body: " &
        window.script("return document.body.textContent;", timeout = 2).data

    let asyncLaunch = window.script("""
      if (typeof window.__invoke !== 'function') return false;
      const requestId = crypto.randomUUID();
      const originalCompletion = window.__nimriRpcComplete;
      window.__nimriE2eAsync = {
        requestId,
        response: null,
        bridgeResponses: null,
      };
      window.__nimriRpcComplete = (completedId, response) => {
        if (completedId === requestId) {
          window.__nimriE2eAsync.response = response;
        }
        originalCompletion?.(completedId, response);
      };
      const request = JSON.stringify({
        requestId,
        command: 'test_frontend_e2e.delayedE2eValue',
        args: { value: 'Async RPC completed' },
      });
      void Promise.all([
        window.__invoke(request),
        window.__invoke(request),
      ]).then((responses) => {
        window.__nimriE2eAsync.bridgeResponses =
          responses.map((response) => JSON.parse(response));
      });
      document.querySelector('h1').textContent = 'UI remained responsive';
      return document.querySelector('h1').textContent ===
        'UI remained responsive';
    """, timeout = 2)
    doAssert not asyncLaunch.error and asyncLaunch.data == "true",
      "The frontend did not remain responsive while starting async RPC"

    var asyncState = newJNull()
    for _ in 0 ..< 50:
      let response = window.script(
        "return JSON.stringify(window.__nimriE2eAsync);",
        timeout = 2
      )
      if not response.error:
        asyncState = parseJson(response.data)
        if asyncState["response"].kind != JNull and
            asyncState["bridgeResponses"].kind != JNull:
          break
      await sleepAsync(20)

    var
      acceptedCount = 0
      duplicateCount = 0
    for bridgeResponse in asyncState["bridgeResponses"]:
      if bridgeResponse.hasKey("kind") and
          bridgeResponse["kind"].getStr() == "accepted":
        inc acceptedCount
      elif not bridgeResponse["ok"].getBool() and
          "Duplicate frontend request ID" in
            bridgeResponse["error"].getStr():
        inc duplicateCount
    doAssert acceptedCount == 1 and duplicateCount == 1,
      "Duplicate async request IDs were not rejected before acceptance"
    doAssert asyncState["response"]["ok"].getBool(),
      "The async command returned an error"
    doAssert asyncState["response"]["value"].getStr() == ExpectedAsyncValue,
      "The async completion was routed to the wrong request"
  finally:
    window.close()

let verification = verifyFrontend()

try:
  runFrontendEventLoop(window)
  verification.read()
  echo "Frontend E2E passed: " & ExpectedGreeting
finally:
  window.close()
  webui.clean()
  when not defined(release):
    if viteProcess != nil:
      if viteProcess.running:
        viteProcess.terminate()
        discard viteProcess.waitForExit(2_000)
      viteProcess.close()
