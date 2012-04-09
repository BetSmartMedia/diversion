http = require 'http'
assert = require 'assert'
diversion = require '../lib/diversion'

describe "Proxy with tagRequests enabled", ->
  host = '127.0.0.1'
  port = 0
  path = '/'
  proxy = diversion
    retry: false
    defaultVersion: '~0.1.0'
    tagRequests: true
  state = proxy.state

  backend = http.createServer (req, res) ->
    res.writeHead 200,
      'content-type': 'text/plain'
      'x-request-id': req.headers['x-request-id']
    res.end('ok')

  before (start) ->
    proxy.listen ->
      port = proxy.address().port
      backend.listen 0, '127.0.0.1', ->
        baddress = "127.0.0.1:" + backend.address().port
        state.registerBackend '0.1.0', baddress, {alive: true}, (err, registered) ->
          start(err)

  after ->
    backend.close()
    proxy.close()

  it 'adds an x-request-id header', (done) ->
    http.get {host, port, path}, (res) ->
      res.on 'error', done
      assert res.headers['x-request-id']
      done()

