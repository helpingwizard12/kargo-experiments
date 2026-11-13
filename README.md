# kargo-experiments

A proof of concept for **ring releases with Kargo and Argo CD**.

**ShopFront** is an imaginary product made of 4 microservices (`catalog`, `orders`, `payments`, `notifications`), each with its own Helm chart. It's deployed to 6 tenants in 3 rings:

| Ring | Tenants | Promotion |
|---|---|---|
| 0 – demo | `demo-sandbox`, `demo-sales` | automatic when a new release lands on `main` |
| 1 – partner | `partner-alpha`, `partner-beta` | automatic once **both** demo tenants pass verification and the release has soaked there for 2m |
| 2 – customer | `customer-acme`, `customer-globex` | **manual**, and only possible once **both** partner tenants pass verification and the release has soaked there for 5m |

```
                 main (charts/ product/ tenants/)
                              │  Warehouse "shopfront" → Freight = a commit
              ┌───────────────┴───────────────┐
        demo-sandbox                     demo-sales          ring 0 (auto)
              └───────────────┬───────────────┘
                 verified in ALL + soak 2m
              ┌───────────────┴───────────────┐
        partner-alpha                   partner-beta         ring 1 (auto)
              └───────────────┬───────────────┘
                 verified in ALL + soak 5m
              ┌───────────────┴───────────────┐
        customer-acme                  customer-globex       ring 2 (manual)
```

## Layout

```
charts/<service>/        Helm chart per microservice (hashicorp/http-echo stands in for the app)
product/release.yaml     The product release: a release name plus the version of each service
tenants/<tenant>/        Per-tenant values (name, ring, replicas)
argocd/                  AppProject + ApplicationSet: one Argo CD app per tenant (kx-<tenant>)
kargo/                   Project, ring policies, Warehouse, Stages, PromotionTask, verification
hack/                    Helper scripts
```

## How a promotion works

1. You commit a change to `charts/`, `product/` or `tenants/` on `main`. The Warehouse polls every minute and records the commit as a new piece of **Freight**.
2. Promoting Freight to a tenant Stage runs the `render-tenant` PromotionTask:
   - Runs `helm template` on all 4 charts at the Freight's commit, using that tenant's values.
   - Commits the plain manifests to the `rendered/<tenant>` branch.
   - Syncs the `kx-<tenant>` Argo CD app to that exact commit.
3. The `smoke-test` AnalysisTemplate checks that all 4 services respond. Only verified Freight can move to the next ring.

Because each tenant deploys from its own rendered branch, chart changes, version bumps and tenant config all move through the rings together. Nothing reaches a customer just because it merged to `main`.

## Setup (already done on the local colima cluster)

```bash
# cluster add-ons
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.3 -n cert-manager --create-namespace --set crds.enabled=true
helm upgrade --install argo-rollouts argo-rollouts --repo https://argoproj.github.io/argo-helm --version 2.43.12 -n argo-rollouts --create-namespace
helm upgrade --install kargo oci://ghcr.io/akuity/kargo-charts/kargo --version 1.12.5 -n kargo --create-namespace \
  --set api.adminAccount.passwordHash=... --set api.adminAccount.tokenSigningKey=... \
  --set api.service.type=NodePort --set api.service.nodePort=31444 --set externalWebhooksServer.enabled=false

# repo credentials: stores the SSH deploy key (.local/deploy-key) for Kargo (read/write) and Argo CD (read)
./hack/add-github-credentials.sh

# wire it up
kubectl apply -f kargo/project.yaml && kubectl apply -f kargo/
kubectl apply -f argocd/
```

The Kargo UI is at https://localhost:31444 (self-signed cert). The admin password is in `.local/kargo-admin.txt`, which is gitignored.

## Try it

```bash
# cut a new release: bump a service version
sed -i '' 's/name: "2026.11.0"/name: "2026.11.1"/; /orders:/{n;s/1.0.0/1.1.0/;}' product/release.yaml
git commit -am "release 2026.11.1: orders 1.1.0" && git push
```

Watch it flow: demo tenants update within about a minute, then partner tenants after the 2m soak. Customers wait for you to click **Promote** in the UI, or run:

```bash
kubectl get freight,stages -n kargo-experiments
kubectl -n kx-customer-acme get deploy -L app.kubernetes.io/version
```

## Ideas to try next

- `promotionWindows` in the ProjectConfig, so customers can only be promoted during business hours.
- `autoRollback` on verification failure.
- Break a release (point a service at a bad image tag) and watch it stop at ring 0.
- Promote one service independently: give each service its own Warehouse.
