#!/usr/bin/env node
fs = require('fs')

if (!(configFile = process.argv[2])) {
  console.error("usage: #{process.argv[1]} <config_file>")
  process.exit(1)
}

config = JSON.parse(fs.readFileSync(configFile))

diversion = require('./lib/diversion')

server = diversion(config)
server.state.on('healthChanged', function (version, location, alive) {
  msg = "[" + (new Date).toISOString() + "] " + (alive ? 'ALIVE' : 'DEAD') + ': v' + version + '@' + location
  console.log(msg)
})
server.listen(config.ports.proxy)

