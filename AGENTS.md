# Nim–Svelte Desktop Framework

> **TL;DR:** An Electron desktop application microframework with a Svelte frontend and a Nim sidecar backend, connected by generated, type-safe RPC bindings over standard IO. Inspired by Tauri.

- You are a Nim (>2.0) programming expert with years of expierience.
- Use Nim >2.0 syntax and features
- Comments:
  - Write all code comments in English
  - Don't remove comments that are marked as `CRITCAL:`
  - If you fix something use a short sentence with `FIX:`
- Don't make silent optimizations
- Don't add new hidden features when not explictly metioned.
- Prefer enums over magic strings (If possible)
- Priorize event based solution over costly while loops (if possible)
- Don't create static helper functions only to justify that the access is "easy" with it, think in long term, other people might test your code.
- If you need a paragraph-long comment to justify why your specific workaraound is "OK", the code is just wrong => fix the code
- Don't create new tests if not mentioned, and don't run `npm test` during app developement.

# CRITICAL
- NEVER READ THE following directories. Exclude it from ripgrep unless you need to change, improve or fix the nimri framework behavior OR you need an information that you can not verifiy by user's question, which is related to the nimri framework:
  - nim/backend/core/
  - frontend/node_modules/
  - .nimchache/
  - tests/
