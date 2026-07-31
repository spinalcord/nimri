import std/[json, os, strutils, unittest]

{.push warning[UnusedImport]: off.}
import ../backend/core/rpc_registry
{.pop.}

const
  ProjectRoot = currentSourcePath().parentDir.parentDir
  MetadataPath = ProjectRoot / ".nimcache" / "nimri-rpc.json"
  GeneratedDirectory = ProjectRoot / "frontend" / "generated" / "rpc"

proc generatedFile(name: string): string =
  readFile(GeneratedDirectory / name)

suite "frontend binding generation":
  test "serialization is deterministic and structured":
    serializeFrontendBindings()
    let first = readFile(MetadataPath)
    serializeFrontendBindings()
    check readFile(MetadataPath) == first

    let metadata = parseJson(first)
    check metadata["schemaVersion"].getInt() == 3
    check metadata["commands"].len == 1
    check metadata["commands"][0]["commandKind"].getStr() == "synchronous"
    check metadata["commands"][0]["modulePath"].getStr() == "greeting"
    check metadata["commands"][0]["wireName"].getStr() ==
      "greeting.greet"
    check metadata["commands"][0]["nimName"].getStr() == "greet"
    check metadata["commands"][0]["parameters"][0]["type"]["kind"].getStr() ==
      "string"
    check metadata["commands"][0]["returnType"]["kind"].getStr() == "named"
    check metadata["types"][0]["kind"].getStr() == "object"

  test "generation reads metadata without changing current output":
    let before = @[
      generatedFile("commands/greeting.ts"),
      generatedFile("types/Greeting.ts"),
      generatedFile("types/index.ts"),
      generatedFile(".frontend-bindings-manifest"),
    ]

    generateFrontendBindings()

    check generatedFile("commands/greeting.ts") == before[0]
    check generatedFile("types/Greeting.ts") == before[1]
    check generatedFile("types/index.ts") == before[2]
    check generatedFile(".frontend-bindings-manifest") == before[3]

  test "generated commands keep their wire names and types":
    let commands = generatedFile("commands/greeting.ts")

    check "invoke<Greeting>('greeting.greet', { name })" in commands
    check "greet(name: string): Promise<Greeting>" in commands
    check "from '../types/Greeting'" in commands
    check "from '../../../rpc'" in commands

  test "named types have individual files and a public barrel":
    let
      greetingType = generatedFile("types/Greeting.ts")
      typeBarrel = generatedFile("types/index.ts")

    check "export interface Greeting" in greetingType
    check "from './Greeting'" in typeBarrel
    check not fileExists(ProjectRoot / "frontend" / "commands" /
      "greeting.ts")
