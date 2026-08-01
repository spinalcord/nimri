# Nim-Svelte Desktop Framework

This project was created to make it fast and enjoyable to build good-looking desktop application prototypes. Tauri already solves this problem, BUT Rust's compile-time guarantees and feedback loop can add friction when the main goal is exploring an idea quickly.

To be clear, I am still figuring out where this project will go. For now, it is a foundation for exploring a simple and productive way to build desktop applications.

## AI Disclaimer

AI was used as an engineering tool, including for parts of the Nim macro implementation, while design decisions and the resulting code were reviewed with long-term maintainability in mind for HUMANS by me e.g. using mustache for template generation. I provide also my `AGENTS.md` and my `Agent Skills` for this project.

## Quick start

Install the frontend dependencies and start the app:

```sh
nimble install
npm --prefix frontend install
./app.sh dev
```

The development command compiles the Nim application, starts Vite, and opens the desktop window. For a release build, run:

```sh
./app.sh build
```

The build output is written to `bin/main`. The compiled frontend is embedded in the binary.

## Add a feature

Treat a feature as one vertical slice: define its RPC contract and commands in
`backend/features/<feature>/`, generate the bindings with `./app.sh dev`, then
connect the generated API to a Svelte component. Do not edit files below
`frontend/generated/` manually.

Keep the contract and commands together below a feature directory. Named RPC
types can live in `backend/features/greeting/types.nim`:

```nim
type Greeting* = object
  message*: string
```

Commands for that feature live in
`backend/features/greeting/commands/greeting.nim`:

```nim
import nimri_rpc
import ../types

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(message: "Hello, " & name & "!")
```

All command files below the same feature are combined into one generated
frontend module. The feature path determines the namespace, so the command
above keeps the wire name `greeting.greet` regardless of its Nim filename.
Commands with the same name in different features remain distinct, such as
`greeting.greet` and `profile.greet`; duplicate command names inside one
feature are rejected during compilation.

Call Nim from Svelte:

Import the command and use it like a typed async function:

```html
<script lang="ts">
  import { greet } from 'rpc/commands/greeting';
  import type { Greeting } from 'rpc/types';

  let greeting: Greeting | null = null;

  async function callGreet() {
    greeting = await greet('Mara');
  }
</script>

<button on:click={callGreet}>Call Nim</button>
<p>{greeting?.message ?? ''}</p>
```

> No Magic Strings, No Magic Invokes, No manually using a REST-Api  
> This feels like developing Qt, Avalonia or Wpf applications

## Development commands

```sh
./app.sh run        # Run the app
./app.sh dev        # Start the development workflow
./app.sh build      # Create a release build
```

## Limitations (For now)

- Commands must be normally named, non-generic procedures with explicit parameter types.
- Supported values are strings, booleans, numeric types, enums, `Option[T]`,
  sequences, fixed arrays, `Table[string, T]`, `OrderedTable[string, T]`,
  exported plain objects with exported fields, and tuples whose fields are all
  named.
- Tuple aliases used by RPC commands must be exported. Positional tuples,
  tables with non-string keys, references, pointers, and other unsupported
  generic types cannot cross the RPC boundary.
- Objects cannot use inheritance, variant fields, or default field values.
- Integers must fit within JavaScript's safe integer range.
- Floating-point values must be finite. `NaN`, positive infinity, and negative infinity are rejected.
- Async commands do not currently support progress, streaming, cancellation, or automatic timeouts.
- Frontend command functions always return promises, for both synchronous and asynchronous Nim commands.

## Status

This is a focused framework for quickly shipping desktop prototypes. The API is intentionally small and opinionated, so feedback, bug reports, and small focused pull requests are welcome.
