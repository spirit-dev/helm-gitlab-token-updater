# Capability: token-rotation

## Purpose

Automated, zero-touch rotation of GitLab personal and group/project access tokens, with the new token values propagated to HashiCorp Vault and GitLab CI/CD variables on every rotation, and to Kubernetes registry secrets through Vault.

## Requirements

### Requirement: Scheduled token rotation

The system SHALL run a scheduled job (k8s CronJob) that rotates every GitLab access token listed in its manifest when the token's expiry falls within its configured `renew_before` window, using GitLab's rotate APIs with `expiry_after_rotate` as the new expiry.

#### Scenario: Token inside renewal window

- **WHEN** a manifest token's expiry is within `renew_before` of the current date
- **THEN** the token SHALL be rotated with a new expiry of `expiry_after_rotate` from rotation time, and the old value SHALL become invalid

#### Scenario: Token outside renewal window

- **WHEN** a manifest token's expiry is further away than `renew_before`
- **THEN** the token SHALL NOT be rotated

#### Scenario: Manifest token missing in GitLab

- **WHEN** the scheduled run cannot find a manifest token by name in its configured path
- **THEN** the run SHALL report an error and continue with remaining tokens

### Requirement: Fan-out to Vault

For every rotated token, the system SHALL write the new token value to Vault KV under `gitlab/tokens/<token-name>` as part of the same run, before the run reports success.

#### Scenario: Token rotated, Vault reachable

- **WHEN** a token is rotated and the Vault write hook succeeds
- **THEN** the new value SHALL be readable at `gitlab/tokens/<token-name>` in Vault KV and the run SHALL continue

#### Scenario: Vault write fails

- **WHEN** a token is rotated but the Vault write hook fails after all retries
- **THEN** the run SHALL report a failure (job marked failed) so the gap is visible; GitLab-side fan-out for that token SHALL still be attempted

### Requirement: Fan-out to GitLab CI/CD variables

For every rotated token with `update_var` hooks, the system SHALL update the value of the referenced group or project CI/CD variable within the same run, preserving each variable's existing masked/protected attributes.

#### Scenario: Group variable update

- **WHEN** a token with an `update_var` hook targeting a group variable is rotated
- **THEN** the variable's value SHALL equal the new token value and its masked/protected flags SHALL be unchanged

### Requirement: Self-rotation of the rotator credential

The scheduled job SHALL fetch its own GitLab credential from Vault KV at job start (no static GitLab token stored in k8s manifests or CI variables) and SHALL rotate its own credential through the same manifest mechanism.

#### Scenario: Rotator credential rotation

- **WHEN** the rotator's own token reaches its `renew_before` window
- **THEN** it SHALL be rotated in the same run, the new value written back to Vault KV before the run ends, and the successor value SHALL authenticate subsequent API calls of that run

#### Scenario: Avoiding self-lockout

- **WHEN** the Vault write-back of a self-rotation credential fails
- **THEN** a second, independently-managed credential (A/B pair) SHALL remain valid so the next scheduled run can still authenticate

### Requirement: Kubernetes registry secrets sourced from Vault

Registry pull secrets used by workloads (`*-registry-key`) SHALL be owned by external-secrets-operator, reading from the `gitlab/tokens/` KV paths, so Vault updates propagate to k8s without manual action.

#### Scenario: Token rotation propagates to imagePullSecret

- **WHEN** a registry token managed by the rotation system is rotated
- **THEN** the corresponding k8s secret SHALL be updated by external-secrets-operator and subsequent pod schedules SHALL use the new credential

### Requirement: Dry-run validation

The system SHALL support a dry-run mode that performs no writes: it SHALL verify that each manifest token name resolves in GitLab, each referenced CI/CD variable exists, and each hook script is present.

#### Scenario: Dry run against a stale manifest

- **WHEN** dry-run mode runs against a manifest referencing a deleted token or variable
- **THEN** the run SHALL report exactly those items as errors without modifying any token, variable, or Vault entry

### Requirement: Manifest as single source of inventory

The token inventory (names, paths, types, renew windows, hook targets) SHALL live in a version-controlled YAML manifest; the scheduled job SHALL run from this manifest with no token names or paths hardcoded elsewhere.

#### Scenario: Adding a new managed token

- **WHEN** an operator adds a token entry to the manifest and the next scheduled run occurs
- **THEN** that token SHALL be managed under the same rotation and fan-out rules without further configuration
