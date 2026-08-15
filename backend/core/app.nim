# Importing the RPC registry initializes every frontend command registration.
{.push warning[UnusedImport]: off.}
import rpc_registry
{.pop.}

import nimri_rpc

proc serveApp*() =
  serveFrontendRpc()
