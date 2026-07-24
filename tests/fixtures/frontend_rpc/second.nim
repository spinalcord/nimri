import ../../../backend/core/frontend_rpc

proc same_name*(value: int): string {.accessible.} =
  "second:" & $value
