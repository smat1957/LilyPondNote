"""LilyPondNoteの登録済み利用者へ新しいパスワードを設定する管理ツール。"""

from getpass import getpass
import sys

from argon2 import PasswordHasher

from database import connection, initialize


def main() -> None:
    """対象利用者を確認し、新しいArgon2ハッシュだけをDBへ保存する。"""
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python reset_password.py EMAIL")

    # LilyPondNoteの登録処理と同じく、メールアドレスを小文字へ統一する。
    email = sys.argv[1].strip().lower()
    if not email:
        raise SystemExit("Email is required")

    new_password = getpass("New password: ")
    confirmation = getpass("New password (again): ")
    if not new_password:
        raise SystemExit("Password is required")
    if new_password != confirmation:
        raise SystemExit("Passwords do not match")

    # DBが未作成なら完成形を作る。既存DBではテーブル内容を変更しない。
    initialize()
    password_hash = PasswordHasher().hash(new_password)
    with connection() as database:
        cursor = database.execute(
            "UPDATE users SET password_hash = ? WHERE email = ?",
            (password_hash, email),
        )

    if cursor.rowcount != 1:
        raise SystemExit(f"User not found: {email}")

    print(f"Password updated: {email}")


if __name__ == "__main__":
    main()
