"""SQLite database layer for SGT VoIP Push Gateway."""

import os
import sqlite3
from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict, Any

DEFAULT_DB_DIR = "/var/lib/sgt-push-gateway"
FALLBACK_DB_DIR = os.path.dirname(os.path.abspath(__file__))


def get_db_path() -> str:
    env_path = os.getenv("GATEWAY_DB_PATH")
    if env_path:
        return env_path

    if os.path.isdir(DEFAULT_DB_DIR) and os.access(DEFAULT_DB_DIR, os.W_OK):
        return os.path.join(DEFAULT_DB_DIR, "gateway.db")
    return os.path.join(FALLBACK_DB_DIR, "gateway.db")


def get_connection(db_path: Optional[str] = None) -> sqlite3.Connection:
    target = db_path or get_db_path()
    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    conn = sqlite3.connect(target, timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA foreign_keys=ON;")
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


def get_active_tokens_for_extension(
    extension: str,
    db_path: Optional[str] = None,
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
        return [dict(row) for row in cursor.fetchall()]


def create_or_update_call(
    call_uuid: str,
    caller_extension: str,
    callee_extension: str,
    caller_display_name: Optional[str] = None,
    asterisk_uniqueid: Optional[str] = None,
    status: str = "ringing",
    ttl_seconds: int = 30,
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
        return dict(row) if row else None
