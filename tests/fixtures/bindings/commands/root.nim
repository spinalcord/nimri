import std/[asyncdispatch, options]
import ../../../../backend/core/nimri_rpc
import ../models

proc inspect*(profiles: array[2, Profile]): Option[Profile] {.accessible.} =
  if profiles.len > 0:
    some(profiles[0])
  else:
    none(Profile)

proc trailing_default*(name: string = "World") {.accessible.} =
  discard

proc leading_default*(first: int = 1, second: int) {.accessible.} =
  discard

proc future_string*(value: string): Future[string] {.async, accessible.} =
  result = value

proc future_void*(): Future[void] {.accessible, async.} =
  discard
