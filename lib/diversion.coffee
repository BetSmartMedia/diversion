# Diversion - a proxy that chooses backends based on an x-version header
{readFileSync, writeFileSync} = require 'fs'
{request} = require 'http'
bouncy   = require 'bouncy'
semver   = require 'semver'
unless (configFile = process.argv[2])
  console.error "Config file argument is required!"
  process.exit 1

config = JSON.parse readFileSync configFile

# Simple wrapper that reverses the arguments to setInterval
doEvery = (delay, cb) -> setInterval cb, delay

# Register a new backend with the proxy, this *will* block while it saves the
# config file.
registerBackend = (version, backend) ->
  config.backends[version] ?= []
  config.backends[version].push backend
  writeFileSync configFile, JSON.stringify config, null, 2
  {status: 'ok', location: backend.location, version}

# Pick the maximum known version that satisfies a given range
pickVersion = (range) ->
  semver.maxSatisfying Object.keys(config.backends), range

# List all known backends for a specific version
listBackends = (version) ->
  return [null, []] unless version
  [version, config.backends[version] or []]

# Pick one backend from a list, does a simple round-robin for now
pickBackend = (backends) ->
  backend = {}
  until backend.alive
    backend = backends.shift()
    backends.push backend
  backend

# The actual proxy server
bouncy((req, bounce) ->
  reqVer = req.headers['x-version'] ? config.defaultVersion
  unless semver.validRange(reqVer) and (version = pickVersion reqVer)
    res = bounce.respond()
    res.statusCode = 400
    return res.end "Bad version: #{reqVer}"
  unavailable = ->
    res = bounce.respond()
    res.statusCode = 404
    res.end "Version unavailable: #{version}"
  forward = ->
    backends = config.backends[version]
    if backends.length
      backend = pickBackend backends
      bounce(backend.location...).on 'error', (exc) ->
        backend.alive = false
        if config.retry then forward() else unavailable()
    else
      unavailable()
  forward()
).listen config.ports.proxy

# If 
if config.pollFrequency
  doEvery config.pollFrequency, ->
    for v, backends of config.backends
      for b in backends
        do (b) ->
          if b.location.length == 1
            host = '127.0.0.1'
            port = b.location[0]
          else
            [host, port] = b.location
          path = b.healthCheckPath or '/'
          method = 'GET'
          req = request {host, port, path, method}, (res) ->
            b.alive = res.statusCode == 200
          req.on 'error', -> b.alive = false
          req.end()

if config.ports.management
  require('lazorse') ->
    @port = config.ports.management
    @route '/defaultVersion':
      shortName: 'defaultVersion'
      GET: -> @ok config.defaultVersion

    @route '/versions':
      shortName: "versions"
      GET: -> @ok Object.keys config.backends

    @route '/version/{range}':
      shortName: "versionForRange"
      GET: -> @ok pickVersion @range

    @coerce 'range': (r, next) =>
      if (valid = semver.validRange r) then return next null, valid
      next new @errors.InvalidParameter 'range', r

    @route '/backends/{version}':
      shortName: "backends"
      GET: -> @ok listBackends @version
      POST: ->
        if (port = @req.body.port)
          host = @req.body.host ? @req.connection.remoteAddress
          backend = location: [host, port], alive: true
          if @req.body.healthCheckPath
            backend.healthCheckPath = @req.body.healthCheckPath
          @ok registerBackend @version, backend
        else
          @res.statusCode = 422
          @res.end '"port" is required'

    @coerce 'version': (v, next) =>
      if (valid = semver.valid v) then return next null, valid
      next new @errors.InvalidParameter 'version', v
