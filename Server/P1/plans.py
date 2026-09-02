"""LilyPondNoteで利用できるプランと月間サービス上限。"""

PLAN_MONTHLY_LIMITS = {
    "free": 50,
    "standard": 1_000,
    "pro": 5_000,
}


def validated_plan(value: str) -> str:
    plan = value.strip().lower()
    if plan not in PLAN_MONTHLY_LIMITS:
        allowed = ", ".join(PLAN_MONTHLY_LIMITS)
        raise ValueError(f"Plan must be one of: {allowed}")
    return plan
