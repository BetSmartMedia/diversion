semver = require 'semver'

module.exports = (port, defaultVersion, state) ->
  server = require('lazorse') ->
    @port = port

    @route '/traffic':
      GET: -> @ok state.traffic()

    @route '/defaultVersion':
      shortName: 'defaultVersion'
      GET: -> @ok defaultVersion

    @route '/versions':
      shortName: "versions"
      GET: -> @ok state.listVersions()

    @route '/version/{range}':
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

    @route '/backends/{version}':
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

    @coerce 'version': (v, next) =>
      if (valid = semver.valid v) then return next null, valid
      next new @errors.InvalidParameter 'version', v
