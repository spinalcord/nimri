import std/[asyncdispatch, options, tables]
import ../../../../../../backend/core/nimri_rpc
import ../../../models

proc inspect*(profiles: array[2, Profile]): Option[Profile] {.accessible.} =
  if profiles.len > 0:
    some(profiles[0])
  else:
    none(Profile)

proc inspect_collections*(
    profiles: Table[string, seq[Option[Profile]]],
    ordered: OrderedTable[string, Location],
    inline: tuple[label: string, points: array[2, Location]]):
    tuple[profiles: Table[string, Profile], selected: Option[Location]] {.
    accessible.} =
  discard

proc trailing_default*(name: string = "World") {.accessible.} =
  discard

proc leading_default*(first: int = 1, second: int) {.accessible.} =
  discard

proc future_string*(value: string): Future[string] {.async, accessible.} =
  result = value

proc future_void*(): Future[void] {.accessible, async.} =
  discard
