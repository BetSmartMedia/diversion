#!/usr/bin/env node
fs = require('fs')
dateFormat = require('dateformat')

if (!(configFile = process.argv[2])) {
  console.error("usage: #{process.argv[1]} <config_file>")
  process.exit(1)
}

config = JSON.parse(fs.readFileSync(configFile))

require('coffee-script')
diversion = require('./lib/diversion')

server = diversion(config)
server.state.on('healthChanged', function (version, location, alive) {
  now = dateFormat(new Date, "yyyy-mm-dd HH:MM:ss")
  msg = "[" + now + "] " + (alive ? 'ALIVE' : 'DEAD') + ': v' + version + '@' + location
  console.log(msg)
})
server.listen(config.ports.proxy)

