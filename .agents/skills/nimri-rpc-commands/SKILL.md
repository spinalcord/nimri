---
name: nimri-rpc-commands
description: Create, modify, or review typed Nimri RPC commands and generated Svelte bindings, including accessible procedures, immediate or Future results, default parameters, and command exceptions.
---

# Nimri RPC Commands

Implement the backend procedure and use its generated TypeScript binding; never add a manual RPC transport call.

## Workflow

1. Create or update a module below `backend/commands`.
2. Import `nimri_rpc`; export the non-generic procedure and mark it `{.accessible.}`.
3. Use a plain return type for immediate commands, or `Future[T]` with `{.async, accessible.}` for cooperative asynchronous I/O.
4. Run `./app.sh dev`, then import the generated `frontend/commands` module in Svelte.
5. Let command exceptions reject the generated Promise; handle expected failures in the Svelte caller.

Read [commands.md](references/commands.md) before choosing an async shape or changing command parameters.

## Guardrails

- Give every parameter an explicit type; keep command names normal and unique.
- Do not use a background loop for work that can await an event or asynchronous I/O.
- Do not perform blocking or CPU-intensive work on Nim's main thread merely because a command returns `Future[T]`.
- Omit an optional frontend argument only when the Nim procedure supplies a default value.
