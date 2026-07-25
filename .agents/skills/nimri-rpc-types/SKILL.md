---
name: nimri-rpc-types
description: Design, implement, review, or diagnose Nimri RPC data contracts, including exported objects, enums, named tuples, Option, sequences, arrays, Table, and OrderedTable values used from Svelte.
---

# Nimri RPC Types

Use only supported RPC types; export public types and object fields.

## Workflow

1. Read [rpc-types.md](references/rpc-types.md) before defining a command contract.
2. Prefer an enum to a string value set.
3. Export every object, tuple alias, enum, and field required in TypeScript.
4. After contract changes, run `./app.sh dev` and import generated types from `commands/types`.
5. Keep serialization constraints in the public contract; do not rely on a representation that only happens to work locally.

## Guardrails

- Use only named tuples; export every tuple alias used by an RPC command.
- Use `Table[string, T]` or `OrderedTable[string, T]` only for object-style JSON keys; ordering is not guaranteed.
- Keep integers in JavaScript's safe range and floats finite.
- Do not use references, pointers, inheritance, variant objects, object default fields, positional tuples, or non-string table keys across RPC.
