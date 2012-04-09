###
A simple HTTP poller that health checks all backends periodically
###
{request}  = require 'http'

module.exports = (pollFrequency, state) ->
  setInterval ->
    for ver, backends of state.getState().backends
      for loc, stat of backends when stat.healthCheckPath
        do (ver, loc, stat) ->
          [host, port] = loc.split ':'
          path = stat.healthCheckPath
          method = 'GET'
          req = request {host:host, port:port, path:path, method:method}, (res) ->
            state.updateBackend ver, loc, res.statusCode == 200
          req.on 'error', ->
            state.updateBackend ver, loc, false
          req.end()
    null # End of setInterval function
  , pollFrequency
