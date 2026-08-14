---
name: nimri-feature-workflow
description: Create or extend a Nimri feature across the Nim backend, generated type-safe RPC bindings, and Svelte UI. Use when a task spans backend/features, RPC commands or types, generated frontend bindings, and a Svelte feature component.
---

# Nimri Feature Workflow

Implement a feature as one vertical slice: backend contract and command, generated binding, then Svelte integration.

## Workflow

1. Inspect the existing feature and its Svelte integration before changing it. Group backend code by feature below `backend/features/<feature>/`.
2. Put shared RPC contracts in `backend/features/<feature>/types.nim`. Use `$nimri-rpc-types` when adding or revising a contract.
3. Put accessible procedures in `backend/features/<feature>/commands/*.nim`. Use `$nimri-rpc-commands` for procedure shape, async work, parameters, and error behavior.
4. Run `npm run dev` after changing an accessible command or RPC type. It refreshes the frontend bindings and starts the application.
5. Implement or update the Svelte component and integrate it into the existing application. Import generated procedures from `rpc/commands/<feature>` and generated types from `rpc/types`.
6. Exercise the changed feature through the running application. Use `$nimri-development` for explicit generation, builds, or diagnostics.

## Boundaries

- Do not edit files under `frontend/generated/`; regenerate them through `npm run generate` if needed.
- Do not add manual RPC transport calls; use the generated bindings.
- Keep feature-specific backend code below `backend/features/<feature>/`; do not change Nimri framework code for normal application features.
- Do not run `npm test` during application development. It is reserved for Nimri framework maintenance.
