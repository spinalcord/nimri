import nimri_rpc
import ../abc

type
  someType* = object
    hey*: string

proc abctest*(something: someType): string {.accessible.} =
  "test"
