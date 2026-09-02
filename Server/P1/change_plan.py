"""既存ユーザーのLilyPondNoteプランを変更する管理コマンド。"""

import argparse

from database import connection, initialize
from plans import validated_plan


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("email")
    parser.add_argument("plan")
    arguments = parser.parse_args()
    plan = validated_plan(arguments.plan)
    email = arguments.email.strip().lower()
    initialize()
    with connection() as database:
        user = database.execute(
            "SELECT plan FROM users WHERE email = ?", (email,)
        ).fetchone()
        if user is None:
            raise SystemExit(f"User not found: {email}")
        database.execute(
            "UPDATE users SET plan = ? WHERE email = ?", (plan, email)
        )
    print(f"Plan changed: {email}: {user['plan']} -> {plan}")


if __name__ == "__main__":
    main()
