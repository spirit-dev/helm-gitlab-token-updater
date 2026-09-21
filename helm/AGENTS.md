# Helm Chart: gitlab-token-updater

## Purpose

Package and configure the `gitlab-token-updater` CronJob, ConfigMaps, and Vault integration script for deployment on Kubernetes.

## Ownership

Owns all Helm templates (`templates/`), values files (`values.yaml`, `values.turingpi.yaml`), scripts (`scripts/vault-put.sh`), and chart metadata (`Chart.yaml`).

## Local Contracts

- Deployment target namespace: `gitlab-next`.
- Release managed primarily via ArgoCD (see root `ARGOCD-OWNED`).
- Environment-specific values must be defined in `values.<env>.yaml`.
- Rotation manifests live inline in values under `manifest.config` and `manifest.selfRotation` (rendered into the manifest ConfigMap); `${VAR}` placeholders are resolved by the tool from container env, never by Helm.
- Helm chart version in `Chart.yaml` follows semantic versioning.

## Work Guidance

- Use `make template` or `helm template` to validate chart rendering before committing.
- Ensure any secret handling or token rotation logic in `scripts/vault-put.sh` remains secure and POSIX-sh compatible.

## Verification

- `helm lint helm/`
- `make template`

## Child DOX Index

None.
