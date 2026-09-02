"""LilyPondNote利用者を対話形式でP1のDBへ登録する管理用コマンド。"""

import getpass

from argon2 import PasswordHasher

from database import connection, initialize
from plans import validated_plan

# DBが未作成なら完成形のusers/usageテーブルを作る。
initialize()

# パスワードは端末へ表示せず、確認入力との一致も検査する。
email = input("Email: ").strip().lower()
password = getpass.getpass("Password: ")
confirmation = getpass.getpass("Password again: ")
requested_plan = input("Plan [free]: ").strip() or "free"
if not email or not password or password != confirmation:
    raise SystemExit("入力内容を確認してください。")
try:
    plan = validated_plan(requested_plan)
except ValueError as error:
    raise SystemExit(str(error)) from error
# 平文パスワードは保存せず、Argon2ハッシュだけをusersへ記録する。
with connection() as database:
    database.execute(
        "INSERT INTO users(email, password_hash, plan) VALUES(?, ?, ?)",
        (email, PasswordHasher().hash(password), plan),
    )
print("ユーザーを登録しました。")
