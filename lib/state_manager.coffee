fs             = require 'fs'
{EventEmitter} = require 'events'
{inherits}     = require 'util'
semver         = require 'semver'

###
The StateManager encapsulates the state of the proxy table and manages saving it to disk.

It is an EventEmitter and emits the following events:

  ``'registered', version, location, cfg``
    Emitted when a new backend is registered with the proxy

  ``'unregistered', version, location``
    Emitted when a backend is explicitly unregistered from the proxy

  ``'healthChanged', version, location, alive``
    Emitted when a backends state changes from alive to dead or vice-versa

The following events are only emitted if the stateFile config option is set.

  ``'saved', proxyState``
    Emitted when the state file has been successfully written to disk

  ``'saveFailed', err``
    Emitted if writing the state file to disk fails.

If a stateFile is given, and writing to it fails at startup time, the process
will exit immediately with a return code of 2.
###
module.exports = StateManager = (stateFile) ->
  @stateFile = stateFile

  state = backends: {}
 
  # Necessary for initaling monitoring connections
  @getState = -> state

  # If we have a stateFile, read/initialize it and install the save handler
  if @stateFile
    # if state file doesn't exist, meh
    try
      state = JSON.parse fs.readFileSync @stateFile
   
    try
      fs.writeFileSync @stateFile, JSON.stringify(state, null, 2)
    catch e
      # Can't write where the user asked us to, bail out.
      console.error "Writing state file #{@stateFile} failed!\n#{e}"
      process.exit 2

    # The normal save handler
    @save = (cb) ->
      fs.writeFile @stateFile, JSON.stringify(state, null, 2), (err) =>
        if err
          @emit 'saveFailed', err
        else
          @emit 'saved', state
        return cb(err) if typeof cb is 'function'
 
  # Else install a no-op save handler
  else
    @save = (cb) -> cb() if typeof cb is 'function'

  @registerBackend = (version, location, cfg, cb) ->
    state.backends[version] ?= {}
    state.backends[version][location] = cfg
    @emit 'registered', version, location, cfg
    @save (err) ->
      return cb err if err?
      cb null, {version, location}

  @unregisterBackend = (version, location, cb) ->
    backends = state.backends[version]
    x = delete backends[location] if backends?
    deleted = x?
    if Object.keys(backends).length is 0
      delete state.backends[version]
    @emit 'unregistered', version, location
    @save (err) ->
      return cb err if err?
      cb null, deleted

  # Update the status (alive/dead) of an existing backend.
  @updateBackend = (version, location, alive) ->
    was_alive = state.backends[version][location].alive
    state.backends[version][location].alive = alive
    if was_alive != alive
      @save()
      @emit 'healthChanged', version, location, alive

  # Pick the maximum known version that satisfies a given range
  @pickVersion = (range) ->
    return null unless semver.validRange(range)
    semver.maxSatisfying Object.keys(state.backends), range

  @listVersions = -> Object.keys(state.backends)
 
  # List all known backends for a specific version
  @listBackends = (version) ->
    return [null, []] unless version
    [version, state.backends[version] or {}]

  # Map from version -> num requests
  requestCounters = {}
  # Pick one backend from a list, does a simple round-robin for now
  @pickBackend = (version) ->
    backends = state.backends[version]
    locations = Object.keys(backends).filter (l) -> backends[l].alive
    return null unless locations.length
    requestCounters[version] ?= 0
    i = requestCounters[version]++ % locations.length
    location = locations[i]
    @emit 'picked', version, location
    return location

  @traffic = -> requestCounters
  null

inherits(StateManager, EventEmitter)

