# Platform notes

One section per platform, to go with the profiles in
[`charts/shyft-hydrology/examples/`](../charts/shyft-hydrology/examples/). The chart is installed and tested
on kind in CI. None of these three has been run on the real platform yet: treat every step here as a plan to
verify, and correct this file when you have.

## Sigma2 NIRD

Profile: [`sigma2-nird.yaml`](../charts/shyft-hydrology/examples/sigma2-nird.yaml).

What changes against today's setup ([Zenodo 17813414](https://doi.org/10.5281/zenodo.17813414)):

| Today | With the chart |
|---|---|
| Shyft 28.0.0 | Shyft 37.3. The chart does not deploy Shyft 28: upstream no longer publishes that image |
| `shyftservices`: seven services started in the background of one container | one container per service in the `core` pod; each restarts on its own |
| `shyftdtss`: its own Deployment | a container in the same `core` pod, with its own resources |
| `shyftdrms`: Deployment of 8, Service on port 20008 while drms listens on 22008 | Deployment of 8, no Service: each drms registers its pod IP with task |
| HTTP Ingresses in front of a binary protocol | no Ingress; `kubectl port-forward` or in-cluster clients |
| pod IP read from `/etc/hosts` | pod IP from the Kubernetes downward API |
| clients use `shyftservices:<port>` and `shyftdtss:22010` | clients use one Service, `shyft-hydrology:<port>` (same ports at base 22000) |

Steps:

1. **Mirror the image.** NIRD pulls only from Sigma2's registry. Copy the image there and put the copy's
   name in `image.repository`:

   ```sh
   skopeo copy \
     docker://registry.gitlab.com/shyft-os/shyft/fedora44-shyft-app:37.3.0-1.1 \
     docker://<sigma2 registry>/<project>/fedora44-shyft-app:37.3.0-1.1
   ```

   Keep the tag: it is the chart's `appVersion`. Renovate cannot see the mirror, so repeat this when `appVersion` moves.
2. **Databases.** Shyft 28 databases are not migrated by this chart. Either start Shyft 37 on an empty
   directory of the `/shyft-var` claim, or migrate with upstream's tools first. Do not point Shyft 37 at the
   Shyft 28 directories.
3. **User.** The services run as uid and gid 1000 by default. NIRD storage does not honour `fsGroup`: set
   `podSecurityContext.runAsUser`, `runAsGroup` and `fsGroup` to the ids that own the two directories.
4. **Install** with the profile, then `helm test`.

Open:

- Can NIRD projects install with Helm? If not: `mise run render sigma2-nird` prints plain manifests to
  apply. `helm test` is then not available.
- Does NIRD's network plugin enforce NetworkPolicy? If not, the policies are accepted and do nothing.
- Which Kubernetes version does NIRD run? The chart needs 1.30 or newer.
- The names of the two claims and of the registry.

## AWS EKS

Profile: [`aws-eks.yaml`](../charts/shyft-hydrology/examples/aws-eks.yaml).

The cluster needs:

- The **EBS CSI driver** and a `gp3` storage class for the database volume. An EBS volume lives in one
  availability zone, so the `core` pod always runs in that zone.
- A **node group for drms**: x86-64 (the image is amd64 only), on-demand, 16 vCPU or more per node, with the
  taint `dedicated=shyft-drms:NoSchedule`. Not spot: see "Scaling drms" in the chart README.
- A node for `core` with 48 GiB or more, mostly for dtss.
- **NetworkPolicy enforcement**: enable it in the VPC CNI add-on (`enableNetworkPolicy`), or run Calico or
  Cilium. Without it the chart's policies do nothing.
- For the internal load balancer: the **AWS Load Balancer Controller**. Without it, drop the `service` block
  from the profile and stay on ClusterIP.

Then set the node group name, storage class and client CIDR in the profile, install, and run `helm test`.

## Azure AKS

Profile: [`azure-aks.yaml`](../charts/shyft-hydrology/examples/azure-aks.yaml).

The cluster needs:

- A **network policy engine**, chosen when the cluster is created (Cilium, Calico or Azure).
- A **node pool for drms**: x86-64, regular priority, 16 vCPU or more per node, with the taint
  `dedicated=shyft-drms:NoSchedule`. Not spot.
- A node for `core` with 48 GiB or more.
- The built-in `managed-csi-premium` storage class works for the database volume. A managed disk lives in
  one zone, so the `core` pod always runs in that zone.

Then set the node pool name and client CIDR in the profile, install, and run `helm test`.
