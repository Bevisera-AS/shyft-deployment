"""Print what the Shyft databases hold, as one line of JSON. Read-only.

hack/*-test.sh run it inside the core pod (localhost, base port from the pod's environment) before and after
a restart, an upgrade or a reinstall, and compare the lines.
"""
import json

from shyft.time_series import TimeSeries, TsVector, UtcPeriod, shyft_url, time

from hydrology.service.config import HydroServiceConfig

cfg = HydroServiceConfig()


def names(client) -> list[str]:
    return sorted(m.name for m in client.get_model_infos(mids=[]))


task = cfg.task.client()
tasks = {m.name: m.id for m in task.get_model_infos(mids=[])}
assert "nea-run" in tasks, "no demo task: run the model-run test first, an empty database proves nothing"
task_id = tasks["nea-run"]
cases = sorted(c.id for c in task.read_model(mid=task_id).cases)
assert cases, "the demo task has no cases: run the model-run test first"

t0 = time("2010-01-01T00:00:00Z")
period = UtcPeriod(t0, t0 + time(3600 * 24 * 30))
dtss = cfg.dtss.client()
discharge = {}
for case in cases:
    url = shyft_url("r", f"hydrology/{task_id}_{case}_1.discharge")
    values = dtss.evaluate(TsVector([TimeSeries(url)]), period)[0].values
    discharge[case] = [len(values), round(float(sum(values)), 6)]

print(json.dumps({
    "task": sorted(tasks),
    "cases": cases,
    "rmd": names(cfg.rmd.client()),
    "parameter": names(cfg.parameter.client()),
    "state": len(cfg.state.client().get_model_infos(mids=[])),
    "goal_function": names(cfg.goal_function.client()),
    "discharge": discharge,
}, sort_keys=True))
