#!/usr/bin/env bash
# Starts comp-review-api (port 12001) and the comp-review-ui static server (port 12101).
# The container stops when either process ends; tini (PID 1) forwards stop signals to both.
set -euo pipefail

WEBUI_ROOT=/app/webui
API_DIR=/app/reviewer/api

# Web UI runtime settings: the browser calls the API through the host port, so the URL comes from Compose.
cat > "${WEBUI_ROOT}/config.json" <<EOF
{
  "environment": "${WEBUI_ENVIRONMENT:-development}",
  "apiBaseUrl": "${WEBUI_API_BASE_URL:-http://localhost:12001}",
  "pollIntervalMs": ${WEBUI_POLL_INTERVAL_MS:-3000}
}
EOF

echo "Compliance Reviewer $(cat /app/reviewer/VERSION 2>/dev/null || echo '?') (deployed ${APP_DEPLOY_DATE:-unknown})"
echo "API environment: ${COMP_REVIEW_API_ENVIRONMENT:-development}; Web UI environment: ${WEBUI_ENVIRONMENT:-development}"
for v in ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN; do
  if [ -n "${!v:-}" ]; then echo "Credential present: ${v}"; fi
done

cd "${API_DIR}"
python run.py &
api_pid=$!

python /app/docker/spa_server.py --root "${WEBUI_ROOT}" --port 12101 &
ui_pid=$!

# Exit as soon as either process stops, so Docker reports (and can restart) the failure.
set +e
wait -n "${api_pid}" "${ui_pid}"
rc=$?
kill "${api_pid}" "${ui_pid}" 2>/dev/null
wait
exit "${rc}"
