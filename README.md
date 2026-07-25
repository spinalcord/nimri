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

## Add a Nim command

Create a module below `backend/commands` and mark a typed procedure with `{.accessible.}`:

```nim
import nimri_rpc

type Greeting* = object
  message*: string

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(message: "Hello, " & name & "!")
```

Do `./app.sh generate` And call Nim from Svelte:

```html
<script lang="ts">
  import { greet } from 'commands/greeting';

  let greeting = '';

  async function callGreet() {
    greeting = (await greet('Mara')).message;
  }
</script>

<button on:click={callGreet}>Call Nim</button>
<p>{greeting}</p>
```

> No Magic Strings, No Magic Invokes, No manually using a REST-Api  
> This feels like developing Qt, Avalonia or Wpf applications

## Development commands

```sh
./app.sh run        # Run the app
./app.sh dev        # Start the development workflow
./app.sh generate   # Generates RPC Type Script files
./app.sh serialize  # Serialize Methods/Types to Json (Only for framework developement)
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
