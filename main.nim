import std/os
import backend/core/[app, rpc_registry]

when isMainModule:
  let arguments = commandLineParams()
  if arguments == @["serialize"]:
    serializeFrontendBindings()
  elif arguments == @["generate"]:
    serializeFrontendBindings()
    generateFrontendBindings()
  elif arguments == @["serve"]:
    serveApp()
  else:
    stderr.writeLine("Usage: " & getAppFilename().extractFilename &
      " [serialize|generate|serve]")
    quit(2)
