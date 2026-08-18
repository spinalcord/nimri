---
name: nimri-rpc-types
description: Use only for new nontrivial or failing Nimri RPC contracts involving nested containers, exported objects, enums, tuples, tables, serialization, or binding generation.
---

# Nimri RPC Types

Start complete features with `$nimri-feature-workflow`. Use supported RPC types and export public types and fields.

## Workflow

1. Read [rpc-types.md](references/rpc-types.md) before designing a nontrivial contract or diagnosing representation or generation.
2. Prefer an enum to a string value set.
3. Export every object, named tuple, enum, and field needed in TypeScript.
4. Run `npm run dev` and import generated types from `rpc/types`.

## Guardrails

- Use only named tuples and string-keyed tables; table order is not guaranteed.
- Keep integers in JavaScript's safe range and floats finite.
- Do not expose references, pointers, inheritance, variant objects, object field defaults, positional tuples, or non-string table keys.
