{{/*
Common labels
*/}}
{{- define "bugsink.labels" -}}
app.kubernetes.io/name: bugsink
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "bugsink.selectorLabels" -}}
app.kubernetes.io/name: bugsink
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "bugsink.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default "bugsink" .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Database URL — picks the right source based on what's enabled.
*/}}
{{- define "bugsink.databaseUrl" -}}
{{- if .Values.database.gcp.enabled -}}
postgres://{{ .Values.database.gcp.user }}:$(DB_PASSWORD)@127.0.0.1:5432/{{ .Values.database.gcp.dbName }}
{{- else if .Values.database.aws.enabled -}}
postgres://{{ .Values.database.aws.user }}:$(DB_PASSWORD)@{{ .Values.database.aws.endpoint }}:{{ .Values.database.aws.port }}/{{ .Values.database.aws.dbName }}
{{- else if .Values.database.local.enabled -}}
postgres://{{ .Values.database.local.user }}:$(DB_PASSWORD)@{{ .Values.database.local.host }}:{{ .Values.database.local.port }}/{{ .Values.database.local.dbName }}
{{- end -}}
{{- end }}
