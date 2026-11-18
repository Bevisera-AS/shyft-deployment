{{/*
One `helm test` pod: the Shyft image running a script from files/ against the core Service.
Context: dict
  "root"     $
  "name"     suffix of the pod name, after "<fullname>-test-"
  "script"   file under files/
  "about"    one line for the rendered manifest
  "weight"   hook weight, as a string; lower runs first (connection, then model run)
  "deadline" seconds after which the pod fails instead of waiting (optional). The model run sets it: with no
             drms registered, task would keep the run waiting forever
*/}}
{{- define "shyft.testPod" -}}
{{- $test := dict "root" .root "component" "test" -}}
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "shyft.fullname" .root }}-test-{{ .name }}
  labels:
    {{- include "shyft.labels" $test | nindent 4 }}
  annotations:
    helm.sh/hook: test
    helm.sh/hook-weight: {{ .weight | quote }}
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  {{- with .deadline }}
  activeDeadlineSeconds: {{ . }}
  {{- end }}
  serviceAccountName: {{ include "shyft.serviceAccountName" .root }}
  automountServiceAccountToken: false
  enableServiceLinks: false
  {{- with .root.Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  securityContext:
    {{- toYaml .root.Values.podSecurityContext | nindent 4 }}
  containers:
    # {{ .about }}
    - name: test
      image: {{ include "shyft.image" .root | quote }}
      imagePullPolicy: {{ .root.Values.image.pullPolicy }}
      command:
        - python3
        - -c
        - {{ .root.Files.Get (printf "files/%s" .script) | toJson }}
      env:
        - name: SHYFT_SERVICE_HOST
          value: {{ include "shyft.fullname" .root }}
        - name: SHYFT_SERVICE_BASE_PORT
          value: {{ .root.Values.shyft.basePort | int | quote }}
        - name: SHYFT_SERVICE_ROOT
          value: /tmp/shyft
      securityContext:
        {{- toYaml .root.Values.securityContext | nindent 8 }}
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
  {{- with .root.Values.tests.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .root.Values.tests.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .root.Values.tests.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
