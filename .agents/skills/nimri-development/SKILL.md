---
name: nimri-development
description: Use only to start, generate, test, build, or diagnose a Nimri application. Covers npm execution and runtime checks, not ordinary feature implementation.
---

# Nimri Development

Run commands from the repository root. Use `$nimri-feature-workflow` for backend-to-Svelte feature work.

## Commands

| Goal | Command |
| --- | --- |
| Develop and run | `npm run dev` |
| Run the application | `npm start` |
| Serialize RPC metadata | `npm run serialize` |
| Generate frontend bindings | `npm run generate` |
| Run project tests | `npm test` |
| Build a release | `npm run build` |

`npm run dev` refreshes RPC bindings and starts the application. Use `serialize` or `generate` only when an explicit intermediate step is needed.
