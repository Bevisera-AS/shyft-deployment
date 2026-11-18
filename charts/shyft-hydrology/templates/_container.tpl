{{/*
The one container definition: every Shyft service is this container with a different script.
Context: dict
  "root"      $
  "service"   Shyft service name, e.g. "goal_function"; runs /opt/shyft/hydrology/service/<service>.py
  "args"      list of command-line arguments (optional)
  "env"       list of environment variables the workload needs, after SHYFT_SERVICE_BASE_PORT (optional)
  "extraEnv"  list of the user's extra environment variables (optional)
  "resources" resources of this container
  "path"      where those resources are in values, for error messages
  "var"       bool: mount the service databases at /shyft-var
  "data"      bool: mount the input data volume
*/}}
{{- define "shyft.container" -}}
{{- include "shyft.checkResources" (dict "path" .path "resources" .resources) -}}
{{- $name := include "shyft.serviceName" .service -}}
- name: {{ $name }}
  image: {{ include "shyft.image" .root | quote }}
  imagePullPolicy: {{ .root.Values.image.pullPolicy }}
  command:
    - python3
    - /opt/shyft/hydrology/service/{{ .service }}.py
  {{- with .args }}
  args:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  env:
    # Shyft prints registration messages with print(): unbuffered, they reach `kubectl logs` at once.
    - name: PYTHONUNBUFFERED
      value: "1"
    - name: SHYFT_SERVICE_BASE_PORT
      value: {{ .root.Values.basePort | int | quote }}
    {{- with .env }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- with .extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  ports:
    - name: {{ $name }}
      containerPort: {{ include "shyft.port" (dict "root" .root "service" .service) }}
      protocol: TCP
  startupProbe:
    tcpSocket:
      port: {{ $name }}
    periodSeconds: {{ .root.Values.probes.startup.periodSeconds }}
    failureThreshold: {{ .root.Values.probes.startup.failureThreshold }}
  livenessProbe:
    tcpSocket:
      port: {{ $name }}
    periodSeconds: {{ .root.Values.probes.liveness.periodSeconds }}
    failureThreshold: {{ .root.Values.probes.liveness.failureThreshold }}
  readinessProbe:
    tcpSocket:
      port: {{ $name }}
    periodSeconds: {{ .root.Values.probes.readiness.periodSeconds }}
    failureThreshold: {{ .root.Values.probes.readiness.failureThreshold }}
  {{- with .resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  securityContext:
    {{- toYaml .root.Values.securityContext | nindent 4 }}
  volumeMounts:
    - name: tmp
      mountPath: /tmp
    {{- if .var }}
    - name: var
      mountPath: /shyft-var
    {{- end }}
    {{- if .data }}
    - name: data
      mountPath: {{ .root.Values.persistence.data.mountPath }}
      readOnly: {{ .root.Values.persistence.data.readOnly }}
    {{- end }}
{{- end }}
