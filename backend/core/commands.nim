import std/[algorithm, macros, os, staticos, strutils]
import nimri_rpc

proc collectCommandModules(directory: string, modulePaths: var seq[string]) {.
    compileTime.} =
  for entry in staticWalkDir(directory):
    case entry.kind
    of staticos.pcFile, staticos.pcLinkToFile:
      if entry.path.endsWith(".nim"):
        modulePaths.add(entry.path)
    of staticos.pcDir:
      collectCommandModules(entry.path, modulePaths)
    of staticos.pcLinkToDir:
      discard

macro importCommandModules(): untyped =
  let
    sourcePath = currentSourcePath()
    commandsDir = sourcePath.parentDir.parentDir / "commands"
  var modulePaths: seq[string]

  collectCommandModules(commandsDir, modulePaths)
  modulePaths.sort()
  result = newStmtList()

  for index, absolutePath in modulePaths:
    let
      relativePath = absolutePath.relativePath(sourcePath.parentDir)
        .changeFileExt("")
        .replace(DirSep, '/')
      modulePath = newLit(relativePath)
      moduleAlias = ident("frontendCommandModule" & $index)
      importTarget = newTree(nnkInfix, ident("as"), modulePath, moduleAlias)
      importStatement = newTree(nnkImportStmt, importTarget)
      exportStatement = newTree(nnkExportStmt, moduleAlias)

    modulePath.setLineInfo(sourcePath, 1, 1)
    importTarget.setLineInfo(sourcePath, 1, 1)
    importStatement.setLineInfo(sourcePath, 1, 1)
    exportStatement.setLineInfo(sourcePath, 1, 1)
    result.add importStatement
    result.add exportStatement

importCommandModules()
defineFrontendBindings()
