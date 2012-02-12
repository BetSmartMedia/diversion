###
Diversion - a proxy that chooses backends based on an X-Version header

Copyright (C) 2011 Bet Smart Media Inc. (http://www.betsmartmedia.com)
###
bouncy     = require 'bouncy'
StateManager = require('./state_manager')
semver = require 'semver'

module.exports = (config) ->
  # initialize proxy routing table state
  state = new StateManager(config.stateFile)

  # The proxy server logic
  server = bouncy((req, bounce) ->
    # URL -> Header -> 
    if config.useURL and reqVer = semver.validRange req.url.split('/')[1]
      path = '/' + req.url.split('/').slice(2).join('/')
    else
      reqVer = req.headers['x-version'] ? config.defaultVersion

    unless (version = state.pickVersion reqVer)
      res = bounce.respond()
      res.statusCode = 422
      return res.end JSON.stringify error: "Bad version: #{reqVer}"
    unavailable = ->
      res = bounce.respond()
      res.statusCode = 404
      res.end JSON.stringify error: "Version unavailable: #{version}"
    forward = ->
      loc = state.pickBackend version
      return unavailable() unless loc?
      [host, port] = loc.split ':'
      bounce({host, port, path}).on 'error', (exc) ->
        state.updateBackend version, loc, false
        if config.retry then forward() else unavailable()
    forward()
  )

  # Poll backends to see who's dead and who's alive
  if config.pollFrequency
    require('./health_checker')(config.pollFrequency, state)

  # Enable the management web-app
  if config.ports?.management
    require('./management_app')(config.ports.management, config.defaultVersion, state)

  # Return the server with the StateManager attached
  server.state = state
  server
