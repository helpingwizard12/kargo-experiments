#!/usr/bin/env bash
# Workloads scaled to 0 on 2026-11-14 to free memory for this POC (colima: 2 CPU / 2 GiB).
# Run this to bring them back to their previous replica counts.
set -euo pipefail
kubectl -n kube-system scale deploy vpa-admission-controller vpa-recommender vpa-updater --replicas=1
kubectl -n keda scale deploy keda-admission keda-metrics-apiserver keda-operator --replicas=1
kubectl -n temporal-local scale deploy temporal-worker --replicas=1
kubectl -n temporal-worker-demo scale deploy temporal-worker --replicas=3
kubectl -n autoscaling-lab scale deploy temporal-worker-hpa --replicas=1
