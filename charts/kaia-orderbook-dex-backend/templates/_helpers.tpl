{{/*
Expand the name of the chart.
*/}}
{{- define "kaia-orderbook-dex-backend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "kaia-orderbook-dex-backend.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kaia-orderbook-dex-backend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kaia-orderbook-dex-backend.labels" -}}
helm.sh/chart: {{ include "kaia-orderbook-dex-backend.chart" . }}
{{ include "kaia-orderbook-dex-backend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kaia-orderbook-dex-backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kaia-orderbook-dex-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
API Service labels
*/}}
{{- define "kaia-orderbook-dex-backend.api.labels" -}}
{{ include "kaia-orderbook-dex-backend.labels" . }}
app.kubernetes.io/component: api
{{- end }}

{{/*
API Service selector labels
*/}}
{{- define "kaia-orderbook-dex-backend.api.selectorLabels" -}}
{{ include "kaia-orderbook-dex-backend.selectorLabels" . }}
app.kubernetes.io/component: api
{{- end }}

{{/*
Event Service labels
*/}}
{{- define "kaia-orderbook-dex-backend.event.labels" -}}
{{ include "kaia-orderbook-dex-backend.labels" . }}
app.kubernetes.io/component: event
{{- end }}

{{/*
Event Service selector labels
*/}}
{{- define "kaia-orderbook-dex-backend.event.selectorLabels" -}}
{{ include "kaia-orderbook-dex-backend.selectorLabels" . }}
app.kubernetes.io/component: event
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "kaia-orderbook-dex-backend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kaia-orderbook-dex-backend.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "kaia-orderbook-dex-backend.api.image" -}}
{{- $registryName := .Values.api.image.registry | default .Values.global.imageRegistry -}}
{{- $repositoryName := .Values.api.image.repository -}}
{{- $tag := .Values.api.image.tag | default .Chart.AppVersion -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper image name for event service
*/}}
{{- define "kaia-orderbook-dex-backend.event.image" -}}
{{- $registryName := .Values.event.image.registry | default .Values.global.imageRegistry -}}
{{- $repositoryName := .Values.event.image.repository -}}
{{- $tag := .Values.event.image.tag | default .Chart.AppVersion -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}