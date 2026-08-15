# Nim-Svelte Desktop Framework

This project was created to make it fast and enjoyable to build good-looking desktop application prototypes. Tauri already solves this problem, BUT Rust's compile-time guarantees and feedback loop can add friction when the main goal is exploring an idea quickly.

To be clear, I am still figuring out where this project will go. For now, it is a foundation for exploring a simple and productive way to build desktop applications.

## AI Disclaimer

AI was used as an engineering tool, including for parts of the Nim macro implementation, while design decisions and the resulting code were reviewed with long-term maintainability in mind for HUMANS by me e.g. using mustache for template generation. I provide also my `AGENTS.md` and my `Agent Skills` for this project.

## Quick start

Install the frontend dependencies and start the app:

```sh
nimble install
npm install
npm run dev
```

The development command generates the bindings, compiles the Nim sidecar, starts
Vite and Electron, and opens the desktop window. Closing the window stops Vite,
Electron, and the sidecar. For a release build, run:

```sh
npm run build
```

The native build output is a directly runnable Electron application directory
below `bin/`, such as `bin/Nimri-linux-x64/` on Linux or
`bin/Nimri-win32-x64/` on Windows. No installer is created. The package contains
the compiled Svelte assets, the Electron runtime, the Nim sidecar, and—on
Windows—the required MinGW runtime DLLs.

## Runtime architecture

Electron owns the application lifecycle, the single desktop window, and
frontend asset delivery. In development it loads Vite from
`http://127.0.0.1:5173`; a packaged app serves its assets through the internal
`nimri://app/` protocol. The renderer runs sandboxed, without Node.js
integration, and can access only the typed `window.nimri` methods exposed by the
isolated preload script.

Electron starts one bundled Nim sidecar in its internal `serve` mode. RPC uses
newline-delimited JSON over the process's standard input and output; Nimri does
not open a bridge port. Protocol output is reserved for RPC messages, while
backend logs go to standard error. Closing the app closes the sidecar input and
cancels active streams. If the sidecar exits unexpectedly, pending calls and
streams fail and Electron shuts down cleanly.

## Add a feature

Treat a feature as one vertical slice: define its RPC contract and commands in
`backend/features/<feature>/`, generate the bindings with `npm run dev`, then
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

> [!NOTE]
> No Magic Strings, No Magic Invokes, No manually using a REST-Api  
> This feels like developing Qt, Avalonia or Wpf applications

## Development commands

```sh
npm run generate   # Generate Frontend Data
npm start          # Run the app
npm run dev        # Start the development workflow
npm run build      # Package a runnable Electron app below bin/
```

The same commands work on Linux and Windows, with builds produced natively on
their target platform. The explicit `npm run run` alias is also available,
along with `npm run serialize` and `npm test`.

Most of the time you need propably `generate` and `dev`.

## Supported RPC capabilities

- Normally named, non-generic procedures with explicit parameter types.
- Strings, booleans, numeric types, enums, `Option[T]`, sequences, fixed
  arrays, `Table[string, T]`, `OrderedTable[string, T]`, exported plain
  objects with exported fields, and exported named tuples.
- Synchronous commands and cooperative asynchronous commands returning
  `Future[T]`; generated frontend functions return promises.
- Streaming commands returning `FutureStream[T]`; generated frontend functions
  return a lazy `NimriStream<T>` that works with `for await...of`.

## Stream command results

Use `std/asyncstreams.FutureStream[T]` when one command needs to deliver values
over time. Return the stream directly rather than wrapping it in `Future`:

```nim
import std/[asyncdispatch, asyncstreams]
import nimri_rpc

type Update* = object
  message*: string

proc produceUpdates(stream: FutureStream[Update]): Future[void] {.async.} =
  try:
    await stream.write(Update(message: "Starting"))
    await stream.write(Update(message: "Finished"))
    stream.complete()
  except ValueError:
    # The consumer canceled or its window disconnected.
    discard
  except CatchableError as exception:
    stream.fail(exception)

proc updates*(): FutureStream[Update] {.accessible.} =
  result = newFutureStream[Update]("updates")
  asyncCheck produceUpdates(result)
```

The generated Svelte binding starts the backend command only when the first
value is requested:

```html
<script lang="ts">
  import { updates } from 'rpc/commands/activity';

  async function readUpdates() {
    try {
      for await (const update of updates()) {
        console.log(update.message);
      }
    } catch (reason) {
      console.error('Update stream failed', reason);
    }
  }
</script>
```

Each `NimriStream<T>` is single-use and supports one consumer. It has no replay,
fan-out, or backend backpressure. Breaking out of `for await...of` calls
`return()` and cancels the backend stream. A stream can also be canceled
explicitly:

```ts
const stream = updates();
const first = await stream.next();
await stream.cancel();
```

Cancellation is cooperative. Nim closes the underlying `FutureStream`, so later
producer `write` futures fail with `ValueError`; producers should await writes
and stop when that happens. Producer exceptions, failed streams, and JSON
serialization errors reject the next frontend read. A normal stream completion
returns `{ done: true }` from `next()`.

## Limitations

These limits require framework work rather than a local feature implementation.

| Limitation | Difficulty |
| --- | --- |
| References and pointers | Nearly impossible, because safe object identity, lifetime, and cyclic graphs need a separate resource model. |
| Generic command procedures | Challenging, because every frontend binding needs a concrete signature. |
| Object inheritance and variant objects | Challenging, because generated TypeScript needs a stable discriminator and complete subtype schema. |
| Positional tuples, non-string table keys, and object default fields | Feasible with explicit JSON encodings. |
| Integers outside JavaScript's safe range, `NaN`, and infinities | Challenging, because JSON and JavaScript `number` do not preserve them safely. |
| Automatic timeouts and resumable or multi-consumer streams | Challenging, because they need additional lifecycle and replay semantics. |

## Status

This is a focused framework for quickly shipping desktop prototypes. The API is intentionally small and opinionated, so feedback, bug reports, and small focused pull requests are welcome.
