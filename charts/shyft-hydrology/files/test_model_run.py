"""helm test (opt-in, tests.modelRun.enabled): seed upstream's demo model and run it.

It WRITES to the databases: the 'nea' demo model, its tasks, and one new case with result series per
invocation. It is meant for CI and for checking a fresh install, not for a system with real data.

What a pass proves: task reaches rmd, parameter, state and dtss; a drms is registered with task and
task can reach it; that drms can reach dtss through the Service; results are stored and readable.
"""
import json
import math
import sys
from dataclasses import asdict

from shyft.energy_market.stm import StmTaskClient
from shyft.hydrology import pt_gs_k, stat_scope
from shyft.time_series import TimeSeries, TsVector, UtcPeriod, shyft_url, time

from hydrology.demo.fill_dummy_data import create_initial_content
from hydrology.demo.run_model import create_interpolation_parameter
from hydrology.service.config import HydroServiceConfig
from hydrology.service.drms import DrmsAttrSpec, DrmsSaveStatisticsArgs
from hydrology.task.run import GeoVar, RunModelArgs, RunResult

RUN_TIMEOUT_MS = 300_000  # the run is a blocking call on task; upstream's 1 s client timeout is too short on slow nodes
STEPS = 30 * 24  # 30 days, hourly, on the demo's 2 x 2 cells

cfg = HydroServiceConfig()
dtss_host_port = f"{cfg.dtss.cfg.host}:{cfg.dtss.cfg.port}"

# 1. Seed. Upstream's function skips whatever already exists, so repeated runs are fine.
task_id, _ = create_initial_content(cfg=cfg, model_type=pt_gs_k.PTGSKModel)
task_name = "nea-run"


def model_id(client, name: str) -> int:
    found = [m.id for m in client.get_model_infos(mids=[]) if m.name == name]
    assert found, f"seeded model {name!r} not found"
    return found[0]


parameter_id = model_id(cfg.parameter.client(), f"nea-{pt_gs_k.PTGSKParameter.__name__}")
state_id = model_id(cfg.state.client(), f"nea-{pt_gs_k.PTGSKState.__name__}")

# 2. Run through task. task picks a registered drms, so this hangs if none is registered.
task = StmTaskClient(f"{cfg.task.cfg.host}:{cfg.task.cfg.port}", timeout_ms=RUN_TIMEOUT_MS)
cases_before = {c.id for c in task.read_model(mid=task_id).cases}
case_id = max(cases_before, default=0) + 1  # task allocates max+1; checked below
t0 = time("2010-01-01T00:00:00Z")
stats_url = shyft_url("r", f"hydrology/{task_name}/t{task_id}/c{case_id}/evap.output")
run_args = RunModelArgs(
    rm_type="PT_GS_K",
    t0=int(t0), dt=3600, n=STEPS,
    parameter_id=parameter_id,
    state_id=state_id,
    geo_db="nea_senorge",
    geo_vars=[f"{GeoVar.temperature}:t", f"{GeoVar.precipitation}:p", f"{GeoVar.radiation}:r",
              f"{GeoVar.wind_speed}:ws", f"{GeoVar.rel_hum}:rh"],
    ensembles=[0],
    dtss_container="r",
    save_results=[RunResult(variable="discharge", indexes=[], url_prefix="hydrology/")],
    # Statistics are written by the drms itself, straight to dtss: this is the drms -> dtss path.
    drms_stats=DrmsSaveStatisticsArgs(
        dtss_host_port=dtss_host_port,
        ts_attribute_list=[DrmsAttrSpec(attr_path="actual_evaptranspiration_response.output",
                                        ix_scope=int(stat_scope.catchment), ix=[], ts_url=stats_url)]),
)
run_args.interpolation_parameter = create_interpolation_parameter()
fx_arg = asdict(run_args)
fx_arg["action"] = "run"
print(f"running task {task_id} ({task_name}) for {STEPS} steps", flush=True)
ok = json.loads(task.fx(mid=task_id, fx_arg=json.dumps(fx_arg)) or "false")
assert ok, "task reported that the run failed; see the task and drms container logs"

new_cases = {c.id for c in task.read_model(mid=task_id).cases} - cases_before
assert new_cases == {case_id}, f"expected exactly case {case_id}, got {sorted(new_cases)}"

# 3. Read the results back from dtss.
period = UtcPeriod(t0, t0 + time(3600 * STEPS))
discharge_url = shyft_url("r", f"hydrology/{task_id}_{case_id}_1.discharge")
for what, url in (("discharge, stored by task", discharge_url), ("evaporation, stored by drms", stats_url)):
    ts = cfg.dtss.client().evaluate(TsVector([TimeSeries(url)]), period)[0]
    values = [float(v) for v in ts.values]
    assert len(values) >= STEPS, f"{what}: {len(values)} values at {url}, expected at least {STEPS}"
    assert all(math.isfinite(v) for v in values), f"{what}: non-finite values at {url}"
    print(f"ok    {what}: {len(values)} values, mean {sum(values) / len(values):.4f}  {url}", flush=True)

print(f"ok    model run, case {case_id}")
sys.exit(0)
