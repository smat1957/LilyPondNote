"""LilyPondNote P1のユーザーDBと利用履歴DBを管理する。"""

import sqlite3
from contextlib import contextmanager
from pathlib import Path

DB_PATH = Path(__file__).with_name("lilypondnote.db")


@contextmanager
def connection():
    database = sqlite3.connect(DB_PATH)
    database.row_factory = sqlite3.Row
    try:
        yield database
        database.commit()
    except Exception:
        database.rollback()
        raise
    finally:
        database.close()


def initialize() -> None:
    """新規DBを作成し、旧DBにはサービス種別列を追加する。"""
    with connection() as database:
        database.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY,
                email TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                plan TEXT NOT NULL DEFAULT 'free'
            );
            CREATE TABLE IF NOT EXISTS usage (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id),
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                compile_seconds REAL NOT NULL,
                input_bytes INTEGER NOT NULL,
                success INTEGER NOT NULL,
                service TEXT NOT NULL DEFAULT 'typeset'
                    CHECK(service IN ('typeset', 'transpose'))
            );
            """
        )
        # 既存DBはCREATE TABLE IF NOT EXISTSだけでは列が増えないため、
        # PRAGMAで確認してから移行する。既存履歴はPDF生成として扱う。
        columns = {
            row["name"]
            for row in database.execute("PRAGMA table_info(usage)").fetchall()
        }
        if "service" not in columns:
            database.execute(
                """ALTER TABLE usage ADD COLUMN service TEXT NOT NULL
                   DEFAULT 'typeset'
                   CHECK(service IN ('typeset', 'transpose'))"""
            )
        user_columns = {
            row["name"]
            for row in database.execute("PRAGMA table_info(users)").fetchall()
        }
        if "plan" not in user_columns:
            database.execute(
                "ALTER TABLE users ADD COLUMN plan TEXT NOT NULL DEFAULT 'free'"
            )
