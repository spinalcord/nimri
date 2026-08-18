---
name: nimri-feature-workflow
description: Use for a vertical Nimri feature spanning backend/features, generated RPC bindings, and Svelte UI. Start here for ordinary end-to-end feature work.
---

# Nimri Feature Workflow

Implement one vertical slice: backend, generated binding, then Svelte UI.

## Workflow

1. Inspect related backend and Svelte code. For a new feature, run `npm run feature <kebab-name>`; keep its generated underscore paths.
2. Keep backend code in `backend/features/<feature>/`, shared contracts in `types.nim`, and accessible procedures in `commands/*.nim`.
3. Add `$nimri-rpc-types` only for a new nontrivial, complex, or failing contract.
4. Add `$nimri-rpc-commands` only for async, streams, defaults, cancellation, or exception behavior.
5. Run `npm run dev` after RPC changes, then use imports from `rpc/commands/<feature>` and `rpc/types` in Svelte.
6. Integrate and exercise the feature. Add `$nimri-development` only for explicit generation, builds, tests, or runtime diagnosis.

## Boundaries

- Do not edit `frontend/generated/` or add manual transport calls; regenerate and use typed bindings.
- Do not change Nimri framework code for normal application features.
