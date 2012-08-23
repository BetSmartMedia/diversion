[![build status](https://secure.travis-ci.org/BetSmartMedia/diversion.png)](http://travis-ci.org/BetSmartMedia/diversion)
# Diversion

Diversion is a versioning HTTP proxy based on
[bouncy](http://github.com/substack/bouncy) and
[semver](http://github.com/isaacs/node-semver). It uses semver to parse version
numbers (or ranges) and then bounces the request to the highest-versioned backend
that satisfies the requested using the maxSatisfying algorithm. This means you
have all the power of npm's version ranges (including ~0.2.1 style matching) for
your proxied services.

Install it:

    npm install diversion

Run it:

		diversion config.json # See example_config.json to get started

## Requesting specific versions 

By default the proxy will look for a version/range in the 'X-Version' header,
but it can also check the first path component of the requested URL for a
version and use that instead if you set "useURL" to true in your config.

## Management API and monitoring page

Also included is an optional management API that listens on a different port and
allows on-line updating of the proxy configuration. To enable this service
include a 'management' port in the 'ports' object in your config. Note that
there is no authentication on this service, so don't expose the port to anybody
you don't want to be able to modify the proxy.

The management service also serves a monitoring page on _/status_ where you can
see the state of registered backends, add and remove backends, and watch
requests get forwarded.

If you'd rather not run the management service, you will need to write your
state file manually and make sure your config.json has the correct path to it.
Here is an example state.json file to get you started:

```javascript
{
  "backends": {
    "0.1.1": {
      "127.0.0.1:3000": {
        "alive": true,
        "healthCheckPath": "/"
      },
      "127.0.0.1:3001": {
        "alive": true,
        "healthCheckPath": "/"
      }
    },
    "0.2.1": {
      "127.0.0.1:3300": {
        "alive": true,
        "healthCheckPath": "/"
      },
      "127.0.0.1:3301": {
        "alive": true,
        "healthCheckPath": "/"
      }
    },
  }
}
```

## Health checks and error recovery

If 'pollFrequency' is set to a non-zero value in the config, diversion will poll
any backends that specified a healthCheckPath and update their live/dead status
according to whether they respond with 200 status codes.

When an error occurs, and health checks are being performed, diversion will
disable the backend that caused the error and continue to poll it until it come
back online.

If 'maxRetries' is set to a non-zero value in the config, diversion will try
the next live backend up to 'maxRetries' times or it runs out of live backends.

## License

MIT
