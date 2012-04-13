http = require 'http'
diversion = require '../lib/diversion'
assert = require 'assert'

describe "Proxy with management api enabled", ->
  proxy = diversion
    retry: false
    defaultVersion: '1.2.3'
    pollFrequency: 250
    ports: {management: 34343}

  requested = false
  backend = http.createServer (req, res) ->
    requested = true
    res.end('ok')

  before (start) ->
    # A timeout to allow the initial health check to happen
    waitStart = -> setTimeout start, 400
    proxy.listen 0, ->
      backend.listen 0, '127.0.0.1', ->
        http.request({
          method:  'POST'
          port:    34343
          path:    '/backends/1.2.3'
          headers: {'content-type': 'application/json'}
        }, (res) ->
          res.on 'end', waitStart
          res.on 'error', waitStart
        ).end JSON.stringify
          port: backend.address().port
          healthCheckPath: '/'

  it 'can have a backend added via POST request', ->
    assert proxy.state.pickBackend '1.2.3'

  it 'health checks the backend', ->
    assert requested
