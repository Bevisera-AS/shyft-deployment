# Task: Ingress and HTTPRoute

Plan: [implementation.md](implementation.md).

## Background

- `TODO.md` asks for an Ingress. The chart has none: Shyft's services speak a native binary protocol over TCP,
  and an Ingress or HTTPRoute carries HTTP only.
- Shyft has one HTTP interface: an optional WebSocket "web API" on the DTSS server (time series). Upstream's
  hydrology scripts do not start it, and have no flag or variable to start it.
- Sigma2's setup ([Zenodo 17813414](https://doi.org/10.5281/zenodo.17813414)) had two public HTTPS Ingresses,
  `dtss.shyft.nird.sigma2.no` → 22010 and `services.shyft.nird.sigma2.no` → 22000. Both pointed at binary
  ports, so they could not have worked. Both names have stopped resolving. They show that access from
  outside the cluster was wanted, not which protocol.
- ingress-nginx was retired in March 2026. Gateway API v1.6.0 (June 2026) is the maintained path. Helm 4's
  `helm create` scaffolds both `ingress:` and `httpRoute:`.

## Requirements

1. An opt-in DTSS web API, off by default. With it off, every render is identical to the chart without this
   feature.
2. An optional Ingress and an optional HTTPRoute, independent of each other. Each routes to the DTSS web port
   only.
3. Authentication is always on: the chart refuses to render the web API without credentials. An Ingress must
   have `tls`.
4. No route ever reaches a native port or DStm's web API.
5. NetworkPolicy admits named peers (the ingress controller or gateway) to the web port only.
6. Tested on kind:
   - a read with credentials works;
   - a read without credentials is refused;
   - a read from a pod that is not admitted is refused.
7. Every port still comes from `_ports.tpl`. The project's rules in `AGENTS.md` still hold.

Exposure: whether the endpoint faces the internet is the operator's choice. The chart cannot see whether a
Gateway or IngressClass is internal. It requires authentication and, for an Ingress, TLS. NOTES says the
endpoint can write and delete time series.

## Out of scope

- Routes for the native protocol (TCPRoute, TCP passthrough). The internal load balancer covers native
  clients outside the cluster.
- DStm's web API: it has no authentication.
- Serving a browser application from Shyft (`doc_root`).
- TLS inside Shyft (`tls_only`): TLS ends at the Ingress or Gateway.
- A gateway or ingress controller in CI.

## Assumptions

Verified in upstream source at tag 37.3.0-1.1:

- `examples/hydrology/service/config.py` computes `web_port = base + 2·rel + 1`, and `start_server` never calls
  `start_web_api`.
- `dtss.py` is `HydroServiceConfig(...).dtss.start()` followed by `run_until_exit()`.
- The chart's dtss calls `set_can_remove(True)`: the web API's `remove` is live.
- Upstream's own web examples call `start_web_api` on a running server, in the same process.

Read in the current Shyft docs ([time_series API](https://shyft-os.gitlab.io/shyft-doc/content/time_series/api.html),
[DTSS web API](https://shyft-os.gitlab.io/shyft-doc/content/web_api/dtss.html)). These docs are not pinned to
37.3.0-1.1:

- `DtsServer.start_web_api(host_ip, port, doc_root, fg_threads=2, bg_threads=4, tls_only=False)`.
- `DtsServer.add_auth_tokens(["Basic <base64 user:pwd>"])` turns authentication on, and `auth_needed` reports
  it. The docs say to send tokens only over https/wss, or another protected path.
- The web API writes as well as reads: `store_ts`, `remove`, `q_put`, `q_get`, `q_maintain` (`flush_all`).
- `DStmServer` has a web API and no auth methods. The hydrology servers have no web API.

Unverified (step 1 of the plan checks them in the image):

- At 37.3.0-1.1, `add_auth_tokens`, `auth_needed` and `start_web_api(tls_only)` exist and behave as documented.
- `from hydrology.service.dtss import start_service` imports under `python3 -c`.
- What a request without a token gets back.
- What an empty `doc_root` serves.
- A WebSocket client is available to the test pods.

## Open questions

- For Olga: what were the Sigma2 Ingresses meant for: browsers, or native clients?
- Does NIRD run an Ingress controller, Gateway API, or both, in 2026?
- Is a public, authenticated DTSS endpoint acceptable to Bevisera, or private only?
