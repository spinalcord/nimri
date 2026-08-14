---
name: nimri-development
description: Run, test, generate, build, or diagnose a Nimri desktop application through npm, including RPC generation, frontend contract tests, development startup, and release builds.
---

# Nimri Development

Run npm commands from the repository root.

Use `$nimri-feature-workflow` first when creating or extending a feature across the backend and Svelte UI.

## Commands

| Goal | Command |
| --- | --- |
| Develop and run | `npm run dev` |
| Run the application | `npm start` |
| Serialize RPC metadata | `npm run serialize` |
| Generate frontend bindings | `npm run generate` |
| Run project tests | `npm test` |
| Build a release | `npm run build` |

## Workflow

After changing an accessible command or RPC type, use `npm run dev` to refresh bindings and run the application. Use `serialize` or `generate` only for an explicit intermediate step.

## CRITICAL
Use `npm test` ONLY IF you maintain core nimri framework. You don't have to use this command during app development.
