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

Create a module below `backend/commands` and mark a typed procedure with `{.accessible.}`:

```nim
import nimri_rpc

type Greeting* = object
  message*: string

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(message: "Hello, " & name & "!")
```

Commands can also return a `Future[T]`. The canonical form combines `async`
with `accessible`:

```nim
import std/asyncdispatch
import nimri_rpc

proc loadGreeting*(name: string): Future[Greeting] {.
    async, accessible.} =
  await sleepAsync(100)
  result = Greeting(message: "Hello, " & name & "!")
```

Manually created `Future[T]` values are supported as well. Async commands use
cooperative asynchronous I/O on the Nim main thread; blocking or CPU-intensive
work should still be moved to an appropriate worker.

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

Exported Nim objects, enums, named tuple aliases, sequences, fixed arrays,
string-keyed tables, and optional values can be used in command parameters and
return values:

```nim
import std/[options, tables]
import nimri_rpc

type
  Theme* = enum
    light, dark

  UserProfile* = object
    name*: string
    age*: int
    theme*: Theme

  Point* = tuple
    x: int
    y: int

proc createProfile*(name: string, theme: Theme,
    nickname: Option[string]): UserProfile {.accessible.} =
  UserProfile(name: name, age: 0, theme: theme)

proc saveLocations*(
    locations: Table[string, seq[Option[Point]]],
    bounds: array[2, Point]):
    tuple[saved: int, primary: Option[Point]] {.accessible.} =
  (saved: locations.len, primary: some(bounds[0]))
```

The generated TypeScript preserves these shapes recursively. For example,
`array[2, Point]` becomes `[Point, Point]`,
`Table[string, seq[Option[Point]]]` becomes
`Record<string, Array<Point | null>>`, and the direct return tuple becomes
`{ saved: number; primary: Point | null }`.

Objects and named tuples cross the wire as JSON objects using their field names.
Both `Table[string, T]` and `OrderedTable[string, T]` also use JSON objects,
while sequences and fixed arrays use JSON arrays. `Option[T]` uses either the
encoded value or JSON `null`. Table ordering is not part of the RPC contract;
`OrderedTable` intentionally uses the same object-based format as `Table`.

A minimal Svelte call can pass all of these shapes through the generated,
type-safe command binding:

```svelte
<script lang="ts">
  import { saveLocations } from './commands/example';

  let saved = 0;

  async function save() {
    const result = await saveLocations(
      { home: [{ x: 1, y: 2 }, null] },
      [{ x: 0, y: 0 }, { x: 10, y: 20 }]
    );
    saved = result.saved;
  }
</script>

<button on:click={save}>Save locations</button>
<p>{saved} locations saved</p>
```

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
