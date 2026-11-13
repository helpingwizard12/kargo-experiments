#!/usr/bin/env bash
# Stores this repo's SSH deploy key in the cluster:
#   - Kargo needs read/write (it pushes rendered/<tenant> branches)
#   - Argo CD needs read
# The key lives in .local/deploy-key (gitignored). To create a new one:
#   ssh-keygen -t ed25519 -N '' -f .local/deploy-key
#   gh repo deploy-key add .local/deploy-key.pub --repo helpingwizard12/kargo-experiments --allow-write --title kargo
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=git@github.com:helpingwizard12/kargo-experiments.git
KEY=.local/deploy-key

kubectl create namespace kargo-experiments --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kargo-experiments create secret generic github-creds \
  --from-literal=repoURL="$REPO" --from-file=sshPrivateKey="$KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kargo-experiments label secret github-creds kargo.akuity.io/cred-type=git --overwrite

kubectl -n argocd create secret generic kargo-experiments-repository \
  --from-literal=type=git --from-literal=url="$REPO" --from-file=sshPrivateKey="$KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret kargo-experiments-repository argocd.argoproj.io/secret-type=repository --overwrite
echo "Done: deploy key stored for Kargo and Argo CD."
