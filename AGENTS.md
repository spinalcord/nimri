# Nim–Svelte Desktop Framework

Electron + Svelte frontend with a Nim 2+ sidecar and generated typed RPC.

- Use Nim 2+ syntax and features.
- Write code comments in English. Never remove `CRITICAL:` or `CRITCAL:` comments. Use short `FIX:` comments for fixes.
- Do not add unrequested features or silent optimizations.
- Prefer enums to magic strings and events to polling loops when practical.
- Do not add static helpers merely for convenient access; keep code testable.
- Redesign workarounds that require paragraph-long justification.
- Do not add tests unless asked. Never run `npm test` during app development.

## CRITICAL

Broad searches must exclude `nim/backend/core/`, `frontend/node_modules/`, `.nimchache/`, `tests/`, and `scripts/app.mjs`. Do not read `scripts/app.mjs` for routine feature, UI, or backend work; read it only when changing or diagnosing npm scripts, the dev/build workflow, packaging, or when a task-relevant fact cannot be verified elsewhere. Read the other excluded paths only for Nimri framework work or when a task-relevant fact cannot be verified elsewhere.
