{{/*
======================================================================
kafka-cluster — input validation
Included once from templates/kafka.yaml. Fails the render with a clear
message when the values would produce an invalid or unsafe deployment.
======================================================================
*/}}
{{- define "kafka-cluster.validate" -}}
{{- $ := . -}}

{{/* ---------------- Controller node pool ---------------- */}}
{{- $cr := .Values.nodePools.controller.replicas -}}
{{- if not (or (kindIs "float64" $cr) (kindIs "int" $cr) (kindIs "int64" $cr)) -}}
{{- fail "nodePools.controller.replicas must be an integer." -}}
{{- end -}}
{{- if lt (int $cr) 1 -}}
{{- fail "nodePools.controller.replicas must be at least 1." -}}
{{- end -}}
{{- if eq (mod (int $cr) 2) 0 -}}
{{- fail (printf "nodePools.controller.replicas must be ODD for a stable KRaft quorum (got %d). Use 1, 3 or 5." (int $cr)) -}}
{{- end -}}

{{/* ---------------- Broker node pool ---------------- */}}
{{- $br := .Values.nodePools.broker.replicas -}}
{{- if not (or (kindIs "float64" $br) (kindIs "int" $br) (kindIs "int64" $br)) -}}
{{- fail "nodePools.broker.replicas must be an integer." -}}
{{- end -}}
{{- if lt (int $br) 1 -}}
{{- fail "nodePools.broker.replicas must be at least 1." -}}
{{- end -}}
{{- if ne .Values.nodePools.broker.storage.type "jbod" -}}
{{- fail "nodePools.broker.storage.type must be \"jbod\" for the broker pool (this chart demonstrates multi-volume brokers)." -}}
{{- end -}}

{{/* ---------------- Forbidden broker config keys ---------------- */}}
{{- $forbidden := list "controller." "process.roles" "node.id" "metadata.log.dir" "zookeeper." "broker.id" "listeners" "advertised." -}}
{{- range $k, $v := .Values.cluster.config -}}
{{- range $p := $forbidden -}}
{{- if hasPrefix $p $k -}}
{{- fail (printf "cluster.config.%q is managed by Strimzi and must not be set (matched forbidden prefix %q)." $k $p) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* ---------------- Listeners ---------------- */}}
{{- if or (not .Values.cluster.listeners) (eq (len .Values.cluster.listeners) 0) -}}
{{- fail "cluster.listeners must contain at least one listener." -}}
{{- end -}}

{{/* ---------------- Topics ---------------- */}}
{{- $seenTopics := dict -}}
{{- range $i, $t := .Values.topics -}}
{{- if eq (trim (default "" $t.name)) "" -}}
{{- fail (printf "topics[%d].name is required." $i) -}}
{{- end -}}
{{- if hasKey $seenTopics $t.name -}}
{{- fail (printf "topics[%d]: duplicate topic name %q." $i $t.name) -}}
{{- end -}}
{{- $_ := set $seenTopics $t.name true -}}
{{- if lt (int $t.partitions) 1 -}}
{{- fail (printf "topics[%d] (%s): partitions must be at least 1." $i $t.name) -}}
{{- end -}}
{{- if lt (int $t.replicas) 1 -}}
{{- fail (printf "topics[%d] (%s): replicas must be at least 1." $i $t.name) -}}
{{- end -}}
{{- if gt (int $t.replicas) (int $br) -}}
{{- fail (printf "topics[%d] (%s): replicas (%d) cannot exceed the broker count (%d)." $i $t.name (int $t.replicas) (int $br)) -}}
{{- end -}}
{{- end -}}

{{/* ---------------- Users ---------------- */}}
{{- $authzType := "" -}}
{{- if .Values.cluster.authorization -}}{{- $authzType = (.Values.cluster.authorization.type | default "") -}}{{- end -}}
{{- $seenUsers := dict -}}
{{- range $i, $u := .Values.users -}}
{{- if eq (trim (default "" $u.name)) "" -}}
{{- fail (printf "users[%d].name is required." $i) -}}
{{- end -}}
{{- if hasKey $seenUsers $u.name -}}
{{- fail (printf "users[%d]: duplicate user name %q." $i $u.name) -}}
{{- end -}}
{{- $_ := set $seenUsers $u.name true -}}
{{- if not $u.authentication -}}
{{- fail (printf "users[%d] (%s): authentication is required (e.g. {type: tls} or {type: scram-sha-512})." $i $u.name) -}}
{{- end -}}
{{- if and $u.authorization $u.authorization.acls -}}
{{- if ne $authzType "simple" -}}
{{- fail (printf "users[%d] (%s) defines ACLs, but cluster.authorization.type is not \"simple\" (got %q). ACLs require the simple authorizer." $i $u.name $authzType) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* ---------------- Operator / CRD presence ---------------- */}}
{{- if .Values.strictCRDCheck -}}
{{- if not (.Capabilities.APIVersions.Has "kafka.strimzi.io/v1beta2") -}}
{{- fail "strictCRDCheck is enabled but the kafka.strimzi.io/v1beta2 CRDs are not installed. Install the Strimzi operator (operator.enabled=true) or set strictCRDCheck=false." -}}
{{- end -}}
{{- end -}}

{{- end -}}
