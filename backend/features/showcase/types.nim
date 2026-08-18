type
  ActivityPhase* = enum
    queued,
    connecting,
    processing,
    completed

  ShowcaseOverview* = object
    application*: string
    framework*: string
    transport*: string
    detail*: string

  ActivityEvent* = object
    phase*: ActivityPhase
    message*: string
    elapsedMilliseconds*: int
