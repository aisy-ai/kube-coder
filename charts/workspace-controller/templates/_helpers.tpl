{{/*
Common name for every workspace-controller resource. Fixed (not per-user):
this chart is a namespace singleton.
*/}}
{{- define "wc.name" -}}
workspace-controller
{{- end -}}

{{- define "wc.labels" -}}
app: workspace-controller
{{- end -}}

{{/* Pod scheduling (nodeSelector/tolerations) onto a dedicated node pool.
Both empty by default -> renders nothing (byte-identical to upstream). */}}
{{- define "wc.scheduling" -}}
{{- if .Values.controller.scheduling.nodeSelector }}
nodeSelector:
{{ toYaml .Values.controller.scheduling.nodeSelector | indent 2 }}
{{- end }}
{{- if .Values.controller.scheduling.tolerations }}
tolerations:
{{ toYaml .Values.controller.scheduling.tolerations | indent 2 }}
{{- end }}
{{- end -}}
