#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_CONF="${SCRIPT_DIR}/extensions.conf.phase4"
TARGET_CONF="/etc/asterisk/extensions.conf"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_CONF="/etc/asterisk/extensions.conf.bak_phase4_${TIMESTAMP}"

echo "=== SGT Asterisk Dialplan Updater (Phase 4) ==="

if [[ ! -f "${SOURCE_CONF}" ]]; then
    echo "ERROR: Source configuration ${SOURCE_CONF} not found!" >&2
    exit 1
fi

echo "1. Backing up ${TARGET_CONF} -> ${BACKUP_CONF}..."
cp "${TARGET_CONF}" "${BACKUP_CONF}"

echo "2. Installing updated dialplan..."
cp "${SOURCE_CONF}" "${TARGET_CONF}"

echo "3. Reloading Asterisk dialplan..."
asterisk -rx "dialplan reload"

echo "4. Verifying dialplan [from-internal]..."
asterisk -rx "dialplan show from-internal"

echo "SUCCESS: Asterisk dialplan updated and reloaded with push notification support."
