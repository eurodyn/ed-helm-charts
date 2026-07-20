{{/*
Expand the name of the chart.
*/}}
{{- define "helm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "helm.fullname" -}}
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
{{- define "helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "helm.labels" -}}
helm.sh/chart: {{ include "helm.chart" . }}
{{ include "helm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "helm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "helm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service headless name
*/}}
{{- define "helm.headlessServiceName" -}}
{{ include "helm.fullname" . }}-headless
{{- end }}

{{/*
*/}}

{{/*
Annotations template
*/}}
{{- define "helm.podAnnotations" -}}
{{- if .Values.podAnnotations }}
{{ toYaml .Values.podAnnotations | nindent 4 }}
{{- end }}
app.kubernetes.io/serviceName: {{ include "helm.headlessServiceName" . }}
{{- end }}

{{/*
Image registry/repository
*/}}
{{- define "helm.image" -}}
{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{/*
====================================================================================================
Client Service Name/Port
*/}}

{{- define "helm.clientName" -}}
etcd-client
{{- end }}

{{- define "helm.clientPort" -}}
2379
{{- end }}


{{/*
Server Service Name/Port
*/}}

{{- define "helm.serverName" -}}
etcd-server
{{- end }}

{{- define "helm.serverPort" -}}
2380
{{- end }}

{{/*
Metrics Service Name/Port
*/}}

{{- define "helm.metricsName" -}}
etcd-metrics
{{- end }}

{{- define "helm.metricsPort" -}}
8080
{{- end }}


{{- define "helm.servicePorts" -}}
- name: {{ include "helm.clientName" . }}
  port: {{ include "helm.clientPort" . }}
- name: {{ include "helm.serverName" . }}
  port: {{ include "helm.serverPort" . }}
- name: {{ include "helm.metricsName" . }}
  port: {{ include "helm.metricsPort" . }}
{{- end}}

{{/*
Container ports for the etcd container spec. Unlike Service ports, container
ports use the "containerPort" field rather than "port".
*/}}
{{- define "helm.containerPorts" -}}
- name: {{ include "helm.clientName" . }}
  containerPort: {{ include "helm.clientPort" . }}
- name: {{ include "helm.serverName" . }}
  containerPort: {{ include "helm.serverPort" . }}
- name: {{ include "helm.metricsName" . }}
  containerPort: {{ include "helm.metricsPort" . }}
{{- end}}

{{/*
Build the static etcd initial cluster list.

Example output:
release-etcd-0=$(URI_SCHEME)://release-etcd-0.release-etcd:2380,
release-etcd-1=$(URI_SCHEME)://release-etcd-1.release-etcd:2380,
release-etcd-2=$(URI_SCHEME)://release-etcd-2.release-etcd:2380
*/}}
{{- define "helm.etcdInitialCluster" -}}
{{- $replicas := int (default 3 .Values.replicaCount) -}}
{{- $name := include "helm.fullname" . -}}
{{- $svc := include "helm.headlessServiceName" . -}}
{{- $peerPort := include "helm.serverPort" . -}}

{{- if lt $replicas 1 -}}
  {{- fail "replicaCount must be at least 1" -}}
{{- end -}}

{{- range $ordinal := until $replicas -}}
  {{- if gt $ordinal 0 }},{{ end -}}
  {{- printf "%s-%d=$(URI_SCHEME)://%s-%d.%s:%s" $name $ordinal $name $ordinal $svc $peerPort -}}
{{- end -}}
{{- end }}

{{/*
====================================================================================================
TLS
*/}}

{{/*
Name of the Secret holding the client-facing certificate (tls.crt/tls.key/ca.crt).
When cert-manager is enabled the chart issues this Secret itself; otherwise it must
already exist (tls.client.existingSecret).
*/}}
{{- define "helm.clientTlsSecretName" -}}
{{- if .Values.tls.certManager.enabled -}}
{{ include "helm.fullname" . }}-client-tls
{{- else -}}
{{ required "tls.client.existingSecret is required when tls.enabled is true and tls.certManager.enabled is false" .Values.tls.client.existingSecret }}
{{- end -}}
{{- end }}

{{/*
Name of the Secret holding the peer certificate (tls.crt/tls.key/ca.crt).
When cert-manager is enabled the chart issues this Secret itself; otherwise it must
already exist (tls.peer.existingSecret).
*/}}
{{- define "helm.peerTlsSecretName" -}}
{{- if .Values.tls.certManager.enabled -}}
{{ include "helm.fullname" . }}-peer-tls
{{- else -}}
{{ required "tls.peer.existingSecret is required when tls.enabled is true and tls.certManager.enabled is false" .Values.tls.peer.existingSecret }}
{{- end -}}
{{- end }}

{{/*
cert-manager issuerRef used for the client/peer Certificate resources. Falls back to
the chart-managed self-signed CA issuer when tls.certManager.issuerRef.name is unset.
*/}}
{{- define "helm.certManagerIssuerRef" -}}
{{- if .Values.tls.certManager.issuerRef.name -}}
name: {{ .Values.tls.certManager.issuerRef.name }}
kind: {{ .Values.tls.certManager.issuerRef.kind | default "ClusterIssuer" }}
group: {{ .Values.tls.certManager.issuerRef.group | default "cert-manager.io" }}
{{- else -}}
name: {{ include "helm.fullname" . }}-ca-issuer
kind: Issuer
group: cert-manager.io
{{- end -}}
{{- end }}

{{/*
DNS SANs shared by the client and peer certificates: the headless service in its
short/namespaced/FQDN forms, plus wildcards that cover every pod's stable
per-ordinal name both as the short form used for peer/advertise URLs
(<fullname>-<ordinal>.<headless-service>) and as the FQDN
(<fullname>-<ordinal>.<headless-service>.<namespace>.svc.<clusterDomain>).
*/}}
{{- define "helm.tlsDnsNames" -}}
{{- $fullname := include "helm.fullname" . -}}
{{- $svc := include "helm.headlessServiceName" . -}}
{{- $ns := .Release.Namespace -}}
{{- $domain := .Values.clusterDomain | default "cluster.local" -}}
- {{ $fullname }}
- {{ $svc }}
- {{ $svc }}.{{ $ns }}
- {{ $svc }}.{{ $ns }}.svc.{{ $domain }}
- "*.{{ $svc }}"
- "*.{{ $svc }}.{{ $ns }}.svc.{{ $domain }}"
- localhost
{{- end }}