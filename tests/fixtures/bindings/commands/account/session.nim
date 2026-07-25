import std/asyncdispatch
import ../../../../../backend/core/nimri_rpc
import ../../models

proc inspect*(profile: Profile): Profile {.accessible.} =
  profile

proc open_session*(user_name: string, roles: seq[string]) {.accessible.} =
  discard

proc load_profile*(profile: Profile): Future[Profile] {.async, accessible.} =
  result = profile
