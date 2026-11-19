# Implementation plan

Requirements and background: [task.md](task.md). Branch `ingvarr/2026.11.19-ingress`. This file is live
while the work runs: tick boxes as items finish. It becomes history when the work is done.

## Decisions

| Topic | Decision |
|---|---|
| Listener | The chart's own script, `files/dtss_web.py`. With the web API on, the dtss container runs it instead of upstream's `dtss.py`. Off: the container is unchanged |
| Script | 1. Calls upstream's `start_service`, so the databases, cache and native port stay upstream's. 2. Reads `user:password` lines from a mounted Secret and calls `add_auth_tokens(["Basic <base64>", …])`. 3. Calls `start_web_api("0.0.0.0", <web port>, <empty doc root>, fg, bg, tls_only=False)`. 4. Waits in upstream's `run_until_exit()`, then stops the web API and the server |
| How it runs | `python3 -c <file>`, as the helm test pods run `files/*.py` (`templates/tests/_pod.tpl`): no ConfigMap, and a script change restarts the pod |
| Port | `shyft.webPort` in `_ports.tpl`: base + 2·5 + 1 (20011 by default), passed to the script as an environment variable |
| Auth | Required whenever the web API is on: `webApi.auth.existingSecret` and `key`. The chart never generates credentials |
| TLS | Ends at the Ingress or Gateway. An Ingress without `tls` fails to render. HTTPRoute TLS lives on the Gateway listener, which the chart cannot see: NOTES and the values docs say so |
| Values | New section `webApi` (`enabled`, `auth`, `allowFrom`, threads). Top-level `ingress` and `httpRoute` in `helm create`'s shapes, both off. Backends are fixed to the core Service's `dtss-web` port, not configurable |
| NetworkPolicy | A separate rule admits `webApi.allowFrom` to the web port only. `clientPeers` keeps its meaning (native ports) |
| Guards | In `_helpers.tpl`, beside `shyft.loadBalancerProblem`: a route without `webApi.enabled`, the web API without a Secret, or an Ingress without `tls` each fail with the value to set |
| CI | kind-up installs the Gateway API standard CRDs (pinned v1.6.x, with a Renovate comment), so an HTTPRoute installs. No controller: the API server and kubeconform check the route, and the data path is tested through the Service |
| kubeconform | A CRD schema location pinned by commit, for HTTPRoute |
| Version | 0.1.0: a feature means a minor bump, above both master's 0.0.4 and the licence branch's 0.0.5 |

## Steps

### 1. Spike in the image (docker, no cluster)

- [ ] `DtsServer` at 37.3.0-1.1 has `add_auth_tokens`, `auth_needed` and `start_web_api(…, tls_only)`. If not: stop, report
- [ ] `from hydrology.service.dtss import start_service` works under `python3 -c`
- [ ] A request without a token: what comes back (HTTP status or close)
- [ ] An empty `doc_root` serves no files and no listing
- [ ] A WebSocket client for the tests: a library in the image, or a stdlib client of about 40 lines
- [ ] Results into `docs/shyft-services.md`, in a new section "Web API"

### 2. Chart

- [ ] `_ports.tpl`: `shyft.webPort`
- [ ] `files/dtss_web.py`
- [ ] `_container.tpl`: optional `script`, `extraPorts`, `extraEnv`, `extraVolumeMounts`
- [ ] `core-statefulset.yaml`: dtss runs the script, with the `dtss-web` port and the Secret volume, when on
- [ ] `service.yaml`: the `dtss-web` port when on
- [ ] `networkpolicy.yaml`: the web-port rule for `webApi.allowFrom`
- [ ] `ingress.yaml` (`networking.k8s.io/v1`) and `httproute.yaml` (`gateway.networking.k8s.io/v1`)
- [ ] Guards in `_helpers.tpl`
- [ ] `NOTES.txt`: the URL, that credentials are required, and that the API can write and delete
- [ ] `values.yaml`, then `mise run docs schema`
- [ ] `Chart.yaml` 0.1.0; `CHANGELOG.md` `## [0.1.0]`, under "Added"

### 3. Tests

- [ ] `tests/web_test.yaml`:
  - off: renders nothing new;
  - on: ports at two `basePort`s;
  - Ingress and HTTPRoute shapes;
  - each guard's message;
  - the rule covers the web port only;
  - schema cases.
- [ ] `ci/02-non-default-values.yaml`: web API, Ingress and HTTPRoute on, with a credentials Secret. If the
  Secret can't live there, a new `ci/` file, listed in `ci/README.md`
- [ ] Snapshots: `mise run snapshot-update` only if `ci/02` feeds them; the commit message gives the reason
- [ ] `hack/kind-up.sh`: Gateway API CRDs
- [ ] `kubeconform` task: the HTTPRoute schema
- [ ] helm test: a token-authenticated WebSocket read when the web API is on
- [ ] `hack/web-api-test.sh`:
  - with a token, a read works;
  - without a token, it is refused;
  - from a pod not admitted, it is refused;
  - it keeps the restricted Pod Security Standard.
- [ ] `lint-test.yaml`: a step `mise run test web-api`

### 4. Docs

- [ ] `docs/shyft-services.md`: the Web API section (from step 1), and that each Shyft bump must recheck `files/dtss_web.py`
- [ ] `docs/platforms.md`: a route note per platform, marked untested
- [ ] Root `README.md` and `README.md.gotmpl`: replace "no Ingress" with the precise statement
- [ ] `AGENTS.md`: the invariant "Binary protocol only: no Ingress, no HTTP probes" becomes "native protocol;
  the only HTTP is DTSS's optional, authenticated web API; routes reach that port only". Layout: `files/` also
  holds the dtss web script

### 5. Verify

- [ ] `mise run check` and `mise run check-version`
- [ ] `mise run kind-up`, `mise run load-image`, `mise run e2e`, including `test web-api`. `orb start`
  switches kubectl to `orbstack`: restore `elveli-1` afterwards
- [ ] Renders with default values unchanged
