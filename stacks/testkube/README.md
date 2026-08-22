<!-- SPDX-FileCopyrightText: 2026 BreachSAFE <https://www.breachsafe.io> -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# testkube — Kubernetes-native test orchestration

OPT-IN test stack. Runs qureddy's pytest suite as a Testkube `Test` inside a local
`kind` cluster, with the Testkube dashboard/API exposed via `kubectl port-forward`.
NOT baked into any image, NOT run by CI.

## Bring up

```bash
cd stacks/testkube

# 1. Local cluster (one control-plane node).
kind create cluster --name bslab-testkube --config kind-config.yaml

# 2. Install Testkube (control plane + agent) via Helm.
helm repo add kubeshop https://kubeshop.github.io/helm-charts
helm repo update
helm install testkube kubeshop/testkube \
  --namespace testkube --create-namespace \
  --values values.yaml --wait --timeout 15m

# 3. Register the qureddy pytest Test and run it.
kubectl apply -f qureddy-test.yaml
kubectl testkube run test qureddy-pytest -f   # or: kubectl -n testkube create job ...

# 4. Expose the dashboard + API.
kubectl -n testkube port-forward svc/testkube-dashboard 8099:8080 &
kubectl -n testkube port-forward svc/testkube-api-server 8088:8088 &
# Dashboard: http://localhost:8099
```

## Teardown

```bash
kind delete cluster --name bslab-testkube
```

Upstream Testkube is MIT; kind/Kubernetes images keep their own licenses.
