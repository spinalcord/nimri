import std/[os, strutils]
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
    sleep(100)

  doAssert ExpectedGreeting in renderedGreeting,
    "Expected the Nim greeting, got: " & renderedGreeting & ". Body: " &
      window.script("return document.body.textContent;", timeout = 2).data
finally:
  window.close()
  webui.clean()
  when not defined(release):
    if viteProcess != nil:
      if viteProcess.running:
        viteProcess.terminate()
        discard viteProcess.waitForExit(2_000)
      viteProcess.close()

echo "Frontend E2E passed: " & ExpectedGreeting
