import std/os
import backend/core/[app, rpc_registry]

when isMainModule:
  let arguments = commandLineParams()
  if arguments == @["serialize"]:
    serializeFrontendBindings()
  elif arguments == @["generate"]:
    serializeFrontendBindings()
    generateFrontendBindings()
  elif arguments.len == 0 or arguments == @["run"]:
    serializeFrontendBindings()
    generateFrontendBindings()
    runApp()
  else:
    stderr.writeLine("Usage: " & getAppFilename().extractFilename &
      " [serialize|generate|run]")
    quit(2)
