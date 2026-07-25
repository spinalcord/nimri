import std/[options, tables]

type
  Availability* = enum
    offline, online

  Profile* = object
    displayName*: string
    availability*: Availability
    nickname*: Option[string]
    children*: seq[Profile]
    locations*: Table[string, Location]

  Location* = tuple
    x: int
    y: int
