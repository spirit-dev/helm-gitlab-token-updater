#!/bin/sh
# gitlab-instance-var-put.sh — update a GitLab instance CI/CD variable via API.
# Runs inside the rotator container (Alpine, no curl CLI): uses busybox wget
# with X-HTTP-Method-Override: PUT against the GitLab REST API.
# Expects: GL_NEW_TOKEN, VAR_NAME, GITLAB_HOST, GL_TOKEN (or GL_TOKEN_FILE)
# Optional: VAR_DESCRIPTION, VAR_FORMAT (e.g. dockerconfigjson),
#           DOCKER_REGISTRY_HOST, DOCKER_REGISTRY_USER, VAR_MASKED, VAR_TYPE
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

# Format value if requested
if [ "${VAR_FORMAT}" = "dockerconfigjson" ]; then
  DOCKER_REGISTRY_HOST="${DOCKER_REGISTRY_HOST:?DOCKER_REGISTRY_HOST must be set for dockerconfigjson format}"
  DOCKER_REGISTRY_USER="${DOCKER_REGISTRY_USER:?DOCKER_REGISTRY_USER must be set for dockerconfigjson format}"
  AUTH="$(printf '%s:%s' "${DOCKER_REGISTRY_USER}" "${GL_NEW_TOKEN}" | base64 | tr -d '\r\n')"
  VAR_VALUE="{\"auths\":{\"${DOCKER_REGISTRY_HOST}\":{\"auth\":\"${AUTH}\"}}}"
else
  VAR_VALUE="${GL_NEW_TOKEN}"
fi

# Escape JSON characters for PUT payload
ESCAPED_VALUE="$(printf '%s' "${VAR_VALUE}" | sed 's/\\/\\\\/g; s/"/\\"/g')"

if [ -n "${VAR_DESCRIPTION}" ]; then
  ESCAPED_DESC="$(printf '%s' "${VAR_DESCRIPTION}" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  PAYLOAD="{\"value\":\"${ESCAPED_VALUE}\",\"description\":\"${ESCAPED_DESC}\"}"
else
  PAYLOAD="{\"value\":\"${ESCAPED_VALUE}\"}"
fi

if [ -n "${VAR_MASKED}" ]; then
  PAYLOAD="${PAYLOAD%\}},\"masked\":${VAR_MASKED}}"
fi
if [ -n "${VAR_TYPE}" ]; then
  PAYLOAD="${PAYLOAD%\}},\"variable_type\":\"${VAR_TYPE}\"}"
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
