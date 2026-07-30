# kafka-cluster

Umbrella Helm chart that stands up a complete **Apache Kafka** platform on
**Strimzi**, reusable verbatim across projects. It (optionally) installs the
**Strimzi Cluster Operator + CRDs**, then creates a **KRaft** (ZooKeeper-less)
Kafka cluster with **separate Broker and Controller `KafkaNodePool`s**, plus
`KafkaTopic`s, `KafkaUser`s and per-user **ACLs** — all from `values.yaml`.

- API group: `kafka.strimzi.io/v1` (default; override via `crdApiVersion` for older operators still serving `v1beta2`)
- Strimzi operator: **1.1.0** (appVersion), default Kafka **4.3.0** / metadata `4.3-IV0`
- Architecture: KRaft only (Strimzi 1.x removed ZooKeeper); roles split into
  dedicated node pools; JBOD brokers.

> **Defaults are a blank slate, not a production posture.** Out of the box this
> chart creates a cluster with **one PLAINTEXT listener on `:9092`, no
> authentication and no authorization** — i.e. fully open — and **no topics or
> users**. That is deliberate: the chart is meant to be driven from your own
> values file. Pick an authentication model from the table below before using it
> anywhere shared.

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
helm repo add ed-helm-charts https://eurodyn.github.io/ed-helm-charts
helm repo update
helm install kafka ed-helm-charts/kafka-cluster -n kafka --create-namespace
kubectl wait kafka/kafka -n kafka --for=condition=Ready --timeout=600s
```

That gives you the open, no-auth dev cluster described above. For anything else,
start from one of the example values files:

```sh
helm install kafka ed-helm-charts/kafka-cluster -n kafka --create-namespace \
  -f values-auth-scram.yaml
```

Installing from a local checkout instead (e.g. to test unreleased changes)
works the same way, but the Strimzi subchart must be vendored first:

```sh
helm dependency build charts/kafka          # vendor the Strimzi subchart
helm install kafka charts/kafka -n kafka --create-namespace \
  -f charts/kafka/examples/values-auth-scram.yaml
```

## Choose an authentication model

Each example is a complete, working values file — including the client-side
config and the `kubectl` commands to read the generated credentials.

| Use case | Example values file | Listener `authentication` | Identity is… | `KafkaUser` needed? |
|---|---|---|---|---|
| **No auth** — local/dev, fully open | [examples/values-auth-none.yaml](examples/values-auth-none.yaml) | *(omitted)* | `User:ANONYMOUS` (everyone) | No — `users: []` |
| **SCRAM-SHA-512** — username + password | [examples/values-auth-scram.yaml](examples/values-auth-scram.yaml) | `{type: scram-sha-512}` | the KafkaUser **name** | Yes |
| **mTLS** — client certificate | [examples/values-auth-mtls.yaml](examples/values-auth-mtls.yaml) | `{type: tls}` | the cert subject `CN=<user>` | Yes |

A Strimzi listener supports exactly **one** authentication type, so to offer both
mTLS and SCRAM you declare **two listeners** (see
[examples/values-production.yaml](examples/values-production.yaml)).

### Mapping users → the right example

`users[]` entries must line up with your listeners and authorizer, or the chart
refuses to render:

| If your `users[].authentication.type` is… | your listener must be… | and `cluster.authorization` must be… |
|---|---|---|
| `scram-sha-512` | a listener with `authentication.type: scram-sha-512` | `{type: simple}` — required for `acls` |
| `tls` | a listener with `authentication.type: tls` | `{type: simple}` — required for `acls` |
| *(no KafkaUser at all)* | a listener with **no** `authentication` | `{}` (default), **or** `{type: simple}` + `superUsers: [User:ANONYMOUS]` |

`superUsers` principal format differs by auth type — this trips people up:

| Auth type | `superUsers` entry |
|---|---|
| mTLS | `CN=break-glass-admin` (matches the certificate subject) |
| SCRAM | `my-username` (bare, no prefix) |
| anonymous | `User:ANONYMOUS` (literal) |

### Other example files

| File | Purpose |
|---|---|
| [examples/values-minimal.yaml](examples/values-minimal.yaml) | Single controller + single broker dev cluster, SCRAM. Not fault-tolerant. |
| [examples/values-production.yaml](examples/values-production.yaml) | 3+3 HA, two listeners (mTLS internal + SCRAM LoadBalancer), real StorageClasses, quotas. |
| [examples/values-shared-operator.yaml](examples/values-shared-operator.yaml) | Many projects, **one** cluster-scoped operator (`operator.enabled=false` + `strictCRDCheck=true`). |

## Deployment models

| Model | How | When |
|-------|-----|------|
| **Bundled operator** (default) | `operator.enabled=true` | Single team/cluster; the release owns the operator + CRDs. |
| **Shared operator** | `operator.enabled=false` + `strictCRDCheck=true` | Many projects, one cluster-scoped operator watching their namespaces. See [examples/values-shared-operator.yaml](examples/values-shared-operator.yaml). |

## Key values

| Path | Default | Purpose |
|------|---------|---------|
| `crdApiVersion` | `v1` | Strimzi CRD API version to render resources as. Must match a version served by the target cluster's operator (`kubectl get crd kafkas.kafka.strimzi.io -o jsonpath='{.spec.versions[*].name}'`). |
| `operator.enabled` | `true` | Install the Strimzi operator + CRDs as a subchart. |
| `operator.watchAnyNamespace` | `false` | Operator watches all namespaces (shared model). |
| `cluster.name` | `""` (→ fullname) | Kafka CR name + `strimzi.io/cluster` label. Keep short. |
| `cluster.version` / `cluster.metadataVersion` | `4.3.0` / `4.3-IV0` | Kafka + KRaft metadata level. |
| `cluster.listeners` | one `plain` PLAINTEXT `:9092`, **no auth** | Pass-through listener list (one auth type per listener). |
| `cluster.authorization` | `{}` — **no ACL authorizer** | Set `{type: simple}` for deny-by-default ACLs. `null` to remove after enabling. |
| `cluster.config` | tuned map (RF 3 / ISR 2) | Broker config. Cross-checked against broker count — see Guardrails. |
| `cluster.livenessProbe` / `cluster.readinessProbe` | `{}` (Strimzi defaults) | **Cluster-wide** probes for all Kafka pods. `KafkaNodePool` has no probe field, so these cannot be set per-pool. |
| `cluster.entityOperator` | topic+user operators w/ resources | Reconciles Topic/User CRs. Set `null` to disable (not `{}`). |
| `cluster.kafkaExporter` | enabled | Consumer-lag metrics. Set `null` to disable (not `{}`). |
| `cluster.metrics.enabled` | `false` | JMX→Prometheus ConfigMap + `metricsConfig`. |
| `nodePools.controller.replicas` | `3` | KRaft controllers — **must be odd**. |
| `nodePools.broker.replicas` | `3` | Brokers. Must be ≥ every replication factor. |
| `nodePools.broker.storage` | JBOD, 1 × 50Gi | Multi-volume broker storage (add volumes for parallel I/O). |
| `topics[]` | `[]` | `{name, partitions, replicas, config}` → one `KafkaTopic` each. |
| `users[]` | `[]` | `{name, authentication, authorization.acls, quotas}` → one `KafkaUser` each. |

Nested Strimzi blocks (`storage`, `resources`, `jvmOptions`, `template`,
`listeners`, `config`, `acls`, `authentication`, `quotas`, `entityOperator`,
`kafkaExporter`) are **passed through to the CRDs verbatim** — set any field the
`crdApiVersion` schema accepts without editing templates. Values may contain Helm
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

ACLs require `cluster.authorization.type: simple` — the chart fails the render
otherwise, since ACLs are silently ignored without the authorizer.

The User Operator provisions credentials into a Secret named after each user:
`tls` → `user.crt`/`user.key` (+ `user.p12`); `scram-sha-512` → `password`.

## Storage & KRaft metadata

Every node — broker or controller — keeps a copy of the KRaft metadata log. By
default Strimzi puts it on the volume with the **lowest `id`**; pin it with
`kraftMetadata: shared` (at most one volume may have it):

```yaml
nodePools:
  broker:
    storage:
      type: jbod
      volumes:
        - { id: 0, type: persistent-claim, size: 500Gi, class: fast-nvme, kraftMetadata: shared }
        - { id: 1, type: persistent-claim, size: 500Gi, class: standard-ssd }
```

- **Brokers**: the metadata volume is shared with partition data; extra volumes
  hold partition data only. Pin explicitly if you plan to add volumes later —
  adding a lower-`id` volume otherwise **relocates the log** and forces a rolling
  update that deletes and recreates it.
- **Controllers**: storage holds *only* the metadata log, which always lives on a
  single volume — so extra/JBOD volumes buy nothing and `kraftMetadata` is
  redundant there.

## Operational notes

**`helm uninstall` can hang on KafkaTopic finalizers.** The Topic Operator adds a
`strimzi.io/topic` finalizer to every `KafkaTopic`, so deleting the CR blocks
until the topic is really gone from Kafka — but the same release also deletes the
Topic Operator that would clear it. To trade that risk for possibly-orphaned
topics:

```yaml
cluster:
  entityOperator:
    template:
      topicOperatorContainer:
        env:
          - name: STRIMZI_USE_FINALIZERS
            value: "false"
```

## Validation & guardrails

`templates/_validate.tpl` fails the render with an actionable message when:

- **Node pools** — controllers aren't odd or < 1; brokers < 1; broker storage
  isn't `jbod`.
- **Replication vs. broker count** — `default.replication.factor`,
  `offsets.topic.replication.factor` or
  `transaction.state.log.replication.factor` exceeds `nodePools.broker.replicas`;
  or a topic's `replicas` exceeds it.
- **ISR vs. replication factor** — `min.insync.replicas` >
  `default.replication.factor`, or `transaction.state.log.min.isr` >
  `transaction.state.log.replication.factor`.
  *(Keys explicitly set to `null` are skipped, so you can defer to Kafka's own
  defaults.)*
- **Listeners** — the list is empty; or an **anonymous** listener is combined
  with `authorization.type: simple` without `User:ANONYMOUS` in `superUsers`
  (which would let clients connect but deny every request).
- **Topics / users** — missing or duplicate names; a user without
  `authentication`; a user with `acls` while `authorization.type` isn't `simple`.
- **Reserved config** — `cluster.config` sets a Strimzi-managed key
  (`controller.*`, `process.roles`, `node.id`, `metadata.log.dir`,
  `zookeeper.*`, `broker.id`, `listeners`, `advertised.*`).
- **CRDs** — `strictCRDCheck=true` and `kafka.strimzi.io/<crdApiVersion>` is absent.

## Verify locally

```sh
helm dependency build charts/kafka
helm lint charts/kafka
helm template t charts/kafka -f charts/kafka/examples/values-auth-scram.yaml
helm template t charts/kafka | kubectl apply --dry-run=server -f -   # needs a cluster + CRDs
```

CI (`ct lint`, see [.github/workflows/lint.yml](../../.github/workflows/lint.yml))
additionally renders every file in [ci/](ci/) — one variant per file, covering the
minimal, production, mTLS, no-auth and anonymous-superuser paths. Add a `ci/`
file when you add a code path worth regression-testing; chart defaults alone
render very little.

## Notes

- A Strimzi listener supports exactly **one** authentication type — mTLS and
  SCRAM are therefore on separate listeners.
- Keep the release name / `cluster.name` short: pod names are
  `<cluster>-<pool>-<id>` and must stay under 63 chars (chart truncates the
  cluster name to 40).
- No live cluster is required to lint/template; `--dry-run=server` against a real
  cluster with the CRDs installed is the recommended pre-prod gate.
