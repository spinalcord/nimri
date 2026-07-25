import ../../../backend/core/nimri_rpc

proc same_name*(value: int): string {.accessible.} =
  "second:" & $value
