# RPC type contract

## Supported values

Supported: strings, booleans, numeric types, enums, `Option[T]`, sequences, fixed arrays, `Table[string, T]`, `OrderedTable[string, T]`, exported plain objects with exported fields, and named tuples.

## TypeScript representation

| Nim | Generated TypeScript / JSON |
| --- | --- |
| `Option[T]` | `T \| null` |
| `seq[T]` | `Array<T>` |
| `array[2, Point]` | `[Point, Point]` |
| `Table[string, T]` | `Record<string, T>` |
| `OrderedTable[string, T]` | `Record<string, T>` |
| object / named tuple | JSON object with field names |

`OrderedTable` has the same JSON representation as `Table`; ordering is not guaranteed.

## Example

```nim
import std/[options, tables]
import nimri_rpc

type
  Theme* = enum
    light, dark

  Point* = tuple
    x: int
    y: int

  UserProfile* = object
    name*: string
    theme*: Theme
    nickname*: Option[string]

proc saveLocations*(locations: Table[string, seq[Option[Point]]],
    bounds: array[2, Point]):
    tuple[saved: int, primary: Option[Point]] {.accessible.} =
  (saved: locations.len, primary: some(bounds[0]))
```

Unsupported: positional tuples, tables with non-string keys, references, pointers, generic command procedures, object inheritance, variant fields, and object default field values.
