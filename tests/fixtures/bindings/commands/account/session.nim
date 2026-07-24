import ../../../../../backend/core/frontend_rpc
import ../../models

proc inspect*(profile: Profile): Profile {.accessible.} =
  profile

proc open_session*(user_name: string, roles: seq[string]) {.accessible.} =
  discard
