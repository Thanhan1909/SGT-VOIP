"""SQLite database layer for SGT VoIP Push Gateway with minimal file permissions."""

import os
import sqlite3
from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict, Any


def get_db_path() -> str:
    # 1. Check explicit environment override
    env_path = os.getenv("GATEWAY_DB_PATH")
    if env_path:
        return env_path

    # 2. Check systemd StateDirectory
    state_dir = os.getenv("STATE_DIRECTORY")
    if state_dir and os.path.isdir(state_dir) and os.access(state_dir, os.W_OK):
        return os.path.join(state_dir, "gateway.db")

    # 3. Check system standard /var/lib/sgt-push-gateway if writable
    default_dir = "/var/lib/sgt-push-gateway"
    if os.path.isdir(default_dir) and os.access(default_dir, os.W_OK):
        return os.path.join(default_dir, "gateway.db")

    # 4. Fallback to local push_gateway directory
    local_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(local_dir, "gateway.db")


def get_connection(db_path: Optional[str] = None) -> sqlite3.Connection:
    target = db_path or get_db_path()
    target_dir = os.path.dirname(os.path.abspath(target))
    try:
        os.makedirs(target_dir, mode=0o700, exist_ok=True)
        os.chmod(target_dir, 0o700)
    except Exception:
        pass

    conn = sqlite3.connect(target, timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA foreign_keys=ON;")

    try:
        if os.path.exists(target):
            os.chmod(target, 0o600)
    except Exception:
        pass

    return conn


def init_db(db_path: Optional[str] = None) -> None:
    """Initialize database tables and indexes."""
    with get_connection(db_path) as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS voip_device_tokens (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                extension TEXT NOT NULL,
                platform TEXT NOT NULL CHECK(platform IN ('android', 'ios')),
                device_id TEXT NOT NULL,
                push_token TEXT NOT NULL,
                push_environment TEXT NOT NULL DEFAULT 'production',
                app_version TEXT,
                enabled INTEGER NOT NULL DEFAULT 1,
                last_seen_at TIMESTAMP NOT NULL,
                revoked_at TIMESTAMP,
                UNIQUE(extension, device_id)
            );

            CREATE INDEX IF NOT EXISTS idx_tokens_ext_enabled
                ON voip_device_tokens(extension, enabled);

            CREATE TABLE IF NOT EXISTS voip_calls (
                call_uuid TEXT PRIMARY KEY,
                asterisk_uniqueid TEXT,
                caller_extension TEXT NOT NULL,
                caller_display_name TEXT,
                callee_extension TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('ringing', 'answered', 'declined', 'cancelled', 'expired', 'failed')),
                created_at TIMESTAMP NOT NULL,
                expires_at TIMESTAMP NOT NULL,
                updated_at TIMESTAMP NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_calls_callee_status
                ON voip_calls(callee_extension, status);

            CREATE TABLE IF NOT EXISTS web_push_subscriptions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                extension TEXT NOT NULL,
                device_id TEXT NOT NULL,
                endpoint TEXT NOT NULL UNIQUE,
                p256dh TEXT NOT NULL,
                auth TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at TIMESTAMP NOT NULL,
                updated_at TIMESTAMP NOT NULL,
                last_seen_at TIMESTAMP NOT NULL,
                last_success_at TIMESTAMP,
                failure_count INTEGER NOT NULL DEFAULT 0,
                revoked_at TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS idx_webpush_ext_enabled
                ON web_push_subscriptions(extension, enabled);
            """
        )
        conn.commit()


def upsert_device_token(
    extension: str,
    platform: str,
    device_id: str,
    push_token: str,
    push_environment: str = "production",
    app_version: Optional[str] = None,
    db_path: Optional[str] = None,
) -> None:
    now = datetime.now(timezone.utc).isoformat()
    with get_connection(db_path) as conn:
        conn.execute(
            """
            INSERT INTO voip_device_tokens (
                extension, platform, device_id, push_token,
                push_environment, app_version, enabled, last_seen_at, revoked_at
            ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, NULL)
            ON CONFLICT(extension, device_id) DO UPDATE SET
                platform=excluded.platform,
                push_token=excluded.push_token,
                push_environment=excluded.push_environment,
                app_version=excluded.app_version,
                enabled=1,
                last_seen_at=excluded.last_seen_at,
                revoked_at=NULL;
            """,
            (extension, platform, device_id, push_token, push_environment, app_version, now),
        )
        conn.commit()


def revoke_device_token(
    extension: str,
    device_id: str,
    db_path: Optional[str] = None,
) -> bool:
    now = datetime.now(timezone.utc).isoformat()
    with get_connection(db_path) as conn:
        cursor = conn.execute(
            """
            UPDATE voip_device_tokens
            SET enabled=0, revoked_at=?
            WHERE extension=? AND device_id=?;
            """,
            (now, extension, device_id),
        )
        conn.commit()
        return cursor.rowcount > 0


def disable_push_token(
    push_token: str,
    db_path: Optional[str] = None,
) -> int:
    """Disable invalid or expired push token across all extensions/devices."""
    now = datetime.now(timezone.utc).isoformat()
    with get_connection(db_path) as conn:
        cursor = conn.execute(
            """
            UPDATE voip_device_tokens
            SET enabled=0, revoked_at=?
            WHERE push_token=?;
            """,
            (now, push_token),
        )
        conn.commit()
        return cursor.rowcount


def mask_token(token: str) -> str:
    """Redact raw token to prevent sensitive data leakage."""
    if not token or len(token) <= 10:
        return "***"
    return f"{token[:6]}...{token[-4:]}"


def get_active_tokens_for_extension(
    extension: str,
    db_path: Optional[str] = None,
    redact_tokens: bool = False,
) -> List[Dict[str, Any]]:
    with get_connection(db_path) as conn:
        cursor = conn.execute(
            """
            SELECT id, extension, platform, device_id, push_token,
                   push_environment, app_version, last_seen_at
            FROM voip_device_tokens
            WHERE extension=? AND enabled=1
            ORDER BY last_seen_at DESC;
            """,
            (extension,),
        )
        rows = [dict(row) for row in cursor.fetchall()]
        if redact_tokens:
            for r in rows:
                r["push_token"] = mask_token(r["push_token"])
        return rows


def create_or_update_call(
    call_uuid: str,
    caller_extension: str,
    callee_extension: str,
    caller_display_name: Optional[str] = None,
    asterisk_uniqueid: Optional[str] = None,
    status: str = "ringing",
    ttl_seconds: int = 45,
    db_path: Optional[str] = None,
) -> Dict[str, Any]:
    now = datetime.now(timezone.utc)
    now_str = now.isoformat()
    expires_at = (now + timedelta(seconds=ttl_seconds)).isoformat()

    with get_connection(db_path) as conn:
        conn.execute(
            """
            INSERT INTO voip_calls (
                call_uuid, asterisk_uniqueid, caller_extension,
                caller_display_name, callee_extension, status,
                created_at, expires_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(call_uuid) DO UPDATE SET
                asterisk_uniqueid=COALESCE(excluded.asterisk_uniqueid, voip_calls.asterisk_uniqueid),
                caller_display_name=COALESCE(excluded.caller_display_name, voip_calls.caller_display_name),
                status=excluded.status,
                updated_at=excluded.updated_at;
            """,
            (
                call_uuid,
                asterisk_uniqueid,
                caller_extension,
                caller_display_name,
                callee_extension,
                status,
                now_str,
                expires_at,
                now_str,
            ),
        )
        conn.commit()

    return {
        "call_uuid": call_uuid,
        "caller_extension": caller_extension,
        "caller_display_name": caller_display_name,
        "callee_extension": callee_extension,
        "status": status,
        "created_at": now_str,
        "expires_at": expires_at,
    }


def update_call_status(
    call_uuid: str,
    status: str,
    db_path: Optional[str] = None,
) -> bool:
    now = datetime.now(timezone.utc).isoformat()
    with get_connection(db_path) as conn:
        cursor = conn.execute(
            """
            UPDATE voip_calls
            SET status=?, updated_at=?
            WHERE call_uuid=?;
            """,
            (status, now, call_uuid),
        )
        conn.commit()
        return cursor.rowcount > 0


def get_call(
    call_uuid: str,
    db_path: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    now = datetime.now(timezone.utc)
    now_str = now.isoformat()
    with get_connection(db_path) as conn:
        cursor = conn.execute(
            """
            SELECT call_uuid, asterisk_uniqueid, caller_extension,
                   caller_display_name, callee_extension, status,
                   created_at, expires_at, updated_at
            FROM voip_calls
            WHERE call_uuid=?;
            """,
            (call_uuid,),
        )
        row = cursor.fetchone()
        if not row:
            return None
        call = dict(row)

        # Check call expiration against ring deadline
        expires_at_str = call.get("expires_at")
        is_expired = False
        if expires_at_str:
            try:
                expires_at = datetime.fromisoformat(expires_at_str)
                if expires_at.tzinfo is None:
                    expires_at = expires_at.replace(tzinfo=timezone.utc)
                if now > expires_at:
                    is_expired = True
            except Exception:
                pass

        if is_expired and call["status"] == "ringing":
            conn.execute(
                """
                UPDATE voip_calls
                SET status='expired', updated_at=?
                WHERE call_uuid=?;
                """,
                (now_str, call_uuid),
            )
            conn.commit()
            call["status"] = "expired"

        call["is_expired"] = is_expired
        call["is_ringing"] = (call["status"] == "ringing" and not is_expired)
        return call


def mask_endpoint(endpoint: str) -> str:
    """Redact raw subscription endpoint for safe logging."""
    if not endpoint:
        return "***"
    try:
        from urllib.parse import urlparse
        parsed = urlparse(endpoint)
        path = parsed.path
        masked_path = f"...{path[-8:]}" if len(path) > 8 else path
        return f"{parsed.scheme}://{parsed.netloc}{masked_path}"
    except Exception:
        return f"...{endpoint[-10:]}" if len(endpoint) > 10 else "***"


def upsert_web_push_subscription(
    extension: str,
    device_id: str,
    endpoint: str,
    p256dh: str,
    auth: str,
    db_path: Optional[str] = None,
) -> None:
    """Idempotently register or update a Web Push subscription."""
    now = datetime.now(timezone.utc).isoformat()
    with get_connection(db_path) as conn:
        conn.execute(
            """
            INSERT INTO web_push_subscriptions (
                extension, device_id, endpoint, p256dh, auth,
                enabled, created_at, updated_at, last_seen_at, failure_count, revoked_at
            ) VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, 0, NULL)
            ON CONFLICT(endpoint) DO UPDATE SET
                extension=excluded.extension,
                device_id=excluded.device_id,
                p256dh=excluded.p256dh,
                auth=excluded.auth,
                enabled=1,
                updated_at=excluded.updated_at,
                last_seen_at=excluded.last_seen_at,
                failure_count=0,
                revoked_at=NULL;
            """,
            (extension, device_id, endpoint, p256dh, auth, now, now, now),
        )
        conn.commit()


def revoke_web_push_subscription(
    endpoint: str,
    db_path: Optional[str] = None,
) -> bool:
    """Revoke a Web Push subscription when user unsubscribes."""
    now = datetime.now(timezone.utc).isoformat()
    with get_connection(db_path) as conn:
        cursor = conn.execute(
            """
            UPDATE web_push_subscriptions
            SET enabled=0, revoked_at=?
            WHERE endpoint=?;
            """,
            (now, endpoint),
        )
        conn.commit()
        return cursor.rowcount > 0


def disable_web_push_subscription(
    endpoint: str,
    db_path: Optional[str] = None,
) -> int:
    """Disable invalid or unregistered Web Push endpoint (e.g. 404/410)."""
    now = datetime.now(timezone.utc).isoformat()
    with get_connection(db_path) as conn:
        cursor = conn.execute(
            """
            UPDATE web_push_subscriptions
            SET enabled=0, failure_count=failure_count+1, revoked_at=?
            WHERE endpoint=?;
            """,
            (now, endpoint),
        )
        conn.commit()
        return cursor.rowcount


def get_active_web_push_subscriptions(
    extension: str,
    db_path: Optional[str] = None,
    redact: bool = False,
) -> List[Dict[str, Any]]:
    """Query active Web Push subscriptions for an extension."""
    with get_connection(db_path) as conn:
        cursor = conn.execute(
            """
            SELECT id, extension, device_id, endpoint, p256dh, auth,
                   created_at, updated_at, last_seen_at, failure_count
            FROM web_push_subscriptions
            WHERE extension=? AND enabled=1
            ORDER BY last_seen_at DESC;
            """,
            (extension,),
        )
        rows = [dict(row) for row in cursor.fetchall()]
        if redact:
            for r in rows:
                r["endpoint"] = mask_endpoint(r["endpoint"])
                r["p256dh"] = mask_token(r["p256dh"])
                r["auth"] = "***"
        return rows
