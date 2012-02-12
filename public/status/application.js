// View model representing the proxy server
var DiversionProxy = function () {
	this.versions = ko.observableArray([])

	this.getOrCreateVersion = function (versionString) {
		var matches = this.versions().filter(function (v) { return v.versionString === versionString })
		if (matches.length) return matches[0]
		var v = new BackendVersion(this, versionString)
		this.versions.push(v)
		return v
	}

	this.addBackend = function () {
		var version = prompt("Version?", "1.2.3")
			, address = prompt("Address?", "localhost:3000")
			, healthCheckPath = prompt("Health check path?", '/health')
			, parts = address.split(':')
			, host = parts[0]
			, port = parts[1] || '80'
    if (!(version && address)) return
		var data = {host: host, port: port, healthCheckPath: healthCheckPath}
		var _this = this
		$.post('/backends/' + version, data, function (data) {
			if (!(data && data.version)) debugger
			var v = _this.getOrCreateVersion(data.version)
			v.getOrCreateBackend(data.location)
		})
	}

	this.update = function(backends) {
    for (var versionString in backends) {
      var v = this.getOrCreateVersion(versionString)
      for (var address in backends[versionString]) {
        var b = v.getOrCreateBackend(address)
				b.alive(backends[versionString][address].alive)
      }
    }
	}
}

// Represents a version registered on a proxy and the backends for it
var BackendVersion = function (diversion, versionString) {
	this.diversion = diversion
	this.versionString = versionString // Not changeable
	this.backends = ko.observableArray([])
  var _this = this
	this.available = ko.computed(function () {
		return (_this.backends().filter(function (b) { return b.alive() })).length > 0
	}, this)

	this.getOrCreateBackend = function(address) {
		var matches = this.backends().filter(function (b) { return b.address === address })
		if (matches.length) return matches[0]
		var b = new Backend(this, address)
		this.backends.push(b)
		return b
	}

	this.removeBackend = function (backend) {
		this.backends.remove(backend)
		if (this.backends().length < 1) this.diversion.versions.remove(this)
	}
}

var Backend = function(version, address) {
	this.version = version
	this.address = address
  this.addressId = address.replace(/[.:]/g, '_')
	this.alive = ko.observable()

	this.unregister = function() {
		var parts = this.address.split(':')
			, host = parts[0]
			, port = parts[1] || 80
			, _this = this

		$.ajax('/backends/' + this.version.versionString, {
			type: 'DELETE',
			data: {host: host, port: port},
		})
	}

  this.picked = function() {
    var el = $('#' + this.addressId + ' .indicator')
    el.fadeIn(1, function() { el.fadeOut(150) })
  }
  this.picked()
}

$.ajaxSetup({accepts: 'application/json'})
window.diversion_proxy = new DiversionProxy
ko.applyBindings(diversion_proxy)

var sockjs = new SockJS('/monitor')
sockjs.onmessage = function (e) {
  var data
  try {
    data = JSON.parse(e.data)
  } catch (e) {
    console.log("Message was not JSON: " + e.data)
    return
  }
  if (!(data && data.type)) {
    console.log("Message had no 'type'")
    console.log(data)
    return
  }
  if (data.type === 'state') {
    window.diversion_proxy.update(data.backends)
    return
  }
  var v = window.diversion_proxy.getOrCreateVersion(data.version)
  var b = v.getOrCreateBackend(data.location)
  switch (data.type) {
    case 'unregistered': v.removeBackend(b); break
    case 'health': b.alive(data.alive); break
    case 'picked': b.picked(); break
  }
}

$(function() { $('.indicator').css('opacity', 0) })
