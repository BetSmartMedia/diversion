###
A simple HTTP poller that health checks all backends periodically
###
{request}  = require 'http'

module.exports = (pollFrequency, state) ->
  setInterval ->
    for ver, backends of state.getState().backends
      for loc, stat of backends
        do (ver, loc, stat) ->
          [host, port] = loc.split ':'
          # XXX - feedback needed: maybe only poll backends that have a set
          # healthCheckPath?
          path = stat.healthCheckPath or '/'
          method = 'GET'
          req = request {host:host, port:port, path:path, method:method}, (res) ->
            state.updateBackend ver, loc, res.statusCode == 200
          req.on 'error', ->
            state.updateBackend ver, loc, false
          req.end()
 
  # End of setInterval
  , pollFrequency
