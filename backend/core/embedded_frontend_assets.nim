import std/[algorithm, macros, os, staticos, strutils]

const FrontendDist = currentSourcePath().parentDir.parentDir.parentDir /
  "frontend" / "dist"

static:
  doAssert staticDirExists(FrontendDist),
    "Frontend assets are missing. Build the frontend first with " &
    "`npm --prefix frontend run build`."

macro embeddedFrontendAsset*(urlPath: string): untyped =
  var assetPaths: seq[string]

  proc collectAssetPaths(directory: string) {.compileTime.} =
    for entry in staticWalkDir(directory):
      case entry.kind
      of pcFile, pcLinkToFile:
        assetPaths.add(entry.path)
      of pcDir, pcLinkToDir:
        collectAssetPaths(entry.path)

  collectAssetPaths(FrontendDist)
  assetPaths.sort()

  result = newTree(nnkCaseStmt, urlPath)
  for assetPath in assetPaths:
    let urlPath = "/" & relativePath(assetPath, FrontendDist).replace(DirSep, '/')
    result.add(newTree(nnkOfBranch, newLit(urlPath), newLit(staticRead(assetPath))))
  result.add(newTree(nnkElse, newLit("")))
