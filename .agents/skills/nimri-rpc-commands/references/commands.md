# Command patterns

```nim
import std/asyncdispatch
import std/asyncstreams
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

proc produceMessages(stream: FutureStream[string]): Future[void] {.async.} =
  try:
    await stream.write("first")
    await stream.write("second")
    stream.complete()
  except ValueError:
    # Cancellation closes the stream and makes later writes fail.
    discard
  except CatchableError as exception:
    stream.fail(exception)

proc messages*(): FutureStream[string] {.accessible.} =
  result = newFutureStream[string]("messages")
  asyncCheck produceMessages(result)
```

```svelte
<script lang="ts">
  import { greet } from 'rpc/commands/greeting';
  const greeting = await greet('Mara');
</script>
```

```svelte
<script lang="ts">
  import { messages } from 'rpc/commands/greeting';

  async function consumeMessages() {
    try {
      for await (const message of messages()) {
        console.log(message);
      }
    } catch (reason) {
      console.error('Message stream failed', reason);
    }
  }

  const stream = messages();
  await stream.cancel();
</script>
```

- Generated immediate and `Future[T]` functions return a Promise.
- Generated `FutureStream[T]` functions return a lazy, single-use
  `NimriStream<T>` implementing `AsyncIterableIterator<T>`.
- Use `async` for cooperative asynchronous I/O; `Future` does not make blocking or CPU-intensive work non-blocking.
- Frontend callers may omit trailing arguments with Nim defaults.
- Exceptions reject the Promise; catch expected failures in Svelte.
- Producer failures and JSON serialization failures reject the next stream read.
- `return()` or `cancel()` closes the underlying `FutureStream`; producers must
  await writes and handle the resulting `ValueError`.
- Return `FutureStream[T]` directly. `FutureStream[void]`, nested stream values,
  and `Future[FutureStream[T]]` are unsupported.
