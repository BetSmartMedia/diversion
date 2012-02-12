###
Diversion - a proxy that chooses backends based on an X-Version header

Copyright (C) 2011 Bet Smart Media Inc. (http://www.betsmartmedia.com)
###
fs         = require 'fs'
bouncy     = require 'bouncy'
dateFormat = require 'dateformat'
StateManager = require('./state_manager')

unless (configFile = process.argv[2])
  console.error "usage: #{process.argv[1]} <config_file>"
  process.exit 1

# Parse config
config = JSON.parse fs.readFileSync configFile

# initialize proxy routing table state
state = new StateManager(config.stateFile)

state.on 'healthChanged', (version, location, alive) ->
  now = dateFormat new Date, "yyyy-mm-dd HH:MM:ss"
  console.log "[#{now}] #{if alive then 'ALIVE' else 'DEAD'}: #{version}@#{location}"

# The proxy server logic
bouncy((req, bounce) ->
  reqVer = req.headers['x-version'] ? config.defaultVersion
  unless (version = state.pickVersion reqVer)
    res = bounce.respond()
    res.statusCode = 400
    return res.end JSON.stringify error: "Bad version: #{reqVer}"
  unavailable = ->
    res = bounce.respond()
    res.statusCode = 404
    res.end JSON.stringify error: "Version unavailable: #{version}"
  forward = ->
    loc = state.pickBackend version
    return unavailable() unless loc?
    [host, port] = loc.split ':'
    bounce(host, port).on 'error', (exc) ->
      state.updateBackend version, loc, false
      if config.retry then forward() else unavailable()
  forward()
).listen config.ports.proxy

# Poll backends to see who's dead and who's alive
if config.pollFrequency
  require('./health_checker')(config.pollFrequency, state)

# Enable the management web-app
if config.ports.management
  require('./management_app')(config.ports.management, config.defaultVersion, state)
