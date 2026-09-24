#!/bin/sh
# vault-put.sh — write a token value to Vault KV.
# Runs inside the rotator container (Alpine, no vault/curl CLI): uses busybox wget
# against the Vault HTTP API instead of the vault binary.
# Expects: GL_NEW_TOKEN, KV_PATH, VAULT_ADDR, VAULT_TOKEN (or VAULT_TOKEN_FILE)
# No parent-env assumptions; sets its own PATH.

PATH=/usr/local/bin:/usr/bin:/bin
export PATH

# Required
KV_PATH="${KV_PATH:?KV_PATH must be set}"
GL_NEW_TOKEN="${GL_NEW_TOKEN:?GL_NEW_TOKEN must be set}"
VAULT_ADDR="${VAULT_ADDR:?VAULT_ADDR must be set}"

# Auth: prefer direct VAULT_TOKEN, fall back to reading from a file
if [ -z "${VAULT_TOKEN}" ] && [ -n "${VAULT_TOKEN_FILE}" ]; then
  VAULT_TOKEN="$(cat "${VAULT_TOKEN_FILE}")"
fi
VAULT_TOKEN="${VAULT_TOKEN:?VAULT_TOKEN or VAULT_TOKEN_FILE must be set}"

# KV v2 wire path: gitlab/tokens/<name> -> /v1/gitlab/data/tokens/<name>
# ponytail: assumes KV-v2 mounts and PAT charset (no quote/backslash in JSON);
# switch to the vault CLI or add JSON escaping if either ever stops holding
MOUNT="${KV_PATH%%/*}"
REST="${KV_PATH#*/}"

RESP="$(wget -qO- --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --post-data "{\"data\":{\"value\":\"${GL_NEW_TOKEN}\"}}" \
  "${VAULT_ADDR}/v1/${MOUNT}/data/${REST}")" || {
  echo "vault write failed for ${KV_PATH}: ${RESP:-no response}" >&2
  exit 1
}