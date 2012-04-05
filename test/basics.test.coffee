http = require 'http'
assert = require 'assert'
diversion = require '../lib/diversion'

# Tests
describe "Proxy", ->
  host = '127.0.0.1'
  port = 0
  path = '/'
  server = diversion retry: false, defaultVersion: '~0.1.0'
  state = server.state

  before (start) ->
    server.listen ->
      port = server.address().port
      start()

  after -> server.close()

  it "has no available versions", (done) ->
    http.get {path, host, port}, (res) ->
      assert.equal 422, res.statusCode
      done()

  describe "with a dead backend", ->
    before (start) ->
      state.registerBackend '0.1.0', '127.0.0.1:4043', {alive: false}, (err, registered) ->
        start(err)

    it "won't match a range (422)", (done) ->
      http.get {path, host, port}, (res) ->
        assert.equal 422, res.statusCode
        done()

    it "will match the exact version, but 404", (done) ->
      http.get {path, host, port, headers: {'x-version': '0.1.0'}}, (res) ->
        assert.equal 404, res.statusCode
        done()

    describe "that is now alive", ->
      backendServer = null
      before (start) ->
        backendServer = http.createServer (req, res) ->
          res.writeHead 200, 'content-type': 'text/plain'
          res.end 'ok'
        backendServer.listen 4043, '127.0.0.1', ->
          state.updateBackend "0.1.0", "127.0.0.1:4043", true
          start()

      after -> backendServer.close()

      it "proxies the request", (done) ->
        http.get {path, host, port}, (res) ->
          assert.equal 200, res.statusCode
          done()


