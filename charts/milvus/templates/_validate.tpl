{{/*
======================================================================
milvus-cluster — input validation
Included once from templates/milvus.yaml. Fails the render with a clear
message when the values would produce an invalid or unsafe Milvus resource.
======================================================================
*/}}
{{- define "milvus-cluster.validate" -}}
{{- $ := . -}}

{{/* ---------------- Milvus architecture ---------------- */}}
{{- if ne .Values.milvus.mode "cluster" -}}
{{- fail "milvus.mode must be \"cluster\". Standalone mode is not supported by this chart." -}}
{{- end -}}

{{- $proxy := .Values.milvus.components.proxy -}}
{{- $mix := .Values.milvus.components.mixCoord -}}
{{- $qn := .Values.milvus.components.queryNode -}}
{{- $dn := .Values.milvus.components.dataNode -}}
{{- $sn := .Values.milvus.components.streamingNode -}}

{{- range $name, $c := (dict "proxy" $proxy "mixCoord" $mix "queryNode" $qn "dataNode" $dn "streamingNode" $sn) -}}
{{- if not (kindIs "float64" $c.replicas) -}}
{{- if not (kindIs "int" $c.replicas) -}}
{{- fail (printf "milvus.components.%s.replicas must be an integer." $name) -}}
{{- end -}}
{{- end -}}
{{- if lt (int $c.replicas) 0 -}}
{{- fail (printf "milvus.components.%s.replicas must be a non-negative integer." $name) -}}
{{- end -}}
{{- end -}}

{{- if lt (int $proxy.replicas) 1 -}}
{{- fail "milvus.components.proxy.replicas must be at least 1." -}}
{{- end -}}
{{- if lt (int $qn.replicas) 1 -}}
{{- fail "milvus.components.queryNode.replicas must be at least 1." -}}
{{- end -}}
{{- if lt (int $dn.replicas) 1 -}}
{{- fail "milvus.components.dataNode.replicas must be at least 1." -}}
{{- end -}}
{{- if lt (int $sn.replicas) 1 -}}
{{- fail "milvus.components.streamingNode.replicas must be at least 1 (streaming architecture is mandatory in 2.6)." -}}
{{- end -}}
{{- if $mix.activeStandby -}}
{{- if lt (int $mix.replicas) 2 -}}
{{- fail "milvus.components.mixCoord.replicas must be at least 2 when mixCoord.activeStandby is enabled." -}}
{{- end -}}
{{- else -}}
{{- if lt (int $mix.replicas) 1 -}}
{{- fail "milvus.components.mixCoord.replicas must be at least 1." -}}
{{- end -}}
{{- end -}}

{{/* Legacy coordinators / IndexNode / standalone must not be configured. */}}
{{- range $k := (list "rootCoord" "dataCoord" "queryCoord" "indexCoord" "indexNode" "standalone" "cdc") -}}
{{- if hasKey $.Values.milvus.components $k -}}
{{- fail (printf "milvus.components.%s is not allowed. This chart deploys only proxy, mixCoord, queryNode, dataNode and streamingNode." $k) -}}
{{- end -}}
{{- end -}}

{{/* ---------------- External Kafka ---------------- */}}
{{- $kafka := .Values.externalKafka -}}
{{- if or (not $kafka.brokerList) (eq (len $kafka.brokerList) 0) -}}
{{- fail "externalKafka.brokerList must contain at least one broker." -}}
{{- end -}}
{{- range $i, $b := $kafka.brokerList -}}
{{- if or (not (kindIs "string" $b)) (eq (trim $b) "") -}}
{{- fail (printf "externalKafka.brokerList[%d] must be a non-empty host:port string." $i) -}}
{{- end -}}
{{- end -}}
{{- $secProtos := list "PLAINTEXT" "SSL" "SASL_PLAINTEXT" "SASL_SSL" -}}
{{- if not (has $kafka.securityProtocol $secProtos) -}}
{{- fail (printf "externalKafka.securityProtocol must be one of %s." (join ", " $secProtos)) -}}
{{- end -}}
{{- $usesSasl := or (eq $kafka.securityProtocol "SASL_PLAINTEXT") (eq $kafka.securityProtocol "SASL_SSL") -}}
{{- $usesTLS := or (eq $kafka.securityProtocol "SSL") (eq $kafka.securityProtocol "SASL_SSL") -}}
{{- if $usesSasl -}}
{{- $mechs := list "PLAIN" "SCRAM-SHA-256" "SCRAM-SHA-512" -}}
{{- if not (has $kafka.saslMechanisms $mechs) -}}
{{- fail (printf "externalKafka.saslMechanisms must be one of %s when a SASL security protocol is used." (join ", " $mechs)) -}}
{{- end -}}
{{- if and $kafka.credentials.create (ne (trim (default "" $kafka.existingSecret)) "") -}}
{{- fail "externalKafka: set EITHER credentials.create=true OR existingSecret, not both." -}}
{{- end -}}
{{- $haveInline := and $kafka.credentials.create (ne (trim (default "" $kafka.credentials.username)) "") -}}
{{- $haveExisting := ne (trim (default "" $kafka.existingSecret)) "" -}}
{{- if not (or $haveInline $haveExisting) -}}
{{- fail "externalKafka: SASL is selected but no credentials provided. Set credentials.create=true with username/password, or provide existingSecret." -}}
{{- end -}}
{{- end -}}
{{- if $usesTLS -}}
{{- if and $kafka.tls.enabled (eq (trim (default "" $kafka.tls.existingSecret)) "") -}}
{{- fail "externalKafka.tls.existingSecret is required when Kafka TLS is enabled (SSL/SASL_SSL with a private CA)." -}}
{{- end -}}
{{- end -}}
{{- if and $kafka.tls.enabled $kafka.tls.mutualTLS -}}
{{- if or (eq (trim (default "" $kafka.tls.certKey)) "") (eq (trim (default "" $kafka.tls.keyKey)) "") -}}
{{- fail "externalKafka.tls.certKey and keyKey are required when mutualTLS is enabled." -}}
{{- end -}}
{{- end -}}
{{- if $kafka.tls.insecureSkipVerify -}}
{{- fail "externalKafka.tls.insecureSkipVerify must be false (TLS verification bypass is not permitted)." -}}
{{- end -}}

{{/* ---------------- External etcd ---------------- */}}
{{- $etcd := .Values.externalEtcd -}}
{{- if or (not $etcd.endpoints) (eq (len $etcd.endpoints) 0) -}}
{{- fail "externalEtcd.endpoints must contain at least one endpoint." -}}
{{- end -}}
{{- range $i, $e := $etcd.endpoints -}}
{{- if or (not (kindIs "string" $e)) (eq (trim $e) "") -}}
{{- fail (printf "externalEtcd.endpoints[%d] must be a non-empty host:port string." $i) -}}
{{- end -}}
{{- end -}}
{{- if eq (trim (default "" $etcd.rootPath)) "" -}}
{{- fail "externalEtcd.rootPath is required and must be unique per Milvus cluster." -}}
{{- end -}}
{{- if eq $etcd.rootPath "by-dev" -}}
{{- fail "externalEtcd.rootPath must not be the unsafe default \"by-dev\"." -}}
{{- end -}}
{{- if $etcd.authentication.enabled -}}
{{- if and $etcd.authentication.createSecret (ne (trim (default "" $etcd.existingSecret)) "") -}}
{{- fail "externalEtcd: set EITHER authentication.createSecret=true OR existingSecret, not both." -}}
{{- end -}}
{{- $haveInlineEtcd := and $etcd.authentication.createSecret (ne (trim (default "" $etcd.authentication.username)) "") -}}
{{- $haveExistingEtcd := ne (trim (default "" $etcd.existingSecret)) "" -}}
{{- if not (or $haveInlineEtcd $haveExistingEtcd) -}}
{{- fail "externalEtcd: authentication.enabled is true but no credentials provided. Set authentication.createSecret=true with username/password, or provide existingSecret." -}}
{{- end -}}
{{- end -}}
{{- if $etcd.tls.enabled -}}
{{- if eq (trim (default "" $etcd.tls.existingSecret)) "" -}}
{{- fail "externalEtcd.tls.existingSecret is required when etcd TLS is enabled." -}}
{{- end -}}
{{- end -}}
{{- if $etcd.tls.insecureSkipVerify -}}
{{- fail "externalEtcd.tls.insecureSkipVerify must be false (TLS verification bypass is not permitted)." -}}
{{- end -}}

{{/* ---------------- External Ozone S3 storage ---------------- */}}
{{- $st := .Values.externalStorage -}}
{{- if eq (trim (default "" $st.endpoint)) "" -}}
{{- fail "externalStorage.endpoint is required (host:port, no URL scheme)." -}}
{{- end -}}
{{- if or (hasPrefix "http://" $st.endpoint) (hasPrefix "https://" $st.endpoint) -}}
{{- fail "externalStorage.endpoint must NOT include a URL scheme. Use host:port and control HTTPS with externalStorage.useSSL." -}}
{{- end -}}
{{- if eq (trim (default "" $st.bucketName)) "" -}}
{{- fail "externalStorage.bucketName is required." -}}
{{- end -}}
{{- if eq (trim (default "" $st.rootPath)) "" -}}
{{- fail "externalStorage.rootPath is required." -}}
{{- end -}}
{{- if and $st.credentials.create (ne (trim (default "" $st.existingSecret)) "") -}}
{{- fail "externalStorage: set EITHER credentials.create=true OR existingSecret, not both." -}}
{{- end -}}
{{- if not $st.credentials.create -}}
{{- if eq (trim (default "" $st.existingSecret)) "" -}}
{{- fail "externalStorage.existingSecret is required when credentials.create is false." -}}
{{- end -}}
{{- else -}}
{{- if or (eq (trim (default "" $st.credentials.accessKey)) "") (eq (trim (default "" $st.credentials.secretKey)) "") -}}
{{- fail "externalStorage.credentials.accessKey and secretKey are required when credentials.create is true." -}}
{{- end -}}
{{- end -}}
{{- if $st.useVirtualHost -}}
{{- /* Ozone uses path-style addressing; warn-by-failing only if someone flips it without understanding. Allowed but discouraged. */ -}}
{{- end -}}
{{- if and $st.tls.enabled $st.useSSL -}}
{{- if eq (trim (default "" $st.tls.existingSecret)) "" -}}
{{- fail "externalStorage.tls.existingSecret is required when TLS (private CA) verification is enabled." -}}
{{- end -}}
{{- end -}}
{{- if $st.tls.insecureSkipVerify -}}
{{- fail "externalStorage.tls.insecureSkipVerify must be false (TLS verification bypass is not permitted)." -}}
{{- end -}}

{{/* ---------------- Operator CRD presence (optional strict mode) ---------------- */}}
{{- if .Values.strictCRDCheck -}}
{{- if not (.Capabilities.APIVersions.Has "milvus.io/v1beta1/Milvus") -}}
{{- fail "strictCRDCheck is enabled but the milvus.io/v1beta1 Milvus CRD is not installed. Install the Milvus Operator first, or set strictCRDCheck=false." -}}
{{- end -}}
{{- end -}}

{{- end -}}
