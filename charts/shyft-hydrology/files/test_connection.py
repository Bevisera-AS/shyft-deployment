"""helm test: every core service answers a read-only call through the Kubernetes Service.

Host and base port come from SHYFT_SERVICE_HOST and SHYFT_SERVICE_BASE_PORT, read by Shyft's own
HydroServiceConfig, so this also checks the chart's ports against upstream's port arithmetic.
"""
import sys
import time

from hydrology.service.config import HydroServiceConfig

cfg = HydroServiceConfig()

# Nothing here writes. The model stores list their models; dtss and dstm report their version.
CHECKS = {
    "task": lambda: len(cfg.task.client().get_model_infos(mids=[])),
    "rmd": lambda: len(cfg.rmd.client().get_model_infos(mids=[])),
    "parameter": lambda: len(cfg.parameter.client().get_model_infos(mids=[])),
    "state": lambda: len(cfg.state.client().get_model_infos(mids=[])),
    "dtss": lambda: cfg.dtss.client().get_server_version(),
    "dstm": lambda: cfg.dstm.client().get_server_version(),
    "stm": lambda: len(cfg.stm.client().get_model_infos(mids=[])),
    "goal_function": lambda: len(cfg.goal_function.client().get_model_infos(mids=[])),
}
PORTS = {
    "task": cfg.task.cfg.port,
    "rmd": cfg.rmd.cfg.port,
    "parameter": cfg.parameter.cfg.port,
    "state": cfg.state.cfg.port,
    "dtss": cfg.dtss.cfg.port,
    "dstm": cfg.dstm.cfg.port,
    "stm": cfg.stm.cfg.port,
    "goal_function": cfg.goal_function.cfg.port,
}


def check(name: str, attempts: int = 10) -> bool:
    for attempt in range(1, attempts + 1):
        try:
            answer = CHECKS[name]()
            print(f"ok    {name:<14} {cfg.host}:{PORTS[name]}  -> {answer}", flush=True)
            return True
        except Exception as e:  # noqa: BLE001  any failure is a failed check
            error = e
            time.sleep(2)
    print(f"FAIL  {name:<14} {cfg.host}:{PORTS[name]}  {error}", flush=True)
    return False


results = [check(name) for name in CHECKS]
sys.exit(0 if all(results) else 1)
