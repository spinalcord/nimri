---
name: nimri-rpc-commands
description: Use only for Nimri RPC command behavior involving Future, FutureStream, async or cancellation, default parameters, or exception propagation. Skip routine synchronous commands.
---

# Nimri RPC Commands

Start complete features with `$nimri-feature-workflow`. Implement commands below `backend/features/<feature>/commands` and use generated bindings, never manual transport.

## Workflow

1. Read [commands.md](references/commands.md) before choosing async/stream behavior or changing defaults, cancellation, or errors.
2. Import `nimri_rpc`; export a non-generic `{.accessible.}` procedure.
3. Return `Future[T]` for one cooperative async result or `FutureStream[T]` directly for multiple results.
4. Run `npm run dev`; import from `rpc/commands/<feature>` and handle expected rejection in Svelte.

## Guardrails

- Type every parameter; keep command names unique within the feature.
- Prefer awaited events or I/O to background loops. `Future` does not make blocking or CPU work non-blocking.
- Await stream writes and stop when cancellation makes one fail.
- Never return `Future[FutureStream[T]]`.
- Omit a frontend argument only when Nim supplies its default.
