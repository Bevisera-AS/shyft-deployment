# Shyft services: what the chart relies on

Reference for whoever changes the chart. Everything here was read from upstream at tag `37.3.0-1.1`
([`examples/hydrology/service/`](https://gitlab.com/shyft-os/shyft/-/tree/37.3.0-1.1/examples/hydrology/service))
or observed in the image `registry.gitlab.com/shyft-os/shyft/fedora44-shyft-app:37.3.0-1.1`. When Shyft is
bumped, check it again: the chart's tests cover the parts marked **tested**.

## Services

Each service is one script in `/opt/shyft/hydrology/service/`. Port = base port + 2 × relative port. The
relative ports are hard-coded in `config.py`; only the base is configurable.

| Service | Script | Relative port | Port at base 20000 | Database under the root | Host variable |
|---|---|---|---|---|---|
| task | `task.py` | 0 | 20000 | `task/db` | `SHYFT_TASK_HOST` |
| rmd (region model description) | `rmd.py` | 1 | 20002 | `gcd/db` | `SHYFT_GCD_HOST` |
| parameter | `parameter.py` | 2 | 20004 | `parameter/db` | `SHYFT_PARAMETER_HOST` |
| state | `state.py` | 3 | 20006 | `state/db` | `SHYFT_STATE_HOST` |
| drms | `drms.py` | 4 | 20008 | none | `SHYFT_DRMS_HOST` |
| dtss | `dtss.py` | 5 | 20010 | `dtss/db` | `SHYFT_DTSS_HOST` |
| dstm | `dstm.py` | 6 | 20012 | none | `SHYFT_DSTM_HOST` |
| stm | `stm.py` | 7 | 20014 | `stm/db` | `SHYFT_STM_HOST` |
| goal_function | `goal_function.py` | 8 | 20016 | `goal_function/db` | `SHYFT_GOAL_FUNCTION_HOST` |

- rmd replaced gcd (geo cell data), which Shyft 28 still shipped. Its database directory and its host
  variable still say `gcd`.
- Base + 2 × relative + 1 is reserved for a web API. These scripts do not start it, so nothing listens there
  (**tested**: the chart exposes no such port).
- The protocol is binary, over TCP, without authentication or TLS. Probes can only be TCP connects. A probe
  connection that opens and closes logs nothing on the server.

## Configuration

Every script takes the same arguments; each falls back to an environment variable.

| Argument | Variable | Default | Meaning |
|---|---|---|---|
| `--base-port` | `SHYFT_SERVICE_BASE_PORT` | 20000 | Base port. 0 means "not set" |
| `--interface` | `SHYFT_SERVICE_INTERFACE` | `127.0.0.1` | Address to listen on |
| `--root-dir` | `SHYFT_SERVICE_ROOT` | `/tmp/shyft_root` | Root of the databases; created if missing |
| `--host` | `SHYFT_SERVICE_HOST` | `localhost` | Where a client finds the other services |
| | `SHYFT_<SERVICE>_HOST` | the host above | Per-service override, see the table |
| | `SHYFT_LOGGING_CONFIG_DIR` | the script directory | Directory with `logging_config.ini` |

- `SHYFT_DTSS_CACHE` exists in `config.py` but has no effect: the scripts pass 10 GiB, and the variable is
  only read for values below 5 MB.
- `--task-host` is parsed and never used: a drms finds task through `--host`. `--drms-port` does not change
  the port a drms listens on.

How the chart sets them:

- Core containers get `SHYFT_SERVICE_BASE_PORT`, `SHYFT_SERVICE_ROOT=/shyft-var` and
  `SHYFT_SERVICE_INTERFACE=0.0.0.0`, and no host: they share a pod, so `localhost` is right. A shell in any
  core container therefore has a working Shyft client configuration.
- A drms gets `--interface $(POD_IP) --host <core Service> --root-dir /tmp`.
- Test pods get `SHYFT_SERVICE_HOST=<core Service>`.
- Every pod has `enableServiceLinks: false`. Kubernetes would otherwise inject `<SERVICE>_SERVICE_HOST` for
  each Service in the namespace; for a Service named `shyft` that is `SHYFT_SERVICE_HOST`, with the cluster
  IP in it (**tested**: `ci/02-non-default-values.yaml` names the Service `shyft`).
- `PYTHONUNBUFFERED=1`: the registration messages below are `print()` calls. Buffered, they would not show
  up in `kubectl logs` until much later.

## drms registration

Task keeps the list of drms in memory. There is no API to read it.

1. A drms starts its server, then calls task: "register `<interface>:<port>`". It retries for 10 seconds,
   printing `Failed to register …` and then `Successfully registered`.
2. It repeats the call every 5 seconds for as long as it runs. Registering twice is harmless. This is what
   brings the list back after task restarts (**tested**: `hack/persistence-test.sh`).
3. On SIGTERM it calls "unregister" and exits (**tested**: `hack/drms-test.sh`, scale down).
4. For a run, task takes the first drms in its queue, checks that it answers, uses it, and puts it back at
   the end. So runs rotate over the drms (**tested**: three runs reach three drms).

Why `--interface` must be the pod IP: the drms registers `<interface>:<port>`. With `0.0.0.0` it registers
`<--host>:<port>` instead, which is task's own address.

A registration never expires. If a drms dies without unregistering, task still picks it: the health check
times out after 1 second, task logs `Failed to connect to drms client`, waits another second and takes the
next one. The entry stays until someone unregisters it or task restarts. `mise run upstream-drms` checks this
(not in CI; run it after a Shyft bump): it registers an unreachable address and counts the retries. If
upstream adds an expiry, that check fails and the spot-instance advice in the chart README can be dropped.

A run does not survive losing its drms: the call raises, task logs the exception and returns `false` to the
client. Nothing retries (`fx_run_model` in `examples/hydrology/task/run.py`).

Statistics (`drms_stats` in the run arguments) are written by the drms straight to dtss, at the address the
client put in `dtss_host_port`. That address must resolve from a drms pod, so it must be the core Service,
not `localhost` (**tested**: the model-run helm test reads the statistics back).

## The image

| | |
|---|---|
| User | `ci`, uid 1000, gid 1000 (`wheel`). The image config names the user, so `runAsUser` must be numeric |
| Architecture | amd64 only |
| Size | 1.0 GB compressed, 2.9 GB unpacked |
| Python | 3.14; `PYTHONPATH=/opt/shyft` |
| Demo code | `/opt/shyft/hydrology/demo/`: `fill_dummy_data.py`, `run_model.py`. The model-run test imports it |
| Tools | `bash`, `curl`, `timeout`. No `nc` |

It runs with a read-only root filesystem, no capabilities and any uid, as long as `/tmp` and the database
root are writable. `/tmp` is needed for `/tmp/shyft-hydro-app.log`, the error log that `logging_config.ini`
opens at start.

Upstream's registry keeps only a few tags per repository: the Shyft 28 image that Sigma2's setup used is
gone. Mirror the images you depend on.

## Resource behaviour

- An idle service uses about 200 MiB. The core pod idles at about 1.7 GiB.
- Under the CI workload (the demo model, five model runs) every service peaked at 130–185 MiB, a drms at
  about 130 MiB and a helm test pod at about 140 MiB (cgroup `memory.peak`, kind, 2026-11-19). The chart's
  default memory limits (1 GiB, dstm 2 GiB, dtss 4 GiB, drms 2 GiB, test pods 512 MiB) leave room for that
  many times over; they are not production sizes.
- dtss and dstm each set a cache target of 10 GiB, and dtss an index cache of 4 GiB. They grow with use. A
  memory limit below that can get them killed under load.
- A drms uses every core it is given during a run and is idle otherwise.
- RocksDB preallocates its log files, so empty databases are not small: 0.2 GiB on a kind volume (btrfs),
  1.6 GiB on a tmpfs. Not measured on EBS or Azure disks.

## Looks wrong, is not

- `rocksdb: Error when reading /shyft-var/dtss/db/r/rdb_d dir NotFound` at dtss's first start: the directory
  does not exist yet, and dtss creates it.
- A line of dots in every log: each service prints one every 5 seconds.
- `Failed to register … connect timed out` once or twice in a drms log at install: task was not up yet.
