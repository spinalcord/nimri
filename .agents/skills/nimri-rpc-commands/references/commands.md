# Command patterns

```nim
import std/asyncdispatch
import nimri_rpc

type Greeting* = object
  message*: string

proc greet*(name: string): Greeting {.accessible.} =
  Greeting(message: "Hello, " & name & "!")

proc loadGreeting*(name: string): Future[Greeting] {.async, accessible.} =
  await sleepAsync(100)
  Greeting(message: "Hello, " & name & "!")

proc formatWelcome*(name: string = "World", enthusiastic = false): string {.accessible.} =
  "Welcome, " & name

proc validateName*(name: string): string {.accessible.} =
  if name.len < 3:
    raise newException(ValueError, "A name needs at least 3 characters.")
  name
```

```svelte
<script lang="ts">
  import { greet } from 'commands/greeting';
  const greeting = await greet('Mara');
</script>
```

- Generated functions always return a Promise, even for immediate Nim commands.
- Use `async` for cooperative asynchronous I/O; `Future` does not make blocking or CPU-intensive work non-blocking.
- Frontend callers may omit trailing arguments with Nim defaults.
- Exceptions reject the Promise; catch expected failures in Svelte.
