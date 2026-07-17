<p align="center">
  <img src="logo_ed.png" alt="European Dynamics" width="150"/>
</p>

# ED Helm Charts

A collection of Helm charts maintained by [European Dynamics SA](https://www.eurodyn.com) for deploying common infrastructure components on Kubernetes.

## Usage

Add the repository:

```console
helm repo add ed-helm-charts https://eurodyn.github.io/ed-helm-charts
helm repo update
```

## Available charts

| Chart | Status | Install |
| ----- | ------ | ------- |
| [etcd](charts/etcd/README.md) | Available | `helm install my-etcd ed-helm-charts/etcd` |
| kafka | Work in progress, not yet published | - |

### etcd

Deploys an [etcd](https://etcd.io/) cluster as a Kubernetes `StatefulSet`, with support for mTLS (via cert-manager or pre-existing secrets), PodDisruptionBudgets, and persistent per-member storage. See the [chart README](charts/etcd/README.md) for full configuration details.

```console
helm install my-etcd ed-helm-charts/etcd
```

### kafka

Not yet implemented — tracked in [charts/kafka/TODO.md](charts/kafka/TODO.md).

## License

Copyright European Dynamics SA.
