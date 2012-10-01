###
Diversion - a proxy that chooses backends based on an X-Version header

Copyright (C) 2011 Bet Smart Media Inc. (http://www.betsmartmedia.com)
###
bouncy       = require 'bouncy'
StateManager = require('./state_manager')
semver       = require 'semver'
uuid         = require 'node-uuid'

module.exports = (config) ->
  # initialize proxy routing table
  state = new StateManager config.stateFile

  server = bouncy (req, bounce) ->
    if config.useURL and reqVer = semver.validRange req.url.split('/')[1]
      path = '/' + req.url.split('/').slice(2).join('/')
    else
      reqVer = req.headers['x-version'] ? config.defaultVersion

    unless (version = state.pickVersion reqVer)
      res = bounce.respond()
      res.statusCode = 422
      return res.end JSON.stringify error: "Bad version: #{reqVer}"

    if config.tagRequests
      headers = 'x-request-id': uuid()

    unavailable = ->
      res = bounce.respond()
      res.statusCode = 404
      res.end JSON.stringify error: "Version unavailable: #{version}"

    do forwardRequest = (attempt=0) ->
      loc = state.pickBackend version
      return unavailable() unless loc?
      [host, port] = loc.split ':'

      handleError = (err) ->
        if config.pollFrequency
          state.updateBackend(version, loc, false)
        if config.maxRetries and attempt < config.maxRetries
          forwardRequest(attempt + 1)
        else
          unavailable()

      bounce({host, port, path, headers}).on('error', handleError)

  # Poll backends to see who's dead and who's alive
  if config.pollFrequency
    require('./health_checker')(config.pollFrequency, state)

  # Enable the management web-app
  if config.ports?.management
    require('./management_app')(config.ports.management, config.defaultVersion, state)

  # Return the server with the StateManager attached
  server.state = state
  server
