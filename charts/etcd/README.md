# etcd

A Helm chart for deploying an [etcd](https://etcd.io/) cluster on Kubernetes as a `StatefulSet`.

## Introduction

This chart bootstraps an [etcd](https://github.com/etcd-io/etcd) cluster on a [Kubernetes](https://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

etcd members discover each other through a headless `Service`, and each member gets a stable network identity backed by a `PersistentVolumeClaim` created via `volumeClaimTemplates`.

## Prerequisites

- Kubernetes 1.19+
- Helm 3+
- PV provisioner support in the underlying infrastructure (for persistence)
- [cert-manager](https://cert-manager.io/) v1.13+ installed in the cluster, only if you enable `tls.certManager.enabled`

## Installing the Chart

Add the repository, then install the chart with the release name `my-etcd`:

```console
helm repo add ed-helm-charts https://eurodyn.github.io/ed-helm-charts
helm repo update
helm install my-etcd ed-helm-charts/etcd
```

The command deploys etcd on the Kubernetes cluster with the default configuration. The [Parameters](#parameters) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-etcd` deployment:

```console
helm uninstall my-etcd
```

The command removes all the Kubernetes components associated with the chart, except for the PVCs associated with the cluster. To delete them as well:

```console
kubectl delete pvc -l app.kubernetes.io/instance=my-etcd
```

> **Note**: Deleting the PVCs will destroy the etcd data as well. Proceed with caution.

## Parameters

### Common parameters

| Name               | Description                                                        | Value |
| ------------------ | ------------------------------------------------------------------- | ----- |
| `nameOverride`      | Override the name of the chart                                    | `""`  |
| `fullnameOverride`  | Override the release name                                         | `""`  |
| `replicaCount`      | Number of etcd replicas                                           | `3`   |
| `initialClusterState` | Initial cluster state. Must be `new` on first install, and switched to `existing` before scaling an existing cluster | `new` |
| `clusterDomain`     | Cluster domain suffix, used to build DNS SANs for TLS certificates | `cluster.local` |

### Image parameters

| Name                 | Description                                                    | Value              |
| -------------------- | ---------------------------------------------------------------- | ------------------- |
| `image.registry`     | etcd image registry                                             | `quay.io`           |
| `image.repository`   | etcd image repository                                           | `coreos/etcd`       |
| `image.tag`          | etcd image tag (defaults to the chart's `appVersion` if not set) | `""`                |
| `image.pullPolicy`   | etcd image pull policy                                          | `IfNotPresent`      |
| `imagePullSecrets`   | Names of the secrets to pull the image from private registries | `[]`                |

### Storage parameters

| Name                | Description                                                   | Value  |
| ------------------- | ---------------------------------------------------------------| ------ |
| `persistence.size`  | Size of the PVC created for each etcd replica's data volume    | `10Gi` |

### Pod parameters

| Name                                   | Description                                    | Value                                   |
| ---------------------------------------- | ------------------------------------------------ | ------------------------------------------ |
| `podAnnotations`                       | Annotations added to each etcd pod             | `{}`                                    |
| `podLabels`                            | Labels added to each etcd pod                  | `{}`                                    |
| `podSecurityContext`                   | Pod-level security context                     | `{fsGroup: 1001}`                       |
| `securityContext`                      | Container-level security context               | `{runAsNonRoot: true, runAsUser: 1001}` |
| `resources`                            | Container resource requests/limits             | `{limits: {cpu: 1, memory: 1Gi}, requests: {cpu: 300m, memory: 512Mi}}` |
| `readinessProbe`                       | Readiness probe configuration (`/readyz`)      | See `values.yaml`                       |
| `livenessProbe`                        | Liveness probe configuration (`/livez`)        | See `values.yaml`                       |
| `volumes`                              | Additional volumes added to the pod            | `[]`                                    |
| `volumeMounts`                         | Additional volume mounts added to the etcd container | `[]`                              |
| `tolerations`                          | Tolerations for pod assignment                 | `[]`                                    |
| `affinity`                             | Affinity rules for pod assignment. Defaults to a preferred pod anti-affinity that spreads replicas across nodes | See `values.yaml` |

### Disruption parameters

| Name                   | Description                                                                          | Value |
| ------------------------ | --------------------------------------------------------------------------------------- | ----- |
| `pdb.create`            | Whether to create a PodDisruptionBudget                                             | `true` |
| `pdb.maxUnavailable`    | Max number of pods that can be unavailable at once. Ignored if `minAvailable` is set | `1`   |
| `pdb.minAvailable`      | Min number of pods that must stay available. Takes precedence over `maxUnavailable`  | `""`  |

### mTLS parameters

| Name                              | Description                                                                                    | Value           |
| ------------------------------------ | -------------------------------------------------------------------------------------------------- | ----------------- |
| `tls.enabled`                     | Enable mTLS for the client and peer listeners                                                  | `false`         |
| `tls.certManager.enabled`         | Issue/rotate certificates via cert-manager instead of supplying pre-existing secrets            | `false`         |
| `tls.certManager.issuerRef.name`  | Name of an existing cert-manager `Issuer`/`ClusterIssuer` to sign with. Leave empty to have the chart bootstrap its own self-signed CA | `""` |
| `tls.certManager.issuerRef.kind`  | Kind of the referenced issuer (`Issuer` or `ClusterIssuer`)                                     | `ClusterIssuer` |
| `tls.certManager.issuerRef.group` | API group of the referenced issuer                                                              | `cert-manager.io` |
| `tls.certManager.duration`        | Validity period of the issued client/peer certificates                                          | `2160h` (90d)   |
| `tls.certManager.renewBefore`     | How long before expiry cert-manager renews the certificates                                     | `360h` (15d)    |
| `tls.client.existingSecret`       | Name of a pre-existing Secret (`tls.crt`/`tls.key`/`ca.crt`) for the client listener. Required when `tls.enabled=true` and `tls.certManager.enabled=false` | `""` |
| `tls.peer.existingSecret`         | Name of a pre-existing Secret (`tls.crt`/`tls.key`/`ca.crt`) for peer traffic. Required when `tls.enabled=true` and `tls.certManager.enabled=false` | `""` |

## Configuration and installation details

### Scaling the cluster

`replicaCount` controls both the number of `StatefulSet` replicas and the static `--initial-cluster` member list rendered by the chart. Because of etcd's [bootstrapping semantics](https://etcd.io/docs/latest/op-guide/clustering/), scaling an existing cluster is a two-step operation:

1. Set `initialClusterState` to `existing`.
2. Increase `replicaCount` and upgrade the release.

Applying both changes in the same upgrade, or leaving `initialClusterState` as `new` when scaling, will cause the new members to fail to join the cluster.

```console
helm upgrade my-etcd ed-helm-charts/etcd --set initialClusterState=existing --set replicaCount=5
```

### Networking

The chart creates a single headless `Service` (`<fullname>-headless`) with `publishNotReadyAddresses: true`, exposing three ports:

| Port name      | Port   | Purpose                          |
| -------------- | ------ | --------------------------------- |
| `etcd-client`  | `2379` | Client requests (`etcdctl`, apps) |
| `etcd-server`  | `2380` | Peer-to-peer traffic between members |
| `etcd-metrics` | `8080` | Plaintext metrics and the `/readyz`/`/livez` health endpoints |

Each pod also gets a stable DNS name in the form `<fullname>-<ordinal>.<fullname>-headless.<namespace>.svc.cluster.local`, which is what members use to advertise themselves to their peers.

### mTLS

Set `tls.enabled: true` to require mutual TLS on both the client-facing listener (`--cert-file`/`--key-file`/`--client-cert-auth`, also used by the in-container `etcdctl`) and the peer listener (`--peer-cert-file`/`--peer-key-file`/`--peer-client-cert-auth`). This also flips `URI_SCHEME` from `http` to `https` throughout the StatefulSet.

Certificates can be sourced two ways:

**1. cert-manager (`tls.certManager.enabled: true`)** — the chart renders [`templates/certificates.yaml`](templates/certificates.yaml), which creates two `Certificate` resources (`<fullname>-client-tls`, `<fullname>-peer-tls`), each with DNS SANs covering the headless service and a wildcard for every pod's stable per-ordinal name. You have two options for signing:
   - Set `tls.certManager.issuerRef.name` to an `Issuer`/`ClusterIssuer` you already manage.
   - Leave it empty and the chart bootstraps its own self-signed CA (a self-signed `Issuer` → CA `Certificate` → CA `Issuer`, all scoped to this release).

   ```console
   helm upgrade my-etcd ed-helm-charts/etcd --set tls.enabled=true --set tls.certManager.enabled=true
   ```

**2. Pre-existing secrets (`tls.certManager.enabled: false`)** — supply `tls.client.existingSecret` and `tls.peer.existingSecret`, each pointing at a Secret you created out-of-band containing the keys `tls.crt`, `tls.key`, and `ca.crt`. The chart fails fast with a clear error if either is left unset while `tls.enabled: true`.

   The certificate's SANs must cover the headless service and every pod's stable per-ordinal name; a wildcard is the simplest way to do that:

   ```
   DNS: <fullname>, <fullname>-headless, <fullname>-headless.<namespace>,
        <fullname>-headless.<namespace>.svc.<clusterDomain>,
        *.<fullname>-headless.<namespace>.svc.<clusterDomain>, localhost
   IP:  127.0.0.1
   ```

   Once you have `tls.crt`/`tls.key`/`ca.crt` on disk, create the Secret with:

   ```console
   kubectl create secret generic my-etcd-client-tls -n <namespace> \
     --from-file=tls.crt=./tls.crt --from-file=tls.key=./tls.key --from-file=ca.crt=./ca.crt
   ```

   (repeat for the peer secret), then `--set tls.client.existingSecret=my-etcd-client-tls --set tls.peer.existingSecret=my-etcd-peer-tls`.

**Notes:**
- Certificate rotation doesn't require a pod restart: the certs are mounted as a Secret volume (kubelet resyncs mounted Secret contents on its normal sync interval, ~1 minute by default), and etcd has reloaded its cert/key/CA files from disk on every new TLS connection since v3.2.0 — no watch/restart involved, and the docs note the per-connection overhead is negligible. No `checksum/config`-style annotation or rollout is needed; long-lived peer connections pick up the new material once they reconnect, which the default 15-day `renewBefore` window comfortably covers.
- On first install with `tls.certManager.enabled: true`, pods may sit in `ContainerCreating` for a few seconds until cert-manager finishes issuing the Secrets — this is expected.
- Metrics/health endpoints (`--listen-metrics-urls`) stay on plain HTTP regardless of `tls.enabled`, matching upstream etcd's Kubernetes guide.

### Disruption budget

By default the chart creates a PodDisruptionBudget with `maxUnavailable: 1`, which is quorum-safe for the default `replicaCount` of `3` (etcd tolerates losing 1 of 3 members). If you change `replicaCount`, revisit `pdb.maxUnavailable`/`pdb.minAvailable` so voluntary disruptions (node drains, cluster upgrades) can't take down more members than the cluster can tolerate without losing quorum.

### Persistence

The chart uses `volumeClaimTemplates` to provision one PVC per replica (`etcd-data`), sized via `persistence.size`. Because `volumeClaimTemplates` are immutable, changing the size after installation requires manually resizing the underlying PVCs (if your storage class supports it) or recreating the `StatefulSet`.

## Checking cluster health

After installing, run:

```console
kubectl exec -n <namespace> <fullname>-0 -- etcdctl endpoint health --cluster
```

See the output of `helm install`/`helm upgrade` (the chart's `NOTES.txt`) for the exact per-member endpoints and command for your release.

## Chart values example

```yaml
replicaCount: 5

image:
  registry: quay.io
  repository: coreos/etcd
  tag: v3.7.0

persistence:
  size: 20Gi

resources:
  limits:
    cpu: "2"
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

## License

Copyright European Dynamics SA.
