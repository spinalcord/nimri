import std/[algorithm, macros, os, staticos, strutils]
import nimri_rpc

proc collectRpcCommandModules(directory: string, modulePaths: var seq[string]) {.
    compileTime.} =
  for entry in staticWalkDir(directory):
    case entry.kind
    of staticos.pcFile, staticos.pcLinkToFile:
      if entry.path.endsWith(".nim") and
          entry.path.parentDir.extractFilename == "commands":
        modulePaths.add(entry.path)
    of staticos.pcDir:
      collectRpcCommandModules(entry.path, modulePaths)
    of staticos.pcLinkToDir:
      discard

macro importRpcCommandModules(): untyped =
  let
    sourcePath = currentSourcePath()
    featuresDirectory = sourcePath.parentDir.parentDir / "features"
  var modulePaths: seq[string]

  collectRpcCommandModules(featuresDirectory, modulePaths)
  modulePaths.sort()
  result = newStmtList()

  for index, absolutePath in modulePaths:
    let
      relativePath = absolutePath.relativePath(sourcePath.parentDir)
        .changeFileExt("")
        .replace(DirSep, '/')
      modulePath = newLit(relativePath)
      moduleAlias = ident("rpcCommandModule" & $index)
      importTarget = newTree(nnkInfix, ident("as"), modulePath, moduleAlias)
      importStatement = newTree(nnkImportStmt, importTarget)

    modulePath.setLineInfo(sourcePath, 1, 1)
    importTarget.setLineInfo(sourcePath, 1, 1)
    importStatement.setLineInfo(sourcePath, 1, 1)
    result.add importStatement

{.push warning[UnusedImport]: off.}
importRpcCommandModules()
{.pop.}
defineFrontendBindings()
