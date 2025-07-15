{{/*
Expand the name of the chart.
*/}}
{{- define "kaia-orderbook-dex-admin.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "kaia-orderbook-dex-admin.fullname" -}}
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
{{- define "kaia-orderbook-dex-admin.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kaia-orderbook-dex-admin.labels" -}}
helm.sh/chart: {{ include "kaia-orderbook-dex-admin.chart" . }}
{{ include "kaia-orderbook-dex-admin.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kaia-orderbook-dex-admin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kaia-orderbook-dex-admin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Pod labels
*/}}
{{- define "kaia-orderbook-dex-admin.podLabels" -}}
{{ include "kaia-orderbook-dex-admin.selectorLabels" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "kaia-orderbook-dex-admin.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kaia-orderbook-dex-admin.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "kaia-orderbook-dex-admin.image" -}}
{{- $registryName := .Values.image.registry | default .Values.global.imageRegistry -}}
{{- $repositoryName := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}