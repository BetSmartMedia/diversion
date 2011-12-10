# Diversion - a proxy that chooses backends based on an x-version header
{readFileSync, writeFileSync} = require 'fs'
{Server} = require 'http'
bouncy   = require 'bouncy'
semver   = require 'semver'
unless (configFile = process.argv[2])
  console.error "Config file argument is required!"
  process.exit 1

config = JSON.parse readFileSync configFile
config.backends = config.backends

registerBackend = (version, location) ->
  config.backends[version] ?= []
  config.backends[version].push location
  writeFileSync configFile, JSON.stringify config, null, 2
  status = 'ok'
  {status, version, location}

pickVersion = (reqVer) ->
  semver.maxSatisfying Object.keys(config.backends), reqVer

listBackends = (version) ->
  return [null, []] unless version
  [version, config.backends[version] or []]

pickBackend = (backends) ->
  # Simple round-robin for now
  backend = backends.shift()
  backends.push backend
  backend

bouncy((req, bounce) ->
  reqVer = req.headers['x-version'] ? config.defaultVersion
  # validRange matches ~0.1.0, ranges, and single versions
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
      target = pickBackend backends
      bounce(target...).on 'error', (exc) ->
        if not config.retry then unavailable()
        else
          config.backends[version] = backends.filter (backend) -> backend != target
          forward()
    else
      unavailable()
  forward()
).listen config.ports.proxy


if config.ports.management
  require('lazorse') ->
    @port = config.ports.management
    @route '/versions':
      shortName: "versions"
      GET: -> @ok Object.keys(config.backends)

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
        if (path = @req.body.path)
          @ok registerBackend @version, [path]
        else if (port = @req.body.port)
          host = @req.body.host ? @req.connection.remoteAddress
          @ok registerBackend @version, [host, port]
        else
          @res.statusCode = 422
          @res.end '"path" or "port" is required'

    @coerce 'version': (v, next) =>
      if (valid = semver.valid v) then return next null, valid
      next new @errors.InvalidParameter 'version', v
