#!/usr/bin/env bash
# Stores a GitHub fine-grained PAT for this repo in the cluster:
#   - Kargo needs read/write (it pushes rendered/<tenant> branches)
#   - Argo CD needs read
# Create the PAT at https://github.com/settings/personal-access-tokens/new
#   Repository access: Only select repositories -> kargo-experiments
#   Permissions: Contents = Read and write
set -euo pipefail
REPO=https://github.com/tanish120704/kargo-experiments.git
read -rp "GitHub username: " GH_USER
read -rsp "Fine-grained PAT (input hidden): " GH_PAT; echo

kubectl create namespace kargo-experiments --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kargo-experiments create secret generic github-creds \
  --from-literal=repoURL="$REPO" --from-literal=username="$GH_USER" --from-literal=password="$GH_PAT" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kargo-experiments label secret github-creds kargo.akuity.io/cred-type=git --overwrite

kubectl -n argocd create secret generic kargo-experiments-repository \
  --from-literal=type=git --from-literal=url="$REPO" --from-literal=username="$GH_USER" --from-literal=password="$GH_PAT" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret kargo-experiments-repository argocd.argoproj.io/secret-type=repository --overwrite
echo "Done: credentials stored for Kargo and Argo CD."
