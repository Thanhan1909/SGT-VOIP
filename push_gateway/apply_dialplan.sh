#!/usr/bin/env bash
set -euo pipefail

# Idempotent and transactional dialplan applicator for SGT VoIP Phase 4
SRC_DIALPLAN="/home/an-sgt/odoo19_01/push_gateway/extensions.conf.phase4"
TARGET_DIALPLAN="/etc/asterisk/extensions.conf"
BACKUP_DIR="/home/an-sgt/odoo19_01/backups/dialplan"

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
BACKUP_FILE="${BACKUP_DIR}/extensions.conf.${TIMESTAMP}.bak"

echo "[DIALPLAN] Backing up ${TARGET_DIALPLAN} -> ${BACKUP_FILE}..."
if [ -f "$TARGET_DIALPLAN" ]; then
    cp "$TARGET_DIALPLAN" "$BACKUP_FILE"
fi

echo "[DIALPLAN] Applying new dialplan from ${SRC_DIALPLAN}..."
cp "$SRC_DIALPLAN" "${TARGET_DIALPLAN}.tmp"

# Atomically replace
mv "${TARGET_DIALPLAN}.tmp" "$TARGET_DIALPLAN"
chmod 640 "$TARGET_DIALPLAN"
chown asterisk:asterisk "$TARGET_DIALPLAN" 2>/dev/null || true

echo "[DIALPLAN] Reloading Asterisk dialplan..."
if ! asterisk -rx "dialplan reload" >/dev/null; then
    echo "[ERROR] Dialplan reload failed. Rolling back..."
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$TARGET_DIALPLAN"
        asterisk -rx "dialplan reload" || true
    fi
    exit 1
fi

echo "[DIALPLAN] Validating dialplan contexts..."
if ! (asterisk -rx "dialplan show sub-push-dial" | grep -q "sub-push-dial"); then
    echo "[ERROR] Context sub-push-dial not found after reload. Rolling back..."
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$TARGET_DIALPLAN"
        asterisk -rx "dialplan reload" || true
    fi
    exit 1
fi

if ! (asterisk -rx "dialplan show sub-push-cancel-on-hangup" | grep -q "sub-push-cancel-on-hangup"); then
    echo "[ERROR] Context sub-push-cancel-on-hangup not found after reload. Rolling back..."
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$TARGET_DIALPLAN"
        asterisk -rx "dialplan reload" || true
    fi
    exit 1
fi

echo "[SUCCESS] Dialplan applied and validated successfully."
