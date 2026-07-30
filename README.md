<p align="center">
  <img src="logo_ed.png" alt="European Dynamics" width="150"/>
</p>

# ED Helm Charts

A collection of Helm charts maintained by [European Dynamics SA](https://www.eurodyn.com) for deploying common infrastructure components on Kubernetes.

## Usage

```console
helm repo add ed-helm-charts https://eurodyn.github.io/ed-helm-charts
helm repo update
helm search repo ed-helm-charts
helm install my-etcd ed-helm-charts/etcd
```

## Available charts

| Chart | Status | Install |
| ----- | ------ | ------- |
| [etcd](charts/etcd/README.md) | Available | `helm install my-etcd ed-helm-charts/etcd` |
| [kafka](charts/kafka/README.md) | Available | `helm install my-kafka ed-helm-charts/kafka-cluster` |
| [milvus](charts/milvus/README.md) | Available | `helm install my-milvus ed-helm-charts/milvus-cluster` |

### etcd

Deploys an [etcd](https://etcd.io/) cluster as a Kubernetes `StatefulSet`, with support for mTLS (via cert-manager or pre-existing secrets), PodDisruptionBudgets, and persistent per-member storage. See the [chart README](charts/etcd/README.md) for full configuration details.

### kafka

Umbrella chart that stands up a production-oriented Apache Kafka platform on [Strimzi](https://strimzi.io/) — KRaft (ZooKeeper-less), with separate broker/controller `KafkaNodePool`s, `KafkaTopic`s, `KafkaUser`s and per-user ACLs, and an optional bundled Strimzi operator. See the [chart README](charts/kafka/README.md) for authentication examples and full configuration details.

### milvus

Production-grade chart that deploys a [Milvus](https://milvus.io/) 2.6 cluster through the Milvus Operator by creating a single `milvus.io/v1beta1` `Milvus` custom resource. It connects exclusively to **pre-existing external** Kafka, etcd and Apache Ozone (S3 Gateway) — it never installs or manages those dependencies itself. See the [chart README](charts/milvus/README.md) for prerequisites and full configuration details.

## License

Copyright European Dynamics SA.
