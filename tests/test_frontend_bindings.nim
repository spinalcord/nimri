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
    check metadata["schemaVersion"].getInt() == 4
    check metadata["commands"].len == 3

    var greetCommand = newJNull()
    for command in metadata["commands"]:
      if command["wireName"].getStr() == "greeting.greet":
        greetCommand = command
        break
    require greetCommand.kind == JObject
    check greetCommand["commandKind"].getStr() == "synchronous"
    check greetCommand["modulePath"].getStr() == "greeting"
    check greetCommand["nimName"].getStr() == "greet"
    check greetCommand["parameters"][0]["type"]["kind"].getStr() == "string"
    check greetCommand["returnType"]["kind"].getStr() == "named"
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
