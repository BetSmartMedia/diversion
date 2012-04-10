semver = require 'semver'

module.exports = (port, defaultVersion, state) ->
  server = require('lazorse').server {port}, ->

    @resource '/traffic':
      GET: -> @ok state.traffic()

    @resource '/defaultVersion':
      shortName: 'defaultVersion'
      GET: -> @ok defaultVersion

    @resource '/versions':
      shortName: "versions"
      GET: -> @ok state.listVersions()

    @resource '/version/{range}':
      shortName: "versionForRange"
      GET: ->
        @ok pickVersion(@range) or false

    @coerce range: (r, next) ->
      if (valid = semver.validRange r) then return next null, valid
      @error 'InvalidParameter', 'range', r

    @helper getHostAndPort: (withPort) ->
      if (port = @req.body.port)
        host = @req.body.host ? @req.connection.remoteAddress
        withPort.call @, host, port
      else
        @res.statusCode = 422
        @res.end '"port" is required'

    @resource '/backends/{version}':
      shortName: "backends"
      GET: -> @ok state.listBackends @version
      POST: ->
        @getHostAndPort (host, port) ->
          cfg = if @req.body.healthCheckPath
            alive: false
            healthCheckPath: @req.body.healthCheckPath
          else
            alive: false
          state.registerBackend @version, "#{host}:#{port}", cfg, @data
      DELETE: ->
        @getHostAndPort (host, port) ->
          state.unregisterBackend @version, "#{host}:#{port}", @data

    @coerce 'version', "A semver compatible version string", (v, next) =>
      if (valid = semver.valid v) then return next null, valid
      next new @errors.InvalidParameter 'version', v

    @before @findResource, 'static', __dirname + '/../public', maxAge: 99999999999999

  # mmm, sockety
  sockjs = require 'sockjs'

  uiSockServer = sockjs.createServer sockjs_url: "http://cdn.sockjs.org/sockjs-0.2.min.js"
  uiSockServer.on 'connection', (conn) ->

    conn.write JSON.stringify type: 'state', backends: state.getState().backends

    for type in ['registered', 'unregistered', 'picked'] then do (type) ->
      state.on type, (version, location) ->
        conn.write JSON.stringify {type, version, location}

    state.on 'healthChanged', (version, location, alive) ->
      conn.write JSON.stringify {type: 'health', version, location, alive}

  uiSockServer.installHandlers(server, prefix: '[/]monitor')
