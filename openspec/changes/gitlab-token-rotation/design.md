# Design

## Context

- GitLab (single instance) runs on k3s via the helm chart, ArgoCD-owned; everything under `helm/` is deployed this way, so the rotator should follow the same pattern.
- HashiCorp Vault runs single-node on the NAS (OpenMediaVault, docker, file storage, auto-unseal via OMV cron, nightly backup). Ansible-managed in `provisioning/nas-server`. No plugins, no HA — design must keep Vault a write-through store, not a runtime dependency for running workloads.
- Rotator core: `iomarmochtar/gitlab-token-updater` (Go, MIT, ~600 lines on `xanzy/go-gitlab`). Features confirmed by source review: PAT/GAT/repo-token rotation via GitLab rotate APIs with explicit `ExpiresAt`; `update_var` hook (group + project CI variables, masked/protected preserved); `exec_cmd` hook (script path, `GL_NEW_TOKEN` env, per-hook `retry`); `use_token` hook (successor token re-authenticates the same run); `--dry-run` (read-only existence checks); `include:`-based manifest splitting; durations `Nd`/`NM`/`NY` only.
- Scale: ~10 PATs, ~25 CI variables, ~10 k8s `*-registry-key` imagePullSecrets.

## Goals / Non-Goals

**Goals:**

- Zero-touch rotation with fan-out to Vault KV and GitLab CI variables.
- Self-rotation of the rotator's own credential without a static secret in k8s.
- Dry-run as an inventory validation pass.

**Non-Goals:**

- Replacing GitLab CI/CD variables with JWT→Vault CI integration (design "A") — optional future hardening, per-repo, unchanged by this design.
- Vault GitLab secrets plugin (design "C") — makes the single-node Vault runtime-critical; rejected.
- Creating new CI variables or k8s secrets from scratch — bootstrap once manually, automation only updates values.
- Alerting infrastructure — job failure surfaces through existing monitoring of CronJob status.

## Decisions

### D1: `gitlab-token-updater` as rotator core (vs. custom rotator / token-operator)

Small, MIT, audited in full; its hook model covers both fan-out targets natively. Alternatives: writing the same ~600 lines ourselves (NIH), or Sick-IT/token-operator (native Vault sink but no CI-variable hook, GPL-3). Fork is a viable escape hatch if upstream dies — the config surface and hook contract are stable.

### D2: k8s CronJob, not scheduled GitLab pipeline

User decision. The tool's canonical example runs as a scheduled pipeline (self-rotation closing the loop via CI variables), but the CronJob variant closes the loop through Vault instead. Consequences accepted:

- Requires Vault `kubernetes` auth method (one-time setup) so the job authenticates with its ServiceAccount — no static Vault token in k8s.
- Self-rotation loop: init/fetch credential from Vault KV → run tool → `use_token` → `exec_cmd` writes successor back to Vault KV → next run reads it.

### D3: A/B credential pair for lockout safety

Rotate API invalidates the old token immediately. If the self-rotation write-back to Vault fails, the run is locked out. Two admin PATs owned by a dedicated bot user, both in the manifest:

- `A` rotates → `use_token` (run continues on successor) → `exec_cmd` → Vault KV write (retry: 5)
- `B` stays untouched until its own window → next runs recover using `B` if `A`'s write failed
- Job entrypoint fetches `A` first, falls back to `B`; success of either validates the loop.
Alternative considered: single non-expiring admin PAT + monitoring — rejected as it contradicts zero-touch rotation goals.

### D4: Hook script `vault-put.sh` — one script, env-parameterized

`exec.Command(path)` takes no arguments and the hook env does NOT inherit the parent environment (verified in `pkg/shell/shell.go`). The script therefore sets its own PATH and reads everything from explicitly-passed env:

```yaml
- type: exec_cmd
  retry: 5
  args:
    path: /usr/local/bin/vault-put.sh
    env: { VAULT_ADDR: "http://<nas>:8200", KV_PATH: "gitlab/tokens/renovate" }
```

Script body: `vault kv put "$KV_PATH" value="$GL_NEW_TOKEN"` (plus token fetch for Vault itself — the SA-token exchange happens in the job entrypoint, and the resulting VAULT_TOKEN is passed via the hook env or written to a file read by the script).

### D5: k8s registry secrets via external-secrets-operator

Registry tokens land in Vault KV (`gitlab/tokens/<name>`); ESO `ExternalSecret` resources per consuming namespace replace the per-chart `*-registry-key` secrets. Fulfills the existing TODO "nice to have" (centralize registry-key ownership). ArgoCD manages the ESO manifests; removing the secrets from charts may break per-file sha256 checks in those repos — accepted (TODO already notes this: images pull once, pods re-pull with updated credentials).

### D6: Manifest location and shape

Manifest lives in this repo (`helm/gitlab`), one `manage_tokens[]` block per target group/repo/personal, `include:` split between the standard inventory and `internal.yml`-style self-rotation entries (A/B credentials). Schedule: monthly (`renew_before: 14d`, `expiry_after_rotate: 3M` defaults — tool defaults). Image: `iomarmochtar/gitlab-token-updater` from Docker Hub (mirror to internal registry if policy requires).

### D7: Bootstrap order (one-time, manual)

1. Create bot user + PATs A/B (admin `api` scope) in GitLab.
2. Enable Vault `kubernetes` auth method + `rotator` policy (read/write `gitlab/tokens/*`, read only own paths).
3. `vault kv put gitlab/tokens/rotator-a value=...` (and `-b`).
4. Create CI variables and ESO ExternalSecrets (initial values seeded manually).
5. Deploy CronJob via ArgoCD → run `--dry-run` → first real run.

## Risks / Trade-offs

- [Vault write-back fails after self-rotation → run can't authenticate next time] → A/B pair (D3): `B` remains valid; gap visible via failed job status.
- [Vault unavailable at run time (NAS down)] → job fails, retries next schedule; no running workload affected (Vault is write-through, ESO caches last values in k8s secrets). No action needed.
- [Rotate invalidates old token before fan-out completes] → inherent to GitLab rotate API; window is seconds, hooks have retries; failed fan-out leaves a stale Vault entry until next `renew_before` window — mitigated for CI variables (hook failure reported), accepted for Vault (next run re-writes only on next rotation; stale Vault entry is the known wart — noted as candidate for a small periodic "Vault re-sync" job if it ever bites).
- [Single maintainer upstream project] → vendored config-compatible hook contract; fork on first breaking change.
- [Docker Hub dependency for the tool image] → mirror to internal registry during bootstrap if pull policy requires.
- [10 registry secrets removed from charts → ESO must be running before] → deploy ESO and ExternalSecrets before removing chart-owned secrets (migration plan).

## Migration Plan

1. Deploy Vault k8s auth + policies + KV seeds (manual, once).
2. Deploy ESO + ExternalSecrets with chart secrets still present (duplicate values, no breakage).
3. Remove `*-registry-key` from charts once ESO-managed secrets verified.
4. Deploy rotator CronJob in dry-run mode for one cycle; verify report.
5. First real run with `--force` on one low-stakes token; observe fan-out.
6. Enable full manifest.

Rollback: CronJob is additive; revert by deleting the CronJob/ExternalSecrets and restoring chart secrets — token values in GitLab remain valid regardless.

## Open Questions

- Exact ESO deployment in this cluster: does an equivalent secret-sync tool already exist under `helm/`? (Answer during implementation task 1; approach unchanged either way.)
- Mirror of the rotator image to the internal registry or direct Docker Hub pull — deploy-time choice, no design impact.
- Alert wiring for failed runs (existing monitoring stack vs. GitLab notification channels) — can be attached after first real run.
