# kafka-cluster

Umbrella Helm chart that stands up a complete **Apache Kafka** platform on
**Strimzi**, reusable verbatim across projects. It (optionally) installs the
**Strimzi Cluster Operator + CRDs**, then creates a **KRaft** (ZooKeeper-less)
Kafka cluster with **separate Broker and Controller `KafkaNodePool`s**, plus
`KafkaTopic`s, `KafkaUser`s and per-user **ACLs** — all from `values.yaml`.

- API group: `kafka.strimzi.io/v1beta2`
- Strimzi operator: **1.1.0** (appVersion), default Kafka **4.3.0** / metadata `4.3-IV0`
- Architecture: KRaft only (Strimzi 1.x removed ZooKeeper); roles split into
  dedicated node pools; JBOD brokers; deny-by-default `simple` authorization.

## How the umbrella works

```
kafka-cluster (this chart)
├── operator.enabled=true  ─▶ subchart: strimzi-kafka-operator 1.1.0
│                              installs the operator Deployment/RBAC + CRDs
└── templates/             ─▶ Kafka, KafkaNodePool (controller+broker),
                               KafkaTopic[], KafkaUser[], metrics ConfigMap
```

The Strimzi subchart ships its CRDs in a **`crds/`** directory. Helm installs
subchart CRDs **first** (refreshing API discovery) before rendering this chart's
custom resources, so a **single `helm install` works end-to-end**.

> **CRD upgrades are manual.** Helm installs `crds/` only on first install and
> never upgrades/deletes them. When you bump the Strimzi version, apply the new
> CRDs yourself before `helm upgrade`:
> ```sh
> kubectl replace -f https://github.com/strimzi/strimzi-kafka-operator/releases/download/<VERSION>/strimzi-crds-<VERSION>.yaml
> ```

## Quick start

```sh
helm dependency build charts/kafka          # vendor the Strimzi subchart
helm install kafka charts/kafka -n kafka --create-namespace
kubectl wait kafka/kafka -n kafka --for=condition=Ready --timeout=600s
```

Override for your project with a values file:

```sh
helm install kafka charts/kafka -n kafka --create-namespace \
  -f charts/kafka/examples/values-production.yaml
```

## Deployment models

| Model | How | When |
|-------|-----|------|
| **Bundled operator** (default) | `operator.enabled=true` | Single team/cluster; the release owns the operator + CRDs. |
| **Shared operator** | `operator.enabled=false` + `strictCRDCheck=true` | Many projects, one cluster-scoped operator watching their namespaces. See [examples/values-shared-operator.yaml](examples/values-shared-operator.yaml). |

## Key values

| Path | Default | Purpose |
|------|---------|---------|
| `operator.enabled` | `true` | Install the Strimzi operator + CRDs as a subchart. |
| `operator.watchAnyNamespace` | `false` | Operator watches all namespaces (shared model). |
| `cluster.name` | `""` (→ fullname) | Kafka CR name + `strimzi.io/cluster` label. Keep short. |
| `cluster.version` / `cluster.metadataVersion` | `4.3.0` / `4.3-IV0` | Kafka + KRaft metadata level. |
| `cluster.listeners` | internal mTLS `:9092`, external SCRAM LB `:9093` | Pass-through listener list (one auth type per listener). |
| `cluster.authorization` | `{type: simple}` | Deny-by-default ACL authorizer. |
| `cluster.config` | tuned map | Broker config (`default.replication.factor`, `min.insync.replicas`, threads, retention, …). |
| `cluster.entityOperator` | topic+user operators w/ resources | Reconciles Topic/User CRs. Set `null` to disable (not `{}`). |
| `cluster.kafkaExporter` | enabled | Consumer-lag metrics. Set `null` to disable (not `{}`). |
| `cluster.metrics.enabled` | `true` | JMX→Prometheus ConfigMap + `metricsConfig`. |
| `nodePools.controller.replicas` | `3` | KRaft controllers — **must be odd**. |
| `nodePools.broker.replicas` | `3` | Brokers. Must be ≥ max topic replication factor. |
| `nodePools.broker.storage` | JBOD 2×500Gi | Multi-volume broker storage. |
| `topics[]` | 2 examples | `{name, partitions, replicas, config}` → one `KafkaTopic` each. |
| `users[]` | 2 examples | `{name, authentication, authorization.acls, quotas}` → one `KafkaUser` each. |

Nested Strimzi blocks (`storage`, `resources`, `jvmOptions`, `template`,
`listeners`, `config`, `acls`, `authentication`, `quotas`, `entityOperator`,
`kafkaExporter`) are **passed through to the CRDs verbatim** — set any field the
`v1beta2` schema accepts without editing templates. Values may contain Helm
template expressions (rendered with `tpl`).

## Topics, Users & ACLs

```yaml
topics:
  - name: orders.events
    partitions: 24
    replicas: 3
    config: { min.insync.replicas: 2, retention.ms: 1209600000 }

users:
  - name: orders-consumer
    authentication: { type: scram-sha-512 }   # or { type: tls }
    authorization:
      type: simple
      acls:
        - resource: { type: topic, name: orders., patternType: prefix }
          operations: [Read, Describe]
        # consumers MUST have Read on their group to commit offsets:
        - resource: { type: group, name: orders-, patternType: prefix }
          operations: [Read]
```

The User Operator provisions credentials into a Secret named after each user:
`tls` → `user.crt`/`user.key` (+ `user.p12`); `scram-sha-512` → `password`.

## Validation & guardrails

`templates/_validate.tpl` fails the render with a clear message when:
controllers aren't odd; broker storage isn't JBOD; a topic's replicas exceed the
broker count; duplicate topic/user names; a user defines ACLs while
`cluster.authorization.type` isn't `simple`; or `cluster.config` sets a
Strimzi-managed key (`controller.*`, `process.roles`, `node.id`,
`metadata.log.dir`, `zookeeper.*`, …). `strictCRDCheck=true` additionally fails
if the `kafka.strimzi.io/v1beta2` CRDs are absent.

## Verify locally

```sh
helm dependency build charts/kafka
helm lint charts/kafka
helm template t charts/kafka | kubectl apply --dry-run=server -f -   # needs a cluster + CRDs
```

## Notes

- A Strimzi listener supports exactly **one** authentication type — mTLS and
  SCRAM are therefore on separate listeners.
- Keep the release name / `cluster.name` short: pod names are
  `<cluster>-<pool>-<id>` and must stay under 63 chars (chart truncates the
  cluster name to 40).
- No live cluster is required to lint/template; `--dry-run=server` against a real
  cluster with the CRDs installed is the recommended pre-prod gate.
