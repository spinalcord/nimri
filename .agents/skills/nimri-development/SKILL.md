---
name: nimri-development
description: Run, test, generate, build, or diagnose a Nimri desktop application through app.sh, including RPC generation, frontend contract tests, development startup, and release builds.
---

# Nimri Development

Run `app.sh` from the repository root.

## Commands

| Goal | Command |
| --- | --- |
| Develop and run | `./app.sh dev` |
| Run the application | `./app.sh run` |
| Serialize RPC metadata | `./app.sh serialize` |
| Generate frontend bindings | `./app.sh generate` |
| Run project tests | `./app.sh test` |
| Build a release | `./app.sh build` |

## Workflow

After changing an accessible command or RPC type, use `./app.sh dev` to refresh bindings and run the application. Use `serialize` or `generate` only for an explicit intermediate step.

## CRITICAL
Use `/app.sh test` ONLY IF you maintain core nimri framework. You don't have to use this command during app development.
