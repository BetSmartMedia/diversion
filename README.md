# Diversion

Diversion is an API versioning proxy based on
[bouncy](http://github.com/substack/bouncy) and
[semver](http://github.com/isaacs/node-semver), with an optional REST management
API made with [Lazorse](http://github.com/BetSmartMedia/Lazorse). It interprets
the `X-Version` header of incoming requests as version range, then uses semvers
maxSatisfying algorithm to choose a backend. This means you have all the power
of npm's version ranges (including ~0.2.1 style matching) in your X-Version
headers.

Diversion can automatically remove failed backends and retry requests, but
currently the algorithm is a bit overzealous and has no health checking, so it's
quite possible to end up with no live backends due to transient failure.

Also included is a management API that listens on a different port and allows
backends to register themselves with the proxy.

## License

MIT
