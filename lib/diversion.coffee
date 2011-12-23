#
# Diversion - a proxy that chooses backends based on an X-Version header
#
# Copyright (C) 2011 Bet Smart Media Inc. (http://www.betsmartmedia.com)
#

{request}  = require 'http'
fs         = require 'fs'
bouncy     = require 'bouncy'
semver     = require 'semver'
dateFormat = require 'dateformat'

unless (configFile = process.argv[2])
  console.error "usage: #{process.argv[1]} <config_file>"
  process.exit 1

# Parse config and state files
config = JSON.parse fs.readFileSync configFile
try
  fs.statSync config.stateFile
catch e
  fs.writeFileSync config.stateFile, JSON.stringify backends: {}, null, 2
state = JSON.parse fs.readFileSync config.stateFile

# Simple wrapper that reverses the arguments to setInterval
doEvery = (delay, cb) -> setInterval cb, delay

# Basic logging with date/time stamp
log = (args...) ->
	now = dateFormat new Date, "yyyy-mm-dd HH:MM:ss"
	console.log "[" + now + "]", args...

# Register a new backend with the proxy.
# This *will* block while it saves the state file.
registerBackend = (version, location, cfg) ->
  state.backends[version] ?= {}
  state.backends[version][location] = cfg
  fs.writeFileSync config.stateFile, JSON.stringify state, null, 2
  {status: 'ok', location: location, version: version}

# Update the status (alive/dead) of an existing backend.
# This *will* block while it saves the state file.
updateBackend = (version, location, alive) ->
  state.backends[version][location].alive = alive
  fs.writeFileSync config.stateFile, JSON.stringify state, null, 2

# Pick the maximum known version that satisfies a given range
pickVersion = (range) ->
  semver.maxSatisfying Object.keys(state.backends), range

# List all known backends for a specific version
listBackends = (version) ->
  return [null, []] unless version
  [version, state.backends[version] or {}]

# Pick one backend from a list, does a simple round-robin for now
pickBackend = (backends) ->
  # TODO: make this round-robin
  for loc, stat of backends
    return loc if stat.alive
  null

# The actual proxy server
bouncy((req, bounce) ->
  reqVer = req.headers['x-version'] ? config.defaultVersion
  unless semver.validRange(reqVer) and (version = pickVersion reqVer)
    res = bounce.respond()
    res.statusCode = 400
    return res.end JSON.stringify error: "Bad version: #{reqVer}"
  unavailable = ->
    res = bounce.respond()
    res.statusCode = 404
    res.end JSON.stringify error: "Version unavailable: #{version}"
  forward = ->
    backends = state.backends[version]
    if backends? and Object.keys(backends).length
      loc = pickBackend backends
      return unavailable() unless loc?
      [host, port] = loc.split ':'
      bounce(host, port).on 'error', (exc) ->
        updateBackend version, loc, false
        if config.retry then forward() else unavailable()
    else
      unavailable()
  forward()
).listen config.ports.proxy

# Poll backends to see who's dead and who's alive
if config.pollFrequency
  doEvery config.pollFrequency, ->
    for ver, backends of state.backends
      for loc, stat of backends
        do (ver, loc, stat) ->
          [host, port] = loc.split ':'
          path = stat.healthCheckPath or '/'
          method = 'GET'
          req = request {host:host, port:port, path:path, method:method}, (res) ->
            if res.statusCode == 200 and not stat.alive
              log "Backend #{ver} is ALIVE: #{host}:#{port}" unless stat.alive
              updateBackend ver, loc, true
            else if res.statusCode != 200 and stat.alive
              log "Backend #{ver} is DEAD: #{host}:#{port}" if stat.alive
              updateBackend ver, loc, false
          req.on 'error', ->
            log "Backend #{ver} is DEAD: #{host}:#{port}" if stat.alive
            updateBackend ver, loc, false
          req.end()

if config.ports.management
  require('lazorse') ->
    @port = config.ports.management
    @route '/defaultVersion':
      shortName: 'defaultVersion'
      GET: -> @ok config.defaultVersion

    @route '/versions':
      shortName: "versions"
      GET: -> @ok Object.keys state.backends

    @route '/version/{range}':
      shortName: "versionForRange"
      GET: ->
        ver = pickVersion @range
        return @ok "none" unless ver?
        @ok ver

    @coerce 'range': (r, next) ->
      if (valid = semver.validRange r) then return next null, valid
      @error 'InvalidParameter', 'range', r

    @route '/backends/{version}':
      shortName: "backends"
      GET: -> @ok listBackends @version
      POST: ->
        if (port = @req.body.port)
          host = @req.body.host ? @req.connection.remoteAddress
          cfg = alive: true
          if @req.body.healthCheckPath
            cfg.healthCheckPath = @req.body.healthCheckPath
          @ok registerBackend @version, "#{host}:#{port}", cfg
        else
          @res.statusCode = 422
          @res.end '"port" is required'

    @coerce 'version': (v, next) =>
      if (valid = semver.valid v) then return next null, valid
      next new @errors.InvalidParameter 'version', v
