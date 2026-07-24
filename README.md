# Nim-Svelte Desktop Framework

This project was created to make it fast and enjoyable to build good-looking desktop application prototypes. Tauri already solves a similar problem, but Rust's compile-time guarantees and feedback loop can add friction when the main goal is exploring an idea quickly. This framework keeps the familiar web UI workflow of Svelte and pairs it with Nim for a lightweight, productive backend.

To be clear, I am still figuring out where this project will go. For now, it is a foundation for exploring a simple and productive way to build desktop applications.

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

The build output is written to `bin/main` with the compiled frontend in `bin/frontend`.

## Add a Nim command

Create a module below `backend/commands` and mark a synchronous, typed procedure with `{.accessible.}`:

```nim
import frontend_rpc

type Greeting* = object
  message*: string

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(message: "Hello, " & name & "!")
```

Call Nim from Svelte:

Import the command and use it like a typed async function:

```html
<script lang="ts">
  import { greet } from './commands/greeting';

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

## Typed data

Exported Nim objects, enums, sequences, fixed arrays, and optional values can be used in command parameters and return values:

```nim
import std/options
import frontend_rpc

type
  Theme* = enum
    light, dark

  UserProfile* = object
    name*: string
    age*: int
    theme*: Theme

proc createProfile*(name: string, theme: Theme,
    nickname: Option[string]): UserProfile {.accessible.} =
  UserProfile(name: name, age: 0, theme: theme)
```

The frontend types mirror the exported fields and command signatures, so TypeScript can catch mismatches before the app is run.

## Development commands

```sh
./app.sh run        # Run the app
./app.sh dev        # Start the development workflow
./app.sh build      # Create a release build
```

## Limitations (For now)

- Commands must be synchronous, normally named, non-generic procedures with explicit parameter types.
- Supported values are strings, booleans, numeric types, enums, `Option[T]`, sequences, fixed arrays, and exported plain objects with exported fields.
- Tuples, references, pointers, and other unsupported generic types cannot cross the RPC boundary.
- Objects cannot use inheritance, variant fields, or default field values.
- Integers must fit within JavaScript's safe integer range.
- Floating-point values must be finite. `NaN`, positive infinity, and negative infinity are rejected.
- The current command API is synchronous on the Nim side. The frontend command functions return promises because communication with the desktop bridge is asynchronous.

## Status

This is a focused framework for quickly shipping desktop prototypes. The API is intentionally small and opinionated, so feedback, bug reports, and small focused pull requests are welcome.
