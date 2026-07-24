import std/os
import webui

# Importing the aggregator initializes every frontend command registration.
{.push warning[UnusedImport]: off.}
import commands
{.pop.}

import frontend_rpc

when not defined(release):
  import std/[net, osproc]

  const
    DevServerHost = "127.0.0.1"
    DevServerPort = 5173
    WebUiBridgePort = 7681
    DevServerUrl = "http://" & DevServerHost & ":" & $DevServerPort

  proc devServerIsReady(): bool =
    var socket = newSocket()
    try:
      socket.connect(DevServerHost, Port(DevServerPort), timeout = 200)
      result = true
    except CatchableError:
      result = false
    finally:
      socket.close()

  proc waitForDevServer(process: Process) =
    for _ in 0 ..< 100:
      if not process.running:
        raise newException(IOError,
          "Vite exited with code " & $process.peekExitCode & ".")
      if devServerIsReady():
        return
      sleep(100)

    raise newException(IOError,
      "Vite is not reachable at " & DevServerUrl & " after 10 seconds.")

proc runApp*() =
  let myWindow = newWindow()
  bindFrontendCommands(myWindow)

  when defined(release):
    myWindow.rootFolder = getAppDir() / "frontend"
    myWindow.show("index.html")
    wait()
  else:
    myWindow.port = WebUiBridgePort
    let frontendDir = getAppDir() / "frontend"
    var viteProcess: Process

    try:
      if not devServerIsReady():
        viteProcess = startProcess(
          "node",
          workingDir = frontendDir,
          args = ["node_modules/vite/bin/vite.js"],
          options = {poUsePath, poParentStreams}
        )
        waitForDevServer(viteProcess)

      myWindow.show(DevServerUrl)
      wait()
    finally:
      if viteProcess != nil:
        if viteProcess.running:
          viteProcess.terminate()
          discard viteProcess.waitForExit(2_000)
        viteProcess.close()
