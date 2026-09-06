#!/usr/bin/env python3
"""CLI / AGI Trigger script called by Asterisk to dispatch VoIP push via SGT Push Gateway."""

import sys
import json
import argparse
import urllib.request
import urllib.error

GATEWAY_URL = "http://127.0.0.1:8085"


def trigger_incoming(call_uuid: str, caller: str, caller_name: str, callee: str, ttl: int = 30) -> int:
    url = f"{GATEWAY_URL}/api/v1/internal/push/incoming"
    payload = {
        "call_uuid": call_uuid,
        "caller_extension": caller,
        "caller_display_name": caller_name or f"Extension {caller}",
        "callee_extension": callee,
        "ttl_seconds": ttl,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            print(f"[PUSH TRIGGER SUCCESS] {result.get('message')}", file=sys.stderr)
            return 0
    except Exception as ex:
        print(f"[PUSH TRIGGER ERROR] Failed to send incoming push: {ex}", file=sys.stderr)
        return 1


def trigger_cancel(call_uuid: str, reason: str = "caller_hangup") -> int:
    url = f"{GATEWAY_URL}/api/v1/internal/push/cancel"
    payload = {
        "call_uuid": call_uuid,
        "reason": reason,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            print(f"[CANCEL TRIGGER SUCCESS] {result.get('message')}", file=sys.stderr)
            return 0
    except Exception as ex:
        print(f"[CANCEL TRIGGER ERROR] Failed to send cancel push: {ex}", file=sys.stderr)
        return 1


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
