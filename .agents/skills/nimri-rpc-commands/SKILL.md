---
name: nimri-rpc-commands
description: Create, modify, or review typed Nimri RPC commands and generated Svelte bindings, including accessible procedures, immediate, Future, or FutureStream results, default parameters, and command exceptions.
---

# Nimri RPC Commands

Implement the backend procedure and use its generated TypeScript binding; never add a manual RPC transport call.

For work that spans a complete backend-to-Svelte feature, start with `$nimri-feature-workflow`.

## Workflow

1. Create or update a module below
   `backend/features/<feature>/commands`.
2. Import `nimri_rpc`; export the non-generic procedure and mark it `{.accessible.}`.
3. Use a plain return type for immediate commands, `Future[T]` with
   `{.async, accessible.}` for one cooperative asynchronous result, or return
   `FutureStream[T]` directly for multiple results over time.
4. Run `./app.sh dev`, then import the command from
   `rpc/commands/<feature>` in Svelte.
5. Let command exceptions reject the generated Promise or stream read; handle
   expected failures in the Svelte caller.

Read [commands.md](references/commands.md) before choosing an async shape or changing command parameters.

## Guardrails

- Give every parameter an explicit type; keep command names normal and unique.
- Command names must be unique across all command files in the same feature.
- Do not use a background loop for work that can await an event or asynchronous I/O.
- Do not perform blocking or CPU-intensive work on Nim's main thread merely
  because a command returns `Future[T]` or `FutureStream[T]`.
- Await stream writes and stop producing when cancellation makes a write fail.
- Do not wrap a stream in `Future`; `Future[FutureStream[T]]` is unsupported.
- Omit an optional frontend argument only when the Nim procedure supplies a default value.
