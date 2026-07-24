import std/[json, os, unittest]

{.push warning[UnusedImport]: off.}
import ../backend/core/commands
{.pop.}

const
  ProjectRoot = currentSourcePath().parentDir.parentDir
  MetadataPath = ProjectRoot / ".nimcache" / "frontend-rpc.json"
  GeneratedDirectory = ProjectRoot / "frontend" / "commands"

proc generatedFile(name: string): string =
  readFile(GeneratedDirectory / name)

suite "frontend binding generation":
  test "serialization is deterministic and structured":
    serializeFrontendBindings()
    let first = readFile(MetadataPath)
    serializeFrontendBindings()
    check readFile(MetadataPath) == first

    let metadata = parseJson(first)
    check metadata["schemaVersion"].getInt() == 1
    check metadata["commands"].len == 1
    check metadata["commands"][0]["modulePath"].getStr() == "greeting"
    check metadata["commands"][0]["parameters"][0]["type"]["kind"].getStr() ==
      "string"
    check metadata["commands"][0]["returnType"]["kind"].getStr() == "named"
    check metadata["types"][0]["kind"].getStr() == "object"

  test "generation reads metadata without changing current output":
    let before = @[
      generatedFile("greeting.ts"),
      generatedFile("types.ts"),
      generatedFile(".frontend-bindings-manifest"),
    ]

    generateFrontendBindings()

    check generatedFile("greeting.ts") == before[0]
    check generatedFile("types.ts") == before[1]
    check generatedFile(".frontend-bindings-manifest") == before[2]
