# milvus-cluster

A production-grade Helm chart that deploys a **Milvus 2.6 cluster** through the
**Milvus Operator** by creating a single `milvus.io/v1beta1` `Milvus` custom
resource, wired exclusively to **external** Kafka, etcd and Apache Ozone (S3
Gateway).

> **This Helm chart creates a Milvus custom resource. The Milvus Operator
> reconciles that custom resource and creates the Milvus workloads.**

> **Kafka, etcd, Apache Ozone, and Ozone S3 Gateway must exist before this chart
> is installed.**

> **This chart does not deploy or manage Kafka, etcd, Apache Ozone, Ozone S3
> Gateway, MinIO, Pulsar, BookKeeper, ZooKeeper, or Woodpecker. All persistence,
> metadata, and message-stream dependencies must already exist and be reachable
> from the Milvus pods.**

---

## Table of contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Supported Milvus Operator version](#4-supported-milvus-operator-version)
5. [Supported Milvus version](#5-supported-milvus-version)
6. [What this chart creates](#6-what-this-chart-creates)
7. [What this chart does not create](#7-what-this-chart-does-not-create)
8. [Installation](#8-installation)
9. [Upgrade](#9-upgrade)
10. [Uninstall](#10-uninstall)
11. [Configuration reference](#11-configuration-reference)
12. [External Apache Ozone S3 Gateway configuration](#12-external-apache-ozone-s3-gateway-configuration)
13. [External Kafka configuration](#13-external-kafka-configuration)
14. [External etcd configuration](#14-external-etcd-configuration)
15. [TLS and private CA configuration](#15-tls-and-private-ca-configuration)
16. [Secret management](#16-secret-management)
17. [ServiceAccount configuration](#17-serviceaccount-configuration)
18. [NetworkPolicy considerations](#18-networkpolicy-considerations)
19. [Monitoring](#19-monitoring)
20. [Scaling](#20-scaling)
21. [MixCoord active/standby](#21-mixcoord-activestandby)
22. [Backup and restore considerations](#22-backup-and-restore-considerations)
23. [GitOps with Argo CD](#23-gitops-with-argo-cd)
24. [GitOps with Flux](#24-gitops-with-flux)
25. [Troubleshooting](#25-troubleshooting)
26. [CRD validation](#26-crd-validation)
27. [Security considerations](#27-security-considerations)
28. [Known limitations](#28-known-limitations)

---

## 1. Overview

`milvus-cluster` renders one `Milvus` custom resource (plus optional
ServiceAccount / Secrets / NetworkPolicy / ServiceMonitor) and hands it to an
already-installed Milvus Operator. The Operator then creates and manages the
Milvus Deployments, Services and ConfigMaps.

The chart is deliberately **dependency-free**: it never installs, upgrades,
scales or deletes Kafka, etcd or Apache Ozone. Those are treated as pre-existing,
externally-managed platform services.

## 2. Architecture

```text
Milvus Operator — already installed
        │
        └── Milvus custom resource (created by this chart)
              ├── Proxy          (client gateway, ClusterIP by default)
              ├── MixCoord       (unified coordinator, active/standby)
              ├── QueryNode
              ├── DataNode
              └── StreamingNode  (Milvus 2.6 streaming / WAL)
                    ├── External Kafka                 (message stream / WAL)
                    ├── External etcd                  (metadata)
                    └── External Apache Ozone S3 Gateway (object storage)
```

Cluster mode with the Milvus 2.6 component architecture is enforced:
`Proxy`, `MixCoord`, `QueryNode`, `DataNode`, `StreamingNode`.
Standalone mode, legacy separate coordinators (`rootCoord`/`dataCoord`/
`queryCoord`/`indexCoord`) and `IndexNode` are rejected by validation.

## 3. Prerequisites

* Kubernetes >= 1.24
* Helm >= 3.8
* **Milvus Operator >= 1.3.7** installed and healthy in the cluster
* A reachable, pre-existing **external Kafka** cluster
* A reachable, pre-existing **external etcd** cluster
* A reachable, pre-existing **Apache Ozone S3 Gateway**
* An Ozone **bucket** already created for Milvus
* Kubernetes Secrets containing the credentials / TLS material (or use the
  optional External Secrets example)

## 4. Supported Milvus Operator version

This chart was generated and validated against **Milvus Operator `1.3.7`**
(the latest stable release at authoring time), API group `milvus.io/v1beta1`.
Newer 1.3.x releases are expected to be compatible. Verify your installed
Operator's CRD before installing — see [CRD validation](#26-crd-validation).

## 5. Supported Milvus version

Validated against **Milvus `v2.6.20`** (image `milvusdb/milvus:v2.6.20`). All
`spec.config` keys used by this chart were verified against the
`configs/milvus.yaml` schema for that tag.

## 6. What this chart creates

| Resource | Condition |
|---|---|
| `Milvus` (`milvus.io/v1beta1`) | always |
| `ServiceAccount` | `serviceAccount.create=true` (default) |
| `Secret` (storage `accesskey`/`secretkey`) | `externalStorage.credentials.create=true` |
| `Secret` (Kafka SASL) | `externalKafka.credentials.create=true` |
| `Secret` (etcd auth) | `externalEtcd.authentication.createSecret=true` |
| `NetworkPolicy` | `networkPolicy.enabled=true` |
| `ServiceMonitor` | `serviceMonitor.enabled=true` |

## 7. What this chart does not create

No Kafka, etcd, Apache Ozone, Ozone S3 Gateway, MinIO, Pulsar, BookKeeper,
ZooKeeper or Woodpecker — no Deployments, StatefulSets, subcharts, Helm
dependencies or `inCluster` configuration for any of them. There is no
`Chart.lock` because the chart has no dependencies.

## 8. Installation

```bash
# 1. Lint
helm lint ./charts/milvus

# 2. Render and eyeball the Milvus CR
helm template production ./charts/milvus \
  --namespace milvus \
  --values ./charts/milvus/examples/values-production.yaml \
  > rendered.yaml

# 3. Server-side dry-run against a cluster that has the Milvus Operator CRDs
kubectl apply --dry-run=server -f rendered.yaml

# 4. Install / upgrade
helm upgrade --install production ./charts/milvus \
  --namespace milvus \
  --create-namespace \
  --values ./charts/milvus/examples/values-production.yaml
```

## 9. Upgrade

```bash
helm upgrade production ./charts/milvus \
  --namespace milvus \
  --values ./charts/milvus/examples/values-production.yaml
```

Changing `image.tag` triggers a rolling upgrade reconciled by the Operator —
read the [Milvus release notes](https://github.com/milvus-io/milvus/releases)
first. **Never** change `fullnameOverride`, `externalEtcd.rootPath` or
`externalStorage.{bucketName,rootPath}` on a cluster that holds data; doing so
points Milvus at a different/empty dataset.

## 10. Uninstall

```bash
helm uninstall production --namespace milvus
```

This deletes the `Milvus` custom resource; the Operator then tears down the
Milvus workloads. **External Kafka, etcd and Ozone (and their data) are
untouched.** Chart-created Secrets are removed with the release.

## 11. Configuration reference

Every value is documented inline in [`values.yaml`](./values.yaml) and
constrained by [`values.schema.json`](./values.schema.json). Highlights:

| Key | Default | Notes |
|---|---|---|
| `image.repository` / `image.tag` | `milvusdb/milvus` / `v2.6.20` | Milvus server image |
| `milvus.mode` | `cluster` | must be `cluster` |
| `milvus.authorization.enabled` | `true` | Milvus RBAC |
| `milvus.logging.format` | `json` | `json` or `text` |
| `milvus.config` | `{}` | free-form pass-through Milvus config |
| `milvus.components.<c>.replicas` | `2` | per component |
| `milvus.components.proxy.serviceType` | `ClusterIP` | only Proxy has a Service type |
| `milvus.components.mixCoord.activeStandby` | `true` | needs `replicas >= 2` |
| `externalStorage.*` | see §12 | Ozone S3 Gateway |
| `externalKafka.*` | see §13 | Kafka message stream |
| `externalEtcd.*` | see §14 | etcd metadata |
| `strictCRDCheck` | `false` | fail install if CRD missing |

### Config merge precedence

`spec.config` is assembled in three layers (later wins):

1. **Base defaults** produced by the chart (logging, authorization).
2. **User pass-through** `milvus.config` (rendered through `tpl`).
3. **Mandatory enforcement** — connection-critical keys derived from
   `externalStorage` / `externalKafka` / `externalEtcd`
   (`minio.*`, `kafka.*`, `etcd.*`, `mixCoord.enableActiveStandby`,
   `common.security.authorizationEnabled`).

You can add arbitrary Milvus config via `milvus.config`, but you **cannot** use
it to select internal dependencies or a non-Kafka message stream — the
dependency block always renders `external: true` and `msgStreamType: kafka`.

## 12. External Apache Ozone S3 Gateway configuration

Ozone is accessed strictly as external, S3-compatible object storage through the
Operator's `spec.dependencies.storage` (`external: true`, `type: S3`,
`secretRef`) and Milvus's internal `minio` config namespace.

```yaml
externalStorage:
  endpoint: ozone-s3g.storage.example.internal:9879   # host:port, NO scheme
  bucketName: milvus-production
  rootPath: milvus/production
  region: us-east-1
  useSSL: true            # controls HTTP vs HTTPS
  cloudProvider: aws      # generic S3-compatible
  useVirtualHost: false   # Ozone uses PATH-style addressing
  existingSecret: milvus-ozone-credentials   # keys: accesskey / secretkey
```

* The endpoint must be `host:port` **without** a URL scheme; validation rejects
  `http(s)://…`. Use `useSSL` to choose HTTPS.
* The credential Secret must contain the exact keys **`accesskey`** and
  **`secretkey`** (the names the Milvus Operator expects for `storage.secretRef`).
* Ozone normally uses **path-style** bucket addressing, hence
  `useVirtualHost: false`.

Preflight test with any S3 client (from inside the cluster):

```bash
kubectl run s3check --rm -it --image=amazon/aws-cli --restart=Never -- \
  --endpoint-url https://ozone-s3g.storage.example.internal:9879 \
  s3 ls s3://milvus-production --no-verify-ssl
```

## 13. External Kafka configuration

Kafka is the only supported message stream / WAL backend. Configured via
`spec.dependencies.kafka` (`external: true`, `brokerList`) and
`spec.config.kafka`.

```yaml
externalKafka:
  brokerList:
    - kafka-0.kafka.example.internal:9093
    - kafka-1.kafka.example.internal:9093
    - kafka-2.kafka.example.internal:9093
  securityProtocol: SASL_SSL       # PLAINTEXT | SSL | SASL_PLAINTEXT | SASL_SSL
  saslMechanisms: SCRAM-SHA-512    # PLAIN | SCRAM-SHA-256 | SCRAM-SHA-512
  existingSecret: milvus-kafka-credentials
  usernameKey: username
  passwordKey: password
```

**Credential wiring (important).** The Milvus Operator `1.3.x` provides **no
`secretRef` for Kafka**. Rather than write a plaintext password into the Milvus
custom resource, this chart projects the Secret keys into every Milvus pod as
environment variables (`KAFKA_SASLUSERNAME`, `KAFKA_SASLPASSWORD`) using
`valueFrom.secretKeyRef`. The Milvus config loader reads OS environment variables
as config overrides (verified against Milvus `v2.6.20`: keys are lower-cased and
have `.`/`_`/`/` stripped, so `KAFKA_SASLPASSWORD` overrides `kafka.saslPassword`).
**No Kafka credential is ever rendered into the `Milvus` resource.**

Preflight test (TCP reachability):

```bash
kubectl run kcheck --rm -it --image=busybox --restart=Never -- \
  sh -c 'nc -zv kafka-0.kafka.example.internal 9093'
```

## 14. External etcd configuration

```yaml
externalEtcd:
  endpoints:
    - etcd-0.etcd.example.internal:2379
    - etcd-1.etcd.example.internal:2379
    - etcd-2.etcd.example.internal:2379
  rootPath: milvus-production        # spec.config.etcd.rootPath
  existingSecret: milvus-etcd-credentials
  authentication:
    enabled: true
  tls:
    enabled: true
    existingSecret: milvus-etcd-tls
```

* **`rootPath` must be unique** when several Milvus clusters share one etcd.
* **`rootPath` must be chosen before the first deployment.** Changing it after
  Milvus has data makes existing metadata inaccessible.
* `rootPath` must not be the unsafe default `by-dev` (validation rejects it).
* etcd auth credentials are handled exactly like Kafka: projected into pods as
  `ETCD_AUTH_USERNAME` / `ETCD_AUTH_PASSWORD` env vars (overriding
  `etcd.auth.userName` / `etcd.auth.password`), never written into the CR.

Preflight test:

```bash
kubectl run etcdcheck --rm -it --image=bitnami/etcd --restart=Never -- \
  etcdctl --endpoints=https://etcd-0.etcd.example.internal:2379 endpoint health
```

## 15. TLS and private CA configuration

When `*.tls.enabled` is set, the chart mounts the referenced Secret **read-only**
into all Milvus components and points the corresponding Milvus config at the
mounted files:

| Dependency | Mount path | Milvus config key(s) |
|---|---|---|
| Ozone S3 | `/etc/milvus/certs/storage/ca.crt` | `minio.ssl.tlsCACert`, `minio.ssl.tlsMinVersion` |
| Kafka | `/etc/milvus/certs/kafka/{ca.crt,tls.crt,tls.key}` | `kafka.ssl.enabled`, `kafka.ssl.tlsCaCert`, `kafka.ssl.tlsCert`, `kafka.ssl.tlsKey` |
| etcd | `/etc/milvus/certs/etcd/{ca.crt,tls.crt,tls.key}` | `etcd.ssl.enabled`, `etcd.ssl.tlsCACert`, `etcd.ssl.tlsCert`, `etcd.ssl.tlsKey`, `etcd.ssl.tlsMinVersion` |

Notes:

* Kafka mTLS is opt-in via `externalKafka.tls.mutualTLS: true` (requires
  `certKey` + `keyKey` in the Secret). etcd client certs are mounted whenever
  `certKey` and `keyKey` are set.
* `insecureSkipVerify` must remain `false` — validation enforces it. Milvus 2.6
  exposes no runtime toggle to bypass verification for these dependencies, so the
  value is a guard only and is never rendered.
* Kafka has no `tlsMinVersion` config key in Milvus 2.6, so
  `externalKafka.tls.minVersion` is not rendered (retained for interface
  consistency).

## 16. Secret management

**Preferred: existing Secrets.** In production, keep `*.credentials.create=false`
(and `authentication.createSecret=false`) and reference Secrets you manage
out-of-band — via External Secrets Operator, HashiCorp Vault, SOPS-encrypted
manifests, Sealed Secrets or the Argo CD Vault Plugin. See
[`examples/external-secrets.yaml`](./examples/external-secrets.yaml).

**Chart-created Secrets (development only).** Setting `credentials.create=true`
makes the chart render a Secret from values you supply. **These values become
part of the Helm release data stored in the cluster** (and of any values file
they were rendered from). This is **not** suitable for Git-based/GitOps workflows
unless the values are encrypted. Never commit real credentials.

Secret key expectations:

* **Object storage** (`spec.dependencies.storage.secretRef`): keys `accesskey`
  and `secretkey`.
* **Kafka / etcd**: any keys you like; point `usernameKey` / `passwordKey` at
  them. They are projected into pods as env vars, never into the CR.

Credentials are never printed in `NOTES.txt`, annotations, labels, logs or
ConfigMaps.

**Templated Secret names.** All Secret *name* references (`externalStorage.existingSecret`,
`externalKafka.existingSecret`, `externalEtcd.existingSecret` and each
`*.tls.existingSecret`) are rendered through `tpl`, so they may contain Helm
template expressions — e.g. `existingSecret: "{{ .Release.Name }}-kafka-ca"`.
Only the **name** is templated; credential **values** are never passed through
`tpl`.

## 17. ServiceAccount configuration

```yaml
serviceAccount:
  create: true
  name: ""
  annotations: {}     # e.g. IRSA / Workload Identity
  labels: {}
```

When enabled, the ServiceAccount name is set on
`spec.components.serviceAccountName`, which the Operator applies to every Milvus
component pod. Annotations can carry cloud workload-identity bindings, though the
default external Ozone setup authenticates with access/secret keys.

## 18. NetworkPolicy considerations

`networkPolicy.enabled=true` renders a `NetworkPolicy` selecting the Milvus pods
by the `app.kubernetes.io/instance` label the Operator propagates (verify with
`kubectl get pods --show-labels`).

Because Kafka, etcd and Ozone live **outside** the cluster in this architecture,
**standard Kubernetes NetworkPolicy cannot match their DNS names**. You must
supply their IP **CIDR blocks** under
`networkPolicy.egress.{storage,kafka,etcd}.to[].ipBlock.cidr`, or use a CNI
(Cilium, Calico enterprise, …) that supports FQDN/DNS egress policies. The chart
ships **no guessed CIDRs**; the production example uses clearly-marked
placeholders. Supported peer types: `ipBlock`, `namespaceSelector`,
`podSelector`, with configurable ports.

## 19. Monitoring

Milvus exposes Prometheus metrics on port `9091` at `/metrics`. A
`ServiceMonitor` template is provided but **disabled by default** because the
Operator's metrics Service labels and port name can vary by version. Before
enabling:

```bash
kubectl -n milvus get svc --show-labels
kubectl -n milvus get svc <milvus-svc> -o jsonpath='{.spec.ports}'
```

then set `serviceMonitor.enabled=true`, adjust `serviceMonitor.selector` /
`serviceMonitor.portName`, and add the label your Prometheus selects
ServiceMonitors by (e.g. `release: kube-prometheus-stack`). If no stable
Service selector exists on your Operator version, prefer a `PodMonitor` or
annotation-based scraping instead.

## 20. Scaling

Scale by changing replicas and re-running `helm upgrade`:

```bash
helm upgrade production ./charts/milvus -n milvus \
  --reuse-values --set milvus.components.queryNode.replicas=6
```

QueryNode is the usual scaling target for query throughput; DataNode for
ingestion/compaction; StreamingNode for write/WAL throughput. Ensure the external
Kafka/etcd/Ozone tiers are sized to match.

## 21. MixCoord active/standby

`milvus.components.mixCoord.activeStandby=true` (default) sets
`spec.config.mixCoord.enableActiveStandby=true` and requires
`mixCoord.replicas >= 2` (validated). One replica is active; the rest stand by
and take over on failure.

## 22. Backup and restore considerations

* Use [milvus-backup](https://github.com/zilliztech/milvus-backup) for
  logical backups; it stores backups in S3-compatible storage (your Ozone
  bucket or a separate one).
* Back up **etcd** (Milvus metadata) and the **Ozone bucket** (segment data)
  consistently.
* **Test restore**, not just backup, before relying on this cluster in
  production.

## 23. GitOps with Argo CD

Point an `Application` at this chart and supply a values file. Keep secrets out
of Git — use the Argo CD Vault Plugin, or pre-create Secrets with External
Secrets Operator (§16). Because the chart creates a CRD instance, Argo CD needs
the Milvus Operator CRDs present to server-side dry-run/sync; set
`strictCRDCheck: false` for `helm template`-based rendering and rely on the live
cluster's CRDs at apply time.

## 24. GitOps with Flux

Use a `HelmRepository`/`GitRepository` + `HelmRelease` referencing this chart.
Reference Secrets created by External Secrets Operator; do not inline
credentials in the `HelmRelease` values.

## 25. Troubleshooting

```bash
kubectl get milvus -n milvus
kubectl describe milvus <name> -n milvus
kubectl get pods -n milvus -l app.kubernetes.io/instance=<name>
kubectl get svc  -n milvus
kubectl get events -n milvus --sort-by=.lastTimestamp
kubectl logs -n milvus deploy/<name>-milvus-proxy
```

Common issues:

* **CR not reconciled** → Milvus Operator not installed / CRD missing (see §26).
* **Pods CrashLoop on startup** → check reachability of Kafka/etcd/Ozone and the
  credentials in the referenced Secrets.
* **`AccessDenied` / bucket errors** → wrong `accesskey`/`secretkey` keys,
  `useVirtualHost` should be `false` for Ozone, or bucket/rootPath mismatch.
* **TLS handshake failures** → CA Secret key name doesn't match `caKey`, or the
  wrong CA for the endpoint.

## 26. CRD validation

The offline `helm template` never fails just because the CRD is absent. For
strict installs, set `strictCRDCheck: true` to fail fast when
`milvus.io/v1beta1/Milvus` is not present.

Validate against your live Operator:

```bash
kubectl explain milvus.spec
kubectl explain milvus.spec.components
kubectl explain milvus.spec.dependencies
kubectl explain milvus.spec.dependencies.kafka
kubectl explain milvus.spec.dependencies.etcd
kubectl explain milvus.spec.dependencies.storage

helm template production ./charts/milvus -n milvus \
  -f ./charts/milvus/examples/values-production.yaml > rendered.yaml
kubectl apply --dry-run=server -f rendered.yaml
```

## 27. Security considerations

* No real credentials or default passwords ship in the chart.
* Proxy defaults to `ClusterIP` — no public LoadBalancer/Ingress by default.
* Milvus authorization is enabled by default.
* TLS verification bypass is not permitted (`insecureSkipVerify` must be false).
* Existing Kubernetes Secrets are preferred; TLS material is mounted read-only.
* Credentials never appear in annotations, labels, logs, NOTES or ConfigMaps and
  are never rendered into the Milvus custom resource.
* Chart-created Secrets are stored in Helm release metadata — use an external
  secret manager and encrypted GitOps for production.
* `securityContext` / `runAsNonRoot` are configurable but **verify non-root
  compatibility with your Milvus image** before enabling.

## 28. Known limitations

* **No PodDisruptionBudgets.** The Operator's generated pod/Deployment labels are
  not guaranteed stable across versions, so this chart does not ship PDBs with
  guessed selectors. Inspect the real labels and add PDBs yourself:

  ```bash
  kubectl -n milvus get deploy -l app.kubernetes.io/instance=<name> --show-labels
  ```
  ```yaml
  apiVersion: policy/v1
  kind: PodDisruptionBudget
  metadata: { name: milvus-querynode }
  spec:
    minAvailable: 1
    selector:
      matchLabels:
        app.kubernetes.io/instance: <name>
        app.kubernetes.io/component: querynode   # verify the real value first
  ```

* **ServiceMonitor disabled by default** — selectors/port must be verified per
  Operator version (§19).
* **NetworkPolicy egress to external services requires CIDRs** or an
  FQDN-capable CNI (§18).
* **Kafka/etcd credentials rely on Milvus env-var config override** (verified for
  Milvus `v2.6.20`); if you pin a different Milvus version, re-verify the env
  override behaviour.
* **`kubectl apply --dry-run=server` structural validation** requires a cluster
  with the Milvus Operator CRDs installed; offline `helm template` cannot verify
  CR structure against the CRD.
```
