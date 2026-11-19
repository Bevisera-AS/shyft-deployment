{{/*
The one place that knows Shyft's ports. Upstream (examples/hydrology/service/config.py) hard-codes each service's
relative port: a service listens on basePort + 2·rel. basePort + 2·rel + 1 is reserved for a web API that these
services do not start.
*/}}
{{- define "shyft.relativePorts" -}}
task: 0
rmd: 1
parameter: 2
state: 3
drms: 4
dtss: 5
dstm: 6
stm: 7
goal_function: 8
{{- end }}

{{/*
The services of the core pod, in container order.
*/}}
{{- define "shyft.coreServices" -}}
- task
- rmd
- parameter
- state
- dtss
- dstm
- stm
- goal_function
{{- end }}

{{/*
Port of one service.
Context: dict "root" $ "service" "dtss"
*/}}
{{- define "shyft.port" -}}
{{- $rel := get (include "shyft.relativePorts" . | fromYaml) .service -}}
{{- add (int .root.Values.basePort) (mul 2 (int $rel)) -}}
{{- end }}

{{/*
Kubernetes name of one service (container and port names cannot contain "_").
Context: the service name
*/}}
{{- define "shyft.serviceName" -}}
{{- . | replace "_" "-" -}}
{{- end }}
