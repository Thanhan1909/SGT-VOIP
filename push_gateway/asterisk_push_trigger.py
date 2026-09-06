#!/usr/bin/env python3
"""CLI / AGI Trigger script called by Asterisk to dispatch VoIP push via SGT Push Gateway."""

import os
import re
import sys
import json
import argparse
import urllib.request
import urllib.error

GATEWAY_URL = os.getenv("SGT_PUSH_GATEWAY_URL", "http://127.0.0.1:8085")
INTERNAL_API_SECRET = os.getenv("INTERNAL_API_SECRET", "sgt_internal_voip_secret_2026")


def sanitize_str(value: str, pattern: str = r"[^0-9a-zA-Z_.-]", max_len: int = 128) -> str:
    """Strict allowlist sanitization to prevent injection vulnerabilities."""
    if not value:
        return ""
    cleaned = re.sub(pattern, "", value.strip())
    return cleaned[:max_len]


def trigger_incoming(call_uuid: str, caller: str, caller_name: str, callee: str, ttl: int = 30) -> int:
    clean_uuid = sanitize_str(call_uuid, r"[^0-9a-zA-Z_.-]", 128)
    clean_caller = sanitize_str(caller, r"[^0-9a-zA-Z_#*+.-]", 32)
    clean_caller_name = sanitize_str(caller_name, r"[^0-9a-zA-Z _.-]", 64)
    clean_callee = sanitize_str(callee, r"[^0-9a-zA-Z_#*+.-]", 32)

    if not clean_uuid or not clean_caller or not clean_callee:
        print("[PUSH TRIGGER ERROR] Missing or invalid sanitized arguments", file=sys.stderr)
        return 1

    url = f"{GATEWAY_URL}/api/v1/internal/push/incoming"
    payload = {
        "call_uuid": clean_uuid,
        "caller_extension": clean_caller,
        "caller_display_name": clean_caller_name or f"Extension {clean_caller}",
        "callee_extension": clean_callee,
        "ttl_seconds": ttl,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-Internal-Secret": INTERNAL_API_SECRET,
        },
        method="POST",
    )
    try:
        # Keep timeout short (1.5s) to never delay telephony dialing if gateway unavailable
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            print(f"[PUSH TRIGGER SUCCESS] {result.get('message')}", file=sys.stderr)
            return 0
    except Exception as ex:
        print(f"[PUSH TRIGGER WARNING] Gateway unavailable or returned error: {ex}", file=sys.stderr)
        return 0  # Return 0 so dialplan gracefully proceeds to dial without blocking


def trigger_cancel(call_uuid: str, reason: str = "caller_hangup") -> int:
    clean_uuid = sanitize_str(call_uuid, r"[^0-9a-zA-Z_.-]", 128)
    clean_reason = sanitize_str(reason, r"[^0-9a-zA-Z_.-]", 64)

    if not clean_uuid:
        return 0

    url = f"{GATEWAY_URL}/api/v1/internal/push/cancel"
    payload = {
        "call_uuid": clean_uuid,
        "reason": clean_reason,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-Internal-Secret": INTERNAL_API_SECRET,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            print(f"[CANCEL TRIGGER SUCCESS] {result.get('message')}", file=sys.stderr)
            return 0
    except Exception as ex:
        print(f"[CANCEL TRIGGER WARNING] Cancel trigger warning: {ex}", file=sys.stderr)
        return 0


def main():
    parser = argparse.ArgumentParser(description="Asterisk VoIP Push Trigger")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # incoming subparser
    inc = subparsers.add_parser("incoming")
    inc.add_argument("--call-uuid", required=True, help="Call UUID / Channel unique ID")
    inc.add_argument("--caller", required=True, help="Caller extension number")
    inc.add_argument("--caller-name", default="", help="Caller display name")
    inc.add_argument("--callee", required=True, help="Callee extension number")
    inc.add_argument("--ttl", type=int, default=30, help="Push TTL in seconds")

    # cancel subparser
    can = subparsers.add_parser("cancel")
    can.add_argument("--call-uuid", required=True, help="Call UUID to cancel")
    can.add_argument("--reason", default="caller_hangup", help="Cancel reason")

    args = parser.parse_args()
    if args.command == "incoming":
        sys.exit(trigger_incoming(args.call_uuid, args.caller, args.caller_name, args.callee, args.ttl))
    elif args.command == "cancel":
        sys.exit(trigger_cancel(args.call_uuid, args.reason))


if __name__ == "__main__":
    main()
