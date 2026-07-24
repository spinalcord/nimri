import std/options

type
  Availability* = enum
    offline, online

  Profile* = object
    displayName*: string
    availability*: Availability
    nickname*: Option[string]
    children*: seq[Profile]
