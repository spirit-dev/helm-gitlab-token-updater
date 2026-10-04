# Proposal

## Why

GitLab access tokens (PATs/GATs), CI/CD variables, and k8s registry secrets are renewed manually today; a missed expiry silently breaks automation (runners, renovate, ArgoCD pulls, CI). With ~10 PATs, ~25 CI variables, and ~10 k8s imagePullSecrets, manual rotation does not scale and violates the zero-touch operations goal.

## What Changes

- Deploy `iomarmochtar/gitlab-token-updater` as a scheduled Kubernetes CronJob in the cluster hosting GitLab.
- Introduce a YAML manifest (token inventory) driving rotation: per-token `renew_before`, `expiry_after_rotate`, and fan-out hooks.
- Rotate PATs/GATs via GitLab rotate APIs with custom expiry (`expiry_after_rotate`, default 3M).
- Fan out new token values to:
  - HashiCorp Vault KV (`gitlab/tokens/<name>`) via `exec_cmd` hook — Vault as write-through source of truth for k8s consumption.
  - GitLab CI/CD variables (group and project level) via native `update_var` hooks.
- Self-rotation: the CronJob's own PAT is rotated by the tool itself (`use_token` hook + Vault write-back); credentials are fetched from Vault at job start (init container), so no static secret in k8s.
- k8s registry secrets (`*-registry-key`) are sourced from Vault KV via external-secrets-operator, replacing the per-chart copies (fulfills the existing TODO "nice to have").
- `--dry-run` support as inventory validation (token names resolve, target variables exist, scripts present).

## Capabilities

### New Capabilities

- `token-rotation`: automated rotation of GitLab PATs/GATs with fan-out to Vault KV and GitLab CI/CD variables, self-rotation of the rotator credential, and dry-run validation.

### Modified Capabilities
<!-- None: no existing spec's requirements change. -->

## Impact

- **New components**: k8s CronJob + ServiceAccount + RBAC (cluster-local), small `vault-put.sh` hook script, ESO `ExternalSecret` resources for registry secrets.
- **Vault (NAS)**: enable `kubernetes` auth method (CronJob SA token → Vault policy, bootstrap credential stored in KV); new KV paths under `gitlab/tokens/`.
- **GitLab**: one privileged PAT (admin `api` scope) for the rotator, owned by a dedicated bot/service user; token values update in place (masked/protected flags preserved).
- **Helm charts**: `*-registry-key` secrets removed from charts and owned by ESO instead.
- **Dependencies**: `iomarmochtar/gitlab-token-updater` image (docker hub; consider mirroring to internal registry), `external-secrets-operator` (if not already deployed).
- **Risks**: rotate API invalidates the old token immediately — hook fan-out must succeed (retries configured); a failed Vault write-back of the self-rotation token can lock the rotator out (mitigated by A/B token pair, see design).
