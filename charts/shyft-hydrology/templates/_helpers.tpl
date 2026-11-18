{{/*
Chart name, overridable.
*/}}
{{- define "shyft.name" -}}
{{- if .Values.nameOverride -}}
{{- .Values.nameOverride | trunc 40 | trimSuffix "-" -}}
{{- else -}}
{{- .Chart.Name | trunc 40 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
Prefix of every resource name. 40 characters at most: the longest suffix is "-test-connection", and a StatefulSet
name plus its revision hash must fit in a 63-character label.
*/}}
{{- define "shyft.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 40 | trimSuffix "-" -}}
{{- else if contains (include "shyft.name" .) .Release.Name -}}
{{- .Release.Name | trunc 40 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "shyft.name" .) | trunc 40 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
Selector labels of one component. They are immutable on the StatefulSet and the Deployment: do not add to them.
Context: dict "root" $ "component" "core"|"drms"|"test"
*/}}
{{- define "shyft.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shyft.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Labels of every resource of one component.
Context: dict "root" $ "component" "core"|"drms"|"test"
*/}}
{{- define "shyft.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "shyft.selectorLabels" . }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: shyft
{{- end }}

{{/*
ServiceAccount used by every pod.
*/}}
{{- define "shyft.serviceAccountName" -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else if .Values.serviceAccount.create -}}
{{- include "shyft.fullname" . -}}
{{- else -}}
default
{{- end -}}
{{- end }}

{{/*
The Shyft image, by tag or by tag and digest.
*/}}
{{- define "shyft.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.digest -}}
{{- printf "%s:%s@%s" .Values.image.repository $tag .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
{{- end }}

{{/*
Why the Service does not ask for an internal load balancer, or nothing when it does. Shyft's protocol has no
authentication, so any other LoadBalancer is refused.
- service.cloud names the cloud, and one of that cloud's own internal annotations must be present: another
  cloud's annotation does nothing there (on AKS the load balancer would be public).
- Every known annotation that is present, for any cloud, must say "internal": on AWS
  `aws-load-balancer-scheme: internet-facing` wins over the older `aws-load-balancer-internal`.
The chart cannot see the cloud it runs in: NOTES.txt says how to check the address.
*/}}
{{- define "shyft.internalAnnotations" -}}
aws:
  service.beta.kubernetes.io/aws-load-balancer-scheme: internal
  service.beta.kubernetes.io/aws-load-balancer-internal: "true"
azure:
  service.beta.kubernetes.io/azure-load-balancer-internal: "true"
gke:
  networking.gke.io/load-balancer-type: Internal
{{- end }}

{{- define "shyft.loadBalancerProblem" -}}
{{- $known := include "shyft.internalAnnotations" . | fromYaml -}}
{{- $annotations := .Values.service.annotations -}}
{{- $cloud := .Values.service.cloud -}}
{{- $public := list -}}
{{- range $c, $markers := $known -}}
{{- range $key, $want := $markers -}}
{{- if and (hasKey $annotations $key) (ne (get $annotations $key | toString) $want) -}}
{{- $public = append $public (printf "%s=%s" $key (get $annotations $key | toString)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $marked := false -}}
{{- $hints := list -}}
{{- if hasKey $known $cloud -}}
{{- range $key, $want := get $known $cloud -}}
{{- $hints = append $hints (printf "%s=%s" $key $want) -}}
{{- if eq (get $annotations $key | toString) $want -}}
{{- $marked = true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if $public -}}
service.type=LoadBalancer with {{ join ", " $public }}: that asks for a public load balancer, or contradicts another annotation that asks for an internal one.
{{- else if not (hasKey $known $cloud) -}}
service.type=LoadBalancer needs service.cloud (aws, azure or gke): only that cloud's own annotation makes its load balancer internal, and another cloud's annotation does nothing there.
{{- else if not $marked -}}
service.cloud={{ $cloud }} needs one of these service.annotations, to make the load balancer internal: {{ join ", " $hints }}.
{{- end -}}
{{- end }}

{{/*
Bytes in a Kubernetes memory quantity ("512Mi", "2Gi", "1G", "1048576"), or nothing for a form it does not
know (exponents, milli), so that the check below then stays quiet instead of guessing.
*/}}
{{- define "shyft.bytes" -}}
{{- $units := dict "" 1.0 "k" 1e3 "M" 1e6 "G" 1e9 "T" 1e12 "P" 1e15 "Ki" 1024.0 "Mi" 1048576.0 "Gi" 1073741824.0 "Ti" 1099511627776.0 "Pi" 1125899906842624.0 -}}
{{- $q := toString . -}}
{{- $n := regexFind "^[0-9]+(\\.[0-9]+)?" $q -}}
{{- $unit := trimPrefix $n $q -}}
{{- if and $n (hasKey $units $unit) -}}
{{- mulf (float64 $n) (get $units $unit) -}}
{{- end -}}
{{- end }}

{{/*
Fail when a container's memory request is above its memory limit. Helm merges the user's resources into the
defaults, so raising only a request keeps the default limit, and Kubernetes would refuse the pod at install
time, after `helm template` and kubeconform had passed it.
Context: dict "path" (the values path, for the message) "resources"
*/}}
{{- define "shyft.checkResources" -}}
{{- with .resources -}}
{{- $request := dig "requests" "memory" "" . -}}
{{- $limit := dig "limits" "memory" "" . -}}
{{- if and $request $limit -}}
{{- $r := include "shyft.bytes" $request -}}
{{- $l := include "shyft.bytes" $limit -}}
{{- if and $r $l (gt (float64 $r) (float64 $l)) -}}
{{- fail (printf "%s: the memory request %v is above the memory limit %v, and Kubernetes refuses that. Set %s.limits.memory too: the chart has a default limit." $.path $request $limit $.path) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
