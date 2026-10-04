# Tasks

## 1. Inventory and environment discovery

- [x] 1.1 Dump existing GitLab tokens (admin API or Sick-IT `dump-tokens.sh` adapted), existing CI/CD variables (group + project), and all `*-registry-key` k8s secrets across namespaces; produce the token inventory that will seed the manifest
- [x] 1.2 Check the cluster for an existing secret-sync tool (ESO, kubectl-vault_sync, or equivalent) and decide reuse vs. deploy `external-secrets-operator`; record the decision in design.md
- [x] 1.3 Verify on the live GitLab instance that rotate API calls with explicit `expires_at` behave as expected (one test PAT, API call from curl), confirming compatibility with the installed GitLab version

## 2. Vault preparation (NAS)

- [x] 2.1 Enable the Vault `kubernetes` auth method against the k3s cluster and create the `rotator` policy (read/write `gitlab/tokens/*`); verify a test pod authenticates with its ServiceAccount token
- [x] 2.2 Create the bot user PATs A/B in GitLab (admin `api` scope) and seed `gitlab/tokens/rotator-pat-a` and `rotator-pat-b` in Vault KV; verify with `vault kv get`

## 3. Rotator deployment (k8s)

- [x] 3.1 Write the rotation manifest (from task 1.1 inventory): `manage_tokens[]` for all PATs/GATs with `update_var` hooks for the CI variables and `exec_cmd` hooks for Vault writes; self-rotation A/B in an `include:` file; verify the YAML validates against the tool's config schema (run tool `--dry-run`)
- [x] 3.2 Write `vault-put.sh` (reads `GL_NEW_TOKEN`, `KV_PATH`, `VAULT_ADDR`; no parent-env assumptions) and verify locally with `vault kv put/get` round-trip
- [x] 3.3 Deploy the CronJob + ServiceAccount + RBAC via ArgoCD-owned manifests in `helm/gitlab` (init step: SA-token → Vault login, fetch `rotator-pat-a` with `rotator-pat-b` fallback; then run the tool with the manifest); verify the first scheduled dry-run job completes with a clean inventory report
- [x] 3.4 Run one `--force` rotation on a low-stakes token in a manual job; verify the new value lands in Vault KV, the CI variable updates, and the old token is revoked

## 4. Kubernetes registry-secret fan-out

- [x] 4.1 Deploy external-secrets-operator (or reuse per task 1.2) and create `ExternalSecret` resources for each registry secret under `gitlab/tokens/*`; verify k8s secrets materialize with current values before touching any chart
- [x] 4.2 Remove `*-registry-key` secrets from the helm charts and verify pods pull images successfully after a rollout (per design D5, sha256 checks on those files may break — accepted)

## 5. Validation and handover

- [x] 5.1 End-to-end check: rotate a registry token via `--force`, observe ESO picking up the new Vault value and the imagePullSecret updating; document the observed propagation time
- [x] 5.2 Verify failure visibility: make Vault unreachable, trigger a run, confirm the job fails loudly (status + logs) and that the next successful run recovers via the A/B pair; then document the runbook (bootstrap order from design D7, manual recovery steps) in the rotator's README
