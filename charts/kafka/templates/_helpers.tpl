{{/*
======================================================================
kafka-cluster — reusable template helpers
======================================================================
*/}}

{{/*
Chart name (respects nameOverride). Truncated to 63 chars for DNS safety.
*/}}
{{- define "kafka-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name. Respects fullnameOverride, otherwise derives from the
release name and chart name. Truncated to 63 chars for DNS safety.
*/}}
{{- define "kafka-cluster.fullname" -}}
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
The Kafka cluster name — metadata.name of the Kafka CR and the value of the
`strimzi.io/cluster` label on every KafkaNodePool / KafkaTopic / KafkaUser.
Defaults to the fullname (truncated to 40 chars so generated pod names
"<cluster>-<pool>-<id>" stay well under the 63-char limit).
*/}}
{{- define "kafka-cluster.clusterName" -}}
{{- $n := default (include "kafka-cluster.fullname" .) .Values.cluster.name -}}
{{- $n | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{/*
Chart label "name-version" (sanitised for use as a label value).
*/}}
{{- define "kafka-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard Kubernetes recommended labels applied to every object this chart
creates, merged with user-supplied extraLabels (rendered through tpl).
NOTE: does NOT include `strimzi.io/cluster` — templates add that explicitly.
*/}}
{{- define "kafka-cluster.labels" -}}
helm.sh/chart: {{ include "kafka-cluster.chart" . }}
{{ include "kafka-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kafka
{{- with .Values.extraLabels }}
{{ include "kafka-cluster.tplvalues.render" (dict "value" . "context" $) }}
{{- end }}
{{- end -}}

{{/*
Selector labels — the stable subset used to identify this release's objects.
*/}}
{{- define "kafka-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kafka-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Common annotations for the Kafka CR (user-supplied extraAnnotations, tpl-rendered).
*/}}
{{- define "kafka-cluster.annotations" -}}
{{- with .Values.extraAnnotations }}
{{ include "kafka-cluster.tplvalues.render" (dict "value" . "context" $) }}
{{- end }}
{{- end -}}

{{/*
Name of the JMX-exporter metrics ConfigMap.
*/}}
{{- define "kafka-cluster.metricsConfigMapName" -}}
{{- printf "%s-metrics" (include "kafka-cluster.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
------------------------------------------------------------------
General value-rendering helper. Renders an arbitrary value (string / map / list)
through `tpl` so user-supplied values may contain Helm template expressions.

  {{ include "kafka-cluster.tplvalues.render" (dict "value" .Values.x "context" $) }}
------------------------------------------------------------------
*/}}
{{- define "kafka-cluster.tplvalues.render" -}}
{{- if typeIs "string" .value }}
{{- tpl .value .context }}
{{- else }}
{{- tpl (.value | toYaml) .context }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------
Default JMX Prometheus Exporter rules used when cluster.metrics.rules is empty.
A trimmed, production-sane subset of the upstream Strimzi kafka-metrics rules.
------------------------------------------------------------------
*/}}
{{- define "kafka-cluster.defaultMetricsRules" -}}
lowercaseOutputName: true
rules:
  # Broker/topic throughput (bytes/messages per sec), per-topic and aggregate.
  - pattern: kafka.server<type=(.+), name=(.+)PerSec\w*, topic=(.+)><>Count
    name: kafka_server_$1_$2_total
    type: COUNTER
    labels:
      topic: "$3"
  - pattern: kafka.server<type=(.+), name=(.+)PerSec\w*><>Count
    name: kafka_server_$1_$2_total
    type: COUNTER
  # Request latency percentiles / counts, per request type.
  - pattern: kafka.network<type=(.+), name=(.+), request=(.+)><>(\d+)thPercentile
    name: kafka_network_$1_$2
    type: GAUGE
    labels:
      request: "$3"
      quantile: "0.$4"
  - pattern: kafka.network<type=(.+), name=(.+), request=(.+)><>(Count|Value)
    name: kafka_network_$1_$2
    type: GAUGE
    labels:
      request: "$3"
  # Replication health and controller state.
  - pattern: kafka.server<type=ReplicaManager, name=(.+)><>(Value|Count)
    name: kafka_server_replicamanager_$1
    type: GAUGE
  - pattern: kafka.controller<type=KafkaController, name=(.+)><>Value
    name: kafka_controller_kafkacontroller_$1
    type: GAUGE
  # JVM: GC, heap, threads.
  - pattern: java.lang<type=GarbageCollector, name=(.+)><>CollectionCount
    name: jvm_gc_collection_count
    type: COUNTER
    labels:
      gc: "$1"
  - pattern: java.lang<type=GarbageCollector, name=(.+)><>CollectionTime
    name: jvm_gc_collection_time_ms
    type: COUNTER
    labels:
      gc: "$1"
  - pattern: java.lang<type=Memory><HeapMemoryUsage>used
    name: jvm_memory_heap_used_bytes
    type: GAUGE
  - pattern: java.lang<type=Threading><>ThreadCount
    name: jvm_threads_current
    type: GAUGE
{{- end -}}
