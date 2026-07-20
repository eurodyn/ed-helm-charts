{{/*
======================================================================
milvus-cluster — reusable template helpers
======================================================================
*/}}

{{/*
Chart name (respects nameOverride). Truncated to 63 chars for DNS safety.
*/}}
{{- define "milvus-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name. Respects fullnameOverride, otherwise derives from
the release name and chart name. Truncated to 63 chars for DNS safety.
This value is also used as the metadata.name of the Milvus custom resource,
so keep it short and stable — renaming it after install creates a NEW Milvus.
*/}}
{{- define "milvus-cluster.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart label "name-version" (sanitised for use as a label value).
*/}}
{{- define "milvus-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The name of the Milvus custom resource. Equal to the fullname.
*/}}
{{- define "milvus-cluster.milvusName" -}}
{{- include "milvus-cluster.fullname" . -}}
{{- end -}}

{{/*
Standard Kubernetes recommended labels applied to every object this chart
creates, merged with user-supplied extraLabels (rendered through tpl).
*/}}
{{- define "milvus-cluster.labels" -}}
helm.sh/chart: {{ include "milvus-cluster.chart" . }}
{{ include "milvus-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: milvus
{{- with .Values.extraLabels }}
{{ include "milvus-cluster.tplvalues.render" (dict "value" . "context" $) }}
{{- end }}
{{- end -}}

{{/*
Selector labels — the stable subset used to identify this release's objects.
*/}}
{{- define "milvus-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "milvus-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Common annotations (user-supplied extraAnnotations, rendered through tpl).
*/}}
{{- define "milvus-cluster.annotations" -}}
{{- with .Values.extraAnnotations }}
{{ include "milvus-cluster.tplvalues.render" (dict "value" . "context" $) }}
{{- end }}
{{- end -}}

{{/*
ServiceAccount name to use. If serviceAccount.create is true, defaults to the
fullname; otherwise uses the provided name (defaulting to "default").
*/}}
{{- define "milvus-cluster.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "milvus-cluster.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------
Secret name helpers.
Each returns the existingSecret when one is provided, otherwise the
chart-managed name used when *.credentials.create is true.
------------------------------------------------------------------
*/}}

{{/* NOTE: Secret *names* below are rendered through `tpl` so users may template
     them (e.g. existingSecret: "{{`{{ .Release.Name }}`}}-kafka"). Only the NAME
     is templated — credential VALUES are never passed through tpl. */}}

{{/* Ozone / S3 object-storage credential Secret (accesskey/secretkey). */}}
{{- define "milvus-cluster.storageSecretName" -}}
{{- if .Values.externalStorage.credentials.create -}}
{{- printf "%s-storage-credentials" (include "milvus-cluster.fullname" .) -}}
{{- else -}}
{{- tpl (required "externalStorage.existingSecret is required when externalStorage.credentials.create is false" .Values.externalStorage.existingSecret) . -}}
{{- end -}}
{{- end -}}

{{/* Kafka SASL credential Secret. */}}
{{- define "milvus-cluster.kafkaSecretName" -}}
{{- if .Values.externalKafka.credentials.create -}}
{{- printf "%s-kafka-credentials" (include "milvus-cluster.fullname" .) -}}
{{- else -}}
{{- tpl (.Values.externalKafka.existingSecret | default "") . -}}
{{- end -}}
{{- end -}}

{{/* etcd authentication credential Secret. */}}
{{- define "milvus-cluster.etcdSecretName" -}}
{{- if .Values.externalEtcd.authentication.createSecret -}}
{{- printf "%s-etcd-credentials" (include "milvus-cluster.fullname" .) -}}
{{- else -}}
{{- tpl (.Values.externalEtcd.existingSecret | default "") . -}}
{{- end -}}
{{- end -}}

{{/* TLS Secret names (private CA / client certs) — user-provided existingSecret
     for each dependency, rendered through tpl (name only). */}}
{{- define "milvus-cluster.storageTLSSecretName" -}}
{{- tpl (.Values.externalStorage.tls.existingSecret | default "") . -}}
{{- end -}}

{{- define "milvus-cluster.kafkaTLSSecretName" -}}
{{- tpl (.Values.externalKafka.tls.existingSecret | default "") . -}}
{{- end -}}

{{- define "milvus-cluster.etcdTLSSecretName" -}}
{{- tpl (.Values.externalEtcd.tls.existingSecret | default "") . -}}
{{- end -}}

{{/*
------------------------------------------------------------------
Stable, documented mount paths for TLS material. Referenced by both the
Milvus custom resource (spec.config.*.ssl.*) and the mounted volumes.
------------------------------------------------------------------
*/}}
{{- define "milvus-cluster.storageTLSMountPath" -}}/etc/milvus/certs/storage{{- end -}}
{{- define "milvus-cluster.kafkaTLSMountPath" -}}/etc/milvus/certs/kafka{{- end -}}
{{- define "milvus-cluster.etcdTLSMountPath" -}}/etc/milvus/certs/etcd{{- end -}}

{{/*
------------------------------------------------------------------
General value-rendering helper.
Renders an arbitrary value (string / map / list) through `tpl` so that
user-supplied values may contain Helm template expressions.

Usage:
  {{ include "milvus-cluster.tplvalues.render" (dict "value" .Values.something "context" $) }}

Do NOT use this on credential/Secret values — it must not double-render
passwords or access keys.
------------------------------------------------------------------
*/}}
{{- define "milvus-cluster.tplvalues.render" -}}
{{- if typeIs "string" .value }}
{{- tpl .value .context }}
{{- else }}
{{- tpl (.value | toYaml) .context }}
{{- end }}
{{- end -}}
