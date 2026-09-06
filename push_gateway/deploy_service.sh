#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/sgt-push-gateway"
ENV_FILE="${CONFIG_DIR}/gateway.env"
SERVICE_SRC="${SCRIPT_DIR}/sgt-push-gateway.service"
SERVICE_DEST="/etc/systemd/system/sgt-push-gateway.service"

echo "=== SGT Push Gateway Idempotent Deploy Script ==="

# 1. Ensure configuration directory and environment file exist
mkdir -p "${CONFIG_DIR}"
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Creating default environment file at ${ENV_FILE}..."
    cat << 'EOF' > "${ENV_FILE}"
# SGT VoIP Push Gateway Configuration
INTERNAL_API_SECRET=sgt_internal_voip_secret_2026
DEVICE_AUTH_SECRET=sgt_internal_voip_secret_2026
APNS_BUNDLE_ID=com.sgt.voip.flutterSipSoftphone
GATEWAY_DB_PATH=/var/lib/sgt-push-gateway/gateway.db
EOF
    chmod 0600 "${ENV_FILE}"
    chown -R an-sgt:an-sgt "${CONFIG_DIR}" 2>/dev/null || true
fi

# 2. Install / Update Systemd Service
echo "Installing systemd unit ${SERVICE_DEST}..."
cp "${SERVICE_SRC}" "${SERVICE_DEST}"

# 3. Reload daemon and restart service
echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Restarting sgt-push-gateway.service..."
systemctl restart sgt-push-gateway

# 4. Verification
echo "Verifying service status..."
sleep 2

ACTIVE_STATE=$(systemctl is-active sgt-push-gateway)
if [[ "${ACTIVE_STATE}" != "active" ]]; then
    echo "ERROR: Service failed to activate! Current state: ${ACTIVE_STATE}" >&2
    systemctl status sgt-push-gateway --no-pager >&2
    exit 1
fi

echo "Service is active. Checking health endpoint..."
HEALTH_RESP=$(curl -s --max-time 3 http://127.0.0.1:8085/health || true)
echo "Health Response: ${HEALTH_RESP}"

if [[ "${HEALTH_RESP}" != *"sgt-push-gateway"* ]]; then
    echo "ERROR: Health check failed!" >&2
    exit 1
fi

echo "SUCCESS: SGT Push Gateway deployed and running healthy."
