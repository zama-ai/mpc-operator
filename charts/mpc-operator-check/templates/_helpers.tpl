{{/*
Expand the name of the chart.
*/}}
{{- define "mpc-operator-check.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mpc-operator-check.fullname" -}}
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
{{- define "mpc-operator-check.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mpc-operator-check.labels" -}}
helm.sh/chart: {{ include "mpc-operator-check.chart" . }}
{{ include "mpc-operator-check.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mpc-operator-check.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mpc-operator-check.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Job name unique per release and revision, so a check can be rerun right away while the Jobs of
the previous run are kept until ttlSecondsAfterFinished. The prefix is truncated (not the component) to keep names
distinct and Indexed Job pod hostnames under 63 chars.
Usage: include "mpc-operator-check.jobName" (dict "context" . "component" "kms-core")
*/}}
{{- define "mpc-operator-check.jobName" -}}
{{- $prefix := include "mpc-operator-check.fullname" .context | trunc 34 | trimSuffix "-" }}
{{- printf "%s-%s-%d" $prefix .component (int .context.Release.Revision) }}
{{- end }}

{{/*
Check pod labels, including the release revision to select the logs of a given run
*/}}
{{- define "mpc-operator-check.podLabels" -}}
app: mpc-operator-check
{{ include "mpc-operator-check.selectorLabels" . }}
mpc-operator-check/revision: {{ .Release.Revision | quote }}
{{- end }}
