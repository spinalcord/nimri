import std/tables
import ../../../backend/core/nimri_rpc

when defined(unsupportedTable):
  proc invalid*(value: Table[int, string]) {.accessible.} =
    discard
else:
  proc invalid*(value: (string, int)) {.accessible.} =
    discard
