http = require 'http'
assert = require 'assert'
diversion = require '../lib/diversion'

host = '127.0.0.1'

versions = [
  '1.0.8'
  '1.1.0'
  '1.1.3'
]

ranges =
  "~1.0.0": "1.0.8"
  "<1.1.0": "1.0.8"
  ">1.0.0": "1.1.3"
  "~1.1.3": "1.1.3"

versionedService = (version, cb) ->
  server = http.createServer (req, res) ->
    res.writeHead 200, 'content-type': 'text/plain', 'x-version': version
    res.end 'ok'
  .listen 0, host, -> cb(server)

describe "Proxy with multiple versions", ->
  backends = []
  port = null
  before (start) ->
    i = 0
    step = ->
      return if --i > 0
      server.listen ->
        port = server.address().port
        start()

    server = diversion
      retry: false
      defaultVersion: '~1.0.0'

    for version in versions then do (version) ->
      i++
      versionedService version, (backend) ->
        backends.push backend
        bport = backend.address().port
        server.state.registerBackend version, host+':'+bport, alive: true, step

  after = ->
    server.close()
    for backend in backends
      backend.close()

  path = '/'

  for version in versions then do (version) ->
    it "at has version #{version}", (done) ->
      headers = 'x-version': version
      http.get {host, port, headers, path}, (res) ->
        assert.equal 200, res.statusCode
        assert.equal version, res.headers['x-version']
        done()

  for range, version of ranges then do (range, version) ->
    it "returns #{version} for #{range}", (done) ->
      headers = 'x-version': range
      http.get {host, port, headers, path}, (res) ->
        assert.equal 200, res.statusCode
        assert.equal version, res.headers['x-version']
      done()
