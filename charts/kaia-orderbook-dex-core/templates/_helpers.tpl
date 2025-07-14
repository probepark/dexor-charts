{{/*
Expand the name of the chart.
*/}}
{{- define "kaia-orderbook-dex-core.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "kaia-orderbook-dex-core.fullname" -}}
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
{{- define "kaia-orderbook-dex-core.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kaia-orderbook-dex-core.labels" -}}
helm.sh/chart: {{ include "kaia-orderbook-dex-core.chart" . }}
{{ include "kaia-orderbook-dex-core.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kaia-orderbook-dex-core.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kaia-orderbook-dex-core.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Nitro Node labels
*/}}
{{- define "kaia-orderbook-dex-core.nitroNode.labels" -}}
{{ include "kaia-orderbook-dex-core.labels" . }}
app.kubernetes.io/component: nitro-node
{{- end }}

{{/*
Nitro Node selector labels
*/}}
{{- define "kaia-orderbook-dex-core.nitroNode.selectorLabels" -}}
{{ include "kaia-orderbook-dex-core.selectorLabels" . }}
app.kubernetes.io/component: nitro-node
{{- end }}

{{/*
Validator labels
*/}}
{{- define "kaia-orderbook-dex-core.validator.labels" -}}
{{ include "kaia-orderbook-dex-core.labels" . }}
app.kubernetes.io/component: validator
{{- end }}

{{/*
Validator selector labels
*/}}
{{- define "kaia-orderbook-dex-core.validator.selectorLabels" -}}
{{ include "kaia-orderbook-dex-core.selectorLabels" . }}
app.kubernetes.io/component: validator
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "kaia-orderbook-dex-core.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kaia-orderbook-dex-core.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name for nitro node
*/}}
{{- define "kaia-orderbook-dex-core.nitroNode.image" -}}
{{- $registryName := .Values.nitroNode.image.registry | default .Values.global.imageRegistry -}}
{{- $repositoryName := .Values.nitroNode.image.repository -}}
{{- $tag := .Values.nitroNode.image.tag | default .Chart.AppVersion -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper image name for validator
*/}}
{{- define "kaia-orderbook-dex-core.validator.image" -}}
{{- $registryName := .Values.validator.image.registry | default .Values.global.imageRegistry -}}
{{- $repositoryName := .Values.validator.image.repository -}}
{{- $tag := .Values.validator.image.tag | default .Chart.AppVersion -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the storage class
*/}}
{{- define "kaia-orderbook-dex-core.storageClass" -}}
{{- if .Values.global.storageClass }}
{{- .Values.global.storageClass }}
{{- else if .Values.nitroNode.persistence.storageClass }}
{{- .Values.nitroNode.persistence.storageClass }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}
