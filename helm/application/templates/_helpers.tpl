{{- define "ms.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "ms.dbSecretName" -}}
{{ default "db-credentials" .Values.db.existingSecret }}
{{- end -}}

{{- define "ms.datasourceUrl" -}}
jdbc:postgresql://{{ .Values.db.host }}:{{ .Values.db.port }}/{{ .Values.db.name }}
{{- end -}}
