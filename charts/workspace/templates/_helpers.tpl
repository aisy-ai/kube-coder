{{/*
DECIDED NOT TO IMPLEMENT (kept for context):

We considered stripping client-supplied identity headers
(X-Forwarded-User / -Email / -Preferred-Username / -Groups) at each
workspace-facing Ingress as defense-in-depth, in case some future
in-pod code starts trusting them. The natural mechanism on
nginx-ingress is `nginx.ingress.kubernetes.io/configuration-snippet`,
but the cluster's ingress controller runs with `--allow-snippet-
annotations=false` (CVE-2021-25742 hardening, cluster-wide) and its
admission webhook rejects snippets.

Re-enabling snippets would weaken posture for 20+ unrelated tenants on
this shared DOKS cluster — not worth it for a header-strip that
nothing currently trusts. If a future in-pod handler begins
authorizing off these headers, revisit by adding a single shared
ConfigMap in `ingress-nginx` and pointing each workspace ingress at it
via the `proxy-set-headers` annotation (which is *not* a snippet and
is allowed).
*/}}

{{/* oauth2 auth_request URL for the nginx auth-url annotation. "external"
(default) is byte-identical to upstream; "internal" targets the in-cluster
oauth2-proxy Service directly (see ingress.oauth2AuthMode in values.yaml). */}}
{{- define "workspace.oauth2AuthUrl" -}}
{{- if eq .Values.ingress.oauth2AuthMode "internal" -}}
http://oauth2-proxy-{{ .Values.user.name }}.{{ .Values.namespace }}.svc.cluster.local:4180/oauth2/auth
{{- else -}}
https://$host/oauth2/auth
{{- end -}}
{{- end -}}

{{/* Extra annotations merged into every Ingress this chart renders. Empty by
default -> renders nothing (byte-identical to upstream). Caller nindents this
to the annotations block's indent level (nindent replaces every internal
newline too, so a multi-key map comes out correctly indented as a whole). */}}
{{- define "workspace.ingressExtraAnnotations" -}}
{{- with .Values.ingress.extraAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Pod scheduling (nodeSelector/tolerations) onto a dedicated node pool.
Both empty by default -> renders nothing (byte-identical to upstream). */}}
{{- define "workspace.scheduling" -}}
{{- if .Values.scheduling.nodeSelector }}
nodeSelector:
{{ toYaml .Values.scheduling.nodeSelector | indent 2 }}
{{- end }}
{{- if .Values.scheduling.tolerations }}
tolerations:
{{ toYaml .Values.scheduling.tolerations | indent 2 }}
{{- end }}
{{- end -}}

{{/* ---- ResourceQuota derivation (#103) --------------------------------------
Size the per-namespace ResourceQuota from the workspace pod's ACTUAL resource
requests/limits, so a heavier workspace (a bigger ide, or the privileged dind
build sidecar) can't silently exhaust the quota and starve its own oauth2-proxy
pair or cert-manager ACME solver — the failure that took a workspace's ingress
+ TLS down mid-migration. Any quota.{requests,limits}{Cpu,Memory} set explicitly
in values.yaml still wins; otherwise the value is derived as the pod sum across
(ide + dind) plus a fixed overhead covering the oauth2-proxy pair, one in-flight
build Job, the solver, and margin. */}}

{{/* Memory quantity (Gi/Mi/Ki/G/M/plain bytes) -> integer Mi. */}}
{{- define "workspace.memToMi" -}}
{{- $q := . | toString -}}
{{- if hasSuffix "Gi" $q -}}{{- mulf (float64 (trimSuffix "Gi" $q)) 1024 | int -}}
{{- else if hasSuffix "Mi" $q -}}{{- float64 (trimSuffix "Mi" $q) | int -}}
{{- else if hasSuffix "Ki" $q -}}{{- divf (float64 (trimSuffix "Ki" $q)) 1024 | int -}}
{{- else if hasSuffix "G" $q -}}{{- divf (mulf (float64 (trimSuffix "G" $q)) 1000000000) 1048576 | int -}}
{{- else if hasSuffix "M" $q -}}{{- divf (mulf (float64 (trimSuffix "M" $q)) 1000000) 1048576 | int -}}
{{- else -}}{{- divf (float64 $q) 1048576 | int -}}
{{- end -}}
{{- end -}}

{{/* CPU quantity (cores or millicores) -> integer millicores. */}}
{{- define "workspace.cpuToMilli" -}}
{{- $q := . | toString -}}
{{- if hasSuffix "m" $q -}}{{- float64 (trimSuffix "m" $q) | int -}}
{{- else -}}{{- mulf (float64 $q) 1000 | int -}}
{{- end -}}
{{- end -}}

{{/* dind sidecar defaults, mirrored from deployment.yaml's dindResources default. */}}
{{- define "workspace.dindDefault" -}}
{{- $d := dict "limits" (dict "cpu" "2" "memory" "4Gi") "requests" (dict "cpu" "100m" "memory" "256Mi") -}}
{{- index $d .kind .dim -}}
{{- end -}}

{{/* Sum one (kind, dim) across the pod's containers (ide + dind when
build.mode=buildkit). Returns Mi for memory, millicores for cpu.
Call: (dict "ctx" $ "kind" "limits" "dim" "memory"). */}}
{{- define "workspace.podSum" -}}
{{- $ctx := .ctx -}}{{- $kind := .kind -}}{{- $dim := .dim -}}
{{- $conv := ternary "workspace.memToMi" "workspace.cpuToMilli" (eq $dim "memory") -}}
{{- $ide := include $conv (index $ctx.Values.resources $kind $dim) | int -}}
{{- $dind := 0 -}}
{{- if eq $ctx.Values.build.mode "buildkit" -}}
{{- $drk := index ($ctx.Values.build.dindResources | default dict) $kind | default dict -}}
{{- $dindVal := (index $drk $dim) | default (include "workspace.dindDefault" (dict "kind" $kind "dim" $dim)) -}}
{{- $dind = include $conv $dindVal | int -}}
{{- end -}}
{{- add $ide $dind -}}
{{- end -}}

{{- define "workspace.quotaLimitsMemory" -}}
{{- if .Values.quota.limitsMemory }}{{ .Values.quota.limitsMemory }}
{{- else }}{{ printf "%dMi" (add (include "workspace.podSum" (dict "ctx" . "kind" "limits" "dim" "memory") | int) (.Values.quota.overheadMemoryMi | default 4096 | int)) }}{{- end -}}
{{- end -}}

{{- define "workspace.quotaLimitsCpu" -}}
{{- if .Values.quota.limitsCpu }}{{ .Values.quota.limitsCpu }}
{{- else }}{{ printf "%dm" (add (include "workspace.podSum" (dict "ctx" . "kind" "limits" "dim" "cpu") | int) (.Values.quota.overheadCpuMilli | default 2000 | int)) }}{{- end -}}
{{- end -}}

{{- define "workspace.quotaRequestsMemory" -}}
{{- if .Values.quota.requestsMemory }}{{ .Values.quota.requestsMemory }}
{{- else }}{{ printf "%dMi" (add (include "workspace.podSum" (dict "ctx" . "kind" "requests" "dim" "memory") | int) (.Values.quota.overheadReqMemoryMi | default 1024 | int)) }}{{- end -}}
{{- end -}}

{{- define "workspace.quotaRequestsCpu" -}}
{{- if .Values.quota.requestsCpu }}{{ .Values.quota.requestsCpu }}
{{- else }}{{ printf "%dm" (add (include "workspace.podSum" (dict "ctx" . "kind" "requests" "dim" "cpu") | int) (.Values.quota.overheadReqCpuMilli | default 500 | int)) }}{{- end -}}
{{- end -}}
