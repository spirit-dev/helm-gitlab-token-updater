#!/bin/sh
# gitlab-instance-var-put.sh — update a GitLab instance CI/CD variable via API.
# Runs inside the rotator container (Alpine, no curl CLI): uses busybox wget
# with X-HTTP-Method-Override: PUT against the GitLab REST API.
# Expects: GL_NEW_TOKEN, VAR_NAME, GITLAB_HOST, GL_TOKEN (or GL_TOKEN_FILE)
# Optional: VAR_DESCRIPTION
# No parent-env assumptions; sets its own PATH.

PATH=/usr/local/bin:/usr/bin:/bin
export PATH

# Required
VAR_NAME="${VAR_NAME:?VAR_NAME must be set}"
GL_NEW_TOKEN="${GL_NEW_TOKEN:?GL_NEW_TOKEN must be set}"
GITLAB_HOST="${GITLAB_HOST:?GITLAB_HOST must be set}"

# Auth: prefer direct GL_TOKEN, fall back to reading from a file
if [ -z "${GL_TOKEN}" ] && [ -n "${GL_TOKEN_FILE}" ]; then
  GL_TOKEN="$(cat "${GL_TOKEN_FILE}")"
fi
GL_TOKEN="${GL_TOKEN:?GL_TOKEN or GL_TOKEN_FILE must be set}"

# Build JSON payload
if [ -n "${VAR_DESCRIPTION}" ]; then
  PAYLOAD="{\"value\":\"${GL_NEW_TOKEN}\",\"description\":\"${VAR_DESCRIPTION}\"}"
else
  PAYLOAD="{\"value\":\"${GL_NEW_TOKEN}\"}"
fi

# GitLab API update for instance variable uses PUT.
# Busybox wget lacks native PUT support; X-HTTP-Method-Override: PUT via POST is used.
RESP="$(wget -qO- --no-check-certificate \
  --header "PRIVATE-TOKEN: ${GL_TOKEN}" \
  --header "X-HTTP-Method-Override: PUT" \
  --header "Content-Type: application/json" \
  --post-data "${PAYLOAD}" \
  "${GITLAB_HOST}/api/v4/admin/ci/variables/${VAR_NAME}")" || {
  echo "gitlab instance var write failed for ${VAR_NAME}: ${RESP:-no response}" >&2
  exit 1
}
