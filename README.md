# gitlab-token-updater

[![GitLab Sync](https://img.shields.io/badge/gitlab_sync-gitlab_token_updater-blue?style=for-the-badge&logo=gitlab)](https://gitlab-internal.spirit-dev.net/github-mirror/helm-gitlab-token-updater) <!-- markdownlint-disable MD041 -->
[![GitHub Mirror](https://img.shields.io/badge/github_mirror-gitlab_token_updater-blue?style=for-the-badge&logo=github)](https://github.com/spirit-dev/helm-gitlab-token-updater)
[![App Status](https://argocd-internal.spirit-dev.net/api/badge?name=gitlab-token-updater-turingpi&revision=true&showAppName=true)](https://argocd-internal.spirit-dev.net/applications/gitlab-token-updater-turingpi)

<!--TOC-->

______________________________________________________________________

**Table of Contents**

- [Installation process](#installation-process)
- [Rotation Hooks](#rotation-hooks)
  - [1. `use_token`](#1-use_token)
  - [2. `update_var`](#2-update_var)
  - [3. `exec_cmd`](#3-exec_cmd)
    - [Available Helper Scripts](#available-helper-scripts)
- [Operational Runbook](#operational-runbook)
  - [1. Initial Bootstrap Procedure](#1-initial-bootstrap-procedure)
  - [2. Lockout Recovery & Troubleshooting](#2-lockout-recovery--troubleshooting)
    - [A. Automatic A/B Pair Recovery](#a-automatic-ab-pair-recovery)
    - [B. Emergency Total Lockout (Both A & B Invalid)](#b-emergency-total-lockout-both-a--b-invalid)

______________________________________________________________________

<!--TOC-->

## Installation process

The installation is entirely managed by Argocd.

A `Makefile` is present here to ease the first and one-time deployment or in case of an issue.
The installation should be done in two steps:

```shell
#> make dry-run ENV=<ENV>
#> make install ENV=<ENV>
```

## Rotation Hooks

Rotation hooks run sequentially after a token is rotated. When running with `--dry-run`, validation verifies that referenced target variables and scripts exist.

### 1. `use_token`

Re-authenticates the current run using the newly rotated token. Used for self-rotation of the rotator's own credentials.

- **Type:** `use_token`
- **Scope:** Personal access tokens only (`type: personal`).
- **Placement:** Must be the first hook in the token's hook list.
- **Parameters:** None.

```yaml
- name: rotator-pat-a
  hooks:
    - type: use_token
    - type: exec_cmd
      args:
        path: /usr/local/bin/vault-put.sh
        env:
          KV_PATH: gitlab/tokens/rotator-pat-a
          VAULT_ADDR: ${VAULT_ADDR}
          VAULT_TOKEN_FILE: ${VAULT_TOKEN_FILE}
```

### 2. `update_var`

Natively updates a GitLab repository or group CI/CD variable via the GitLab REST API. Existing variable attributes (`masked`, `protected`, `environment_scope`, `description`) are preserved.

- **Type:** `update_var`
- **Scope:** Project/repository or group variables.
- **Parameters:**
  - `type`: Target scope (`repository` or `group`).
  - `path`: Target project path (`group/project`) or group path (`group`).
  - `name`: CI/CD variable key (must match `[a-zA-Z0-9_]`).
  - `gitlab` *(optional)*: External GitLab instance URL.
  - `gitlab_token` *(optional)*: Token for external GitLab instance.

```yaml
- name: my-project-token
  hooks:
    - type: update_var
      args:
        type: repository
        path: infrastructure/helm/my-app
        name: CI_PROJECT_TOKEN
```

### 3. `exec_cmd`

Executes an external shell script with the new token injected via `GL_NEW_TOKEN` environment variable.

- **Type:** `exec_cmd`
- **Parameters:**
  - `path`: Path to executable script.
  - `env`: Key-value map of environment variables passed to script. Supports `${VAR}` expansion from container environment.
  - `retry` *(optional)*: Number of retries on failure (default: chart `default_hook_retry`).

#### Available Helper Scripts

- **`vault-put.sh`:** Writes token to HashiCorp Vault KV-v2 (`gitlab/tokens/<name>`).
  - Required env: `KV_PATH`, `VAULT_ADDR`, `VAULT_TOKEN_FILE` (or `VAULT_TOKEN`).
- **`gitlab-instance-var-put.sh`:** Updates instance-level CI/CD variable (`/api/v4/admin/ci/variables/:key`) via GitLab API (using `X-HTTP-Method-Override: PUT` with `wget`).
  - Required env: `VAR_NAME`, `GITLAB_HOST`, `GL_TOKEN_FILE` (or `GL_TOKEN`).
  - Optional env: `VAR_DESCRIPTION`.

```yaml
- name: semantic-release-pat
  hooks:
    - type: exec_cmd
      args:
        path: /usr/local/bin/vault-put.sh
        env:
          KV_PATH: gitlab/tokens/semantic-release-pat
          VAULT_ADDR: ${VAULT_ADDR}
          VAULT_TOKEN_FILE: ${VAULT_TOKEN_FILE}
    - type: exec_cmd
      args:
        path: /usr/local/bin/gitlab-instance-var-put.sh
        env:
          VAR_NAME: GL_TOKEN
          VAR_DESCRIPTION: "Managed by gitlab token updater. Belongs to PAT from user SemanticRelease/semantic-release-pat"
          GITLAB_HOST: ${GITLAB_HOST}
          GL_TOKEN_FILE: ${GL_TOKEN_FILE}
```

## Operational Runbook

### 1. Initial Bootstrap Procedure

When bootstrapping a fresh environment from scratch (Design D7):

1. **GitLab Bot User:**
   - Create dedicated bot user `token-rotator` in GitLab (`Admin > Users > New User`, set `Admin: true`).
   - Impersonate or log in as `token-rotator` and generate two Personal Access Tokens with `api` scope:
     - `rotator-pat-a` (expiry: standard 3M)
     - `rotator-pat-b` (expiry: standard 3M, offset by ~1.5M for staggered rotation)

2. **Vault Configuration:**
   - Enable `kubernetes` auth method on Vault:
     ```bash
     vault auth enable kubernetes
     ```
   - Configure Vault Kubernetes auth using the long-lived `vault-token-reviewer` token from this chart:
     ```bash
     SA_JWT=$(kubectl -n gitlab-next get secret vault-token-reviewer-token -o jsonpath='{.data.token}' | base64 -d)
     K8S_HOST="https://kubernetes.default.svc"
     K8S_CACERT=$(kubectl -n gitlab-next get secret vault-token-reviewer-token -o jsonpath='{.data.ca\.crt}' | base64 -d)

     vault write auth/kubernetes/config \
       token_reviewer_jwt="$SA_JWT" \
       kubernetes_host="$K8S_HOST" \
       kubernetes_ca_cert="$K8S_CACERT"
     ```
   - Create `rotator` policy:
     ```hcl
     path "gitlab/data/tokens/*" {
       capabilities = ["create", "read", "update"]
     }
     path "gitlab/metadata/tokens/*" {
       capabilities = ["list", "read"]
     }
     ```
   - Bind `rotator` role to the `gitlab-token-updater` ServiceAccount in namespace `gitlab-next`:
     ```bash
     vault write auth/kubernetes/role/rotator \
       bound_service_account_names=gitlab-token-updater \
       bound_service_account_namespaces=gitlab-next \
       policies=rotator \
       ttl=1h
     ```

3. **Seed Initial Vault Secrets:**
   ```bash
   vault kv put gitlab/tokens/rotator-pat-a value="glpat-..."
   vault kv put gitlab/tokens/rotator-pat-b value="glpat-..."
   vault kv put gitlab/tokens/registry-token value="glpat-..."
   # seed other inventory tokens...
   ```

4. **ExternalSecrets Deployment:**
   - Deploy `ClusterSecretStore` (`vault-gitlab-tokens`) and `ExternalSecret` (`gitlab-registry-key`) across target namespaces.
   - Verify that k8s secrets materialize before starting rotator runs.

5. **Deploy & Validate:**
   - Deploy chart via ArgoCD (`dryRun: true` for the first cycle).
   - Verify clean inventory dry-run report in CronJob logs.
   - Switch `dryRun: false` for automatic scheduled rotations.

---

### 2. Lockout Recovery & Troubleshooting

#### A. Automatic A/B Pair Recovery

- Self-rotation rotates `rotator-pat-a` first, switches in-memory to the successor via `use_token`, and writes back to Vault KV.
- If the write-back fails or network drops, `rotator-pat-a` in Vault becomes stale.
- On the next scheduled run, the init container attempts `rotator-pat-a`; if invalid/missing, it automatically falls back to `rotator-pat-b`.
- The run succeeds using `rotator-pat-b`, self-healing the cycle.

#### B. Emergency Total Lockout (Both A & B Invalid)

If both tokens expire simultaneously or were manually revoked:

1. Log into GitLab Web UI as Administrator.
2. Navigate to `Admin > Users > token-rotator > Impersonate` (or edit user).
3. Generate a new Personal Access Token named `rotator-pat-a` with scope `api`.
4. Re-seed Vault KV directly:
   ```bash
   vault kv put gitlab/tokens/rotator-pat-a value="glpat-<new-token>"
   ```
5. Trigger a manual run of the CronJob:
   ```bash
   kubectl -n gitlab-next create job --from=cronjob/gitlab-token-updater gtu-manual-recovery
   kubectl -n gitlab-next logs -f job/gtu-manual-recovery -c rotator
   ```
6. The job authenticates using `rotator-pat-a`, rotates `rotator-pat-b`, and normal operation resu
