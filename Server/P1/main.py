"""LilyPondNote P1 認証・API中継サーバー。

利用者のパスワードを検証してJWTを発行し、認証済みの要求だけをP2へ送る。
PDF生成と移調テキスト生成は同じ利用者DB・JWT・月間上限を共有するが、
利用履歴にはサービス種別を分けて記録する。
"""

import os
import time
from datetime import datetime, timedelta, timezone
from typing import Literal

import jwt
import requests
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel, ConfigDict, Field

from database import connection, initialize
from plans import PLAN_MONTHLY_LIMITS

app = FastAPI(title="LilyPondNote Authentication API", version="1.0.0")
initialize()

SECRET_KEY = os.environ["LILYPONDNOTE_AUTH_SECRET_KEY"]
P2_API_TOKEN = os.environ["LILYPONDNOTE_API_TOKEN"]
P2_TYPESET_URL = os.environ["LILYPONDNOTE_P2_TYPESET_URL"]
P2_TRANSPOSE_URL = os.environ["LILYPONDNOTE_P2_TRANSPOSE_URL"]
MAX_REQUEST_BYTES = 8 * 1024 * 1024
P2_TIMEOUT_SECONDS = 45
JWT_ALGORITHM = "HS256"
JWT_MINUTES = 30
SERVICE_NAME = "lilypondnote"
password_hasher = PasswordHasher()
oauth2 = OAuth2PasswordBearer(tokenUrl="login")


# ---------------------------------------------------------------------------
# APIの入出力モデル
# ---------------------------------------------------------------------------

class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(min_length=1, max_length=320)
    password: str = Field(min_length=1, max_length=1024)
    service: Literal["lilypondnote"]


class CompileRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    scoreID: str = Field(min_length=36, max_length=36)
    processingProgram: str = Field(min_length=1, max_length=2_000_000)
    scoreData: str = Field(min_length=1, max_length=2_000_000)


class TransposeRequest(BaseModel):
    """LilyPond_transposeへ渡す楽譜テキストと移調元・移調先。"""

    model_config = ConfigDict(extra="forbid")
    sourcePitch: str = Field(min_length=1, max_length=16)
    destinationPitch: str = Field(min_length=1, max_length=16)
    source: str = Field(min_length=1, max_length=2_000_000)


@app.middleware("http")
async def limit_request_size(request: Request, call_next):
    """Content-Lengthが上限を超える要求を処理前に拒否する。"""
    value = request.headers.get("content-length")
    if value is not None:
        try:
            if int(value) > MAX_REQUEST_BYTES:
                return JSONResponse(status_code=413, content={"message": "Request too large"})
        except ValueError:
            return JSONResponse(status_code=400, content={"message": "Invalid Content-Length"})
    return await call_next(request)


def current_user(token: str = Depends(oauth2)):
    """JWTを検証し、現在も有効なユーザー行を返す。"""
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[JWT_ALGORITHM],
            audience=SERVICE_NAME,
        )
        user_id = int(payload["sub"])
    except Exception as error:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from error
    with connection() as database:
        user = database.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if user is None or user["status"] != "active":
        raise HTTPException(status_code=403, detail="User is unavailable")
    return user


def monthly_usage(user_id: int, service: str | None = None) -> int:
    """当月の利用回数を返す。service指定時はサービス別に数える。"""
    with connection() as database:
        sql = """SELECT COUNT(*) AS count FROM usage WHERE user_id = ?
                 AND strftime('%Y-%m', created_at) = strftime('%Y-%m', 'now')"""
        parameters: tuple[object, ...] = (user_id,)
        if service is not None:
            sql += " AND service = ?"
            parameters += (service,)
        row = database.execute(sql, parameters).fetchone()
    return int(row["count"])


def record_usage(
    user_id: int,
    service: str,
    started: float,
    input_bytes: int,
    success: bool,
) -> None:
    """処理時間、入力サイズ、成否、サービス種別を1行記録する。"""
    with connection() as database:
        database.execute(
            """INSERT INTO usage(
                   user_id, compile_seconds, input_bytes, success, service
               ) VALUES(?,?,?,?,?)""",
            (
                user_id,
                time.monotonic() - started,
                input_bytes,
                int(success),
                service,
            ),
        )


def plan_limit(user) -> int:
    """未知の旧データもFreeとして安全に扱う。"""
    return PLAN_MONTHLY_LIMITS.get(user["plan"], PLAN_MONTHLY_LIMITS["free"])


def ensure_monthly_limit(user) -> None:
    used = monthly_usage(user["id"])
    limit = plan_limit(user)
    if used >= limit:
        raise HTTPException(
            status_code=429,
            detail={
                "message": "Monthly service limit exceeded",
                "plan": user["plan"],
                "limit": limit,
                "used": used,
            },
        )


def post_to_p2(url: str, payload: dict) -> dict:
    """内部トークンを付けてP2へPOSTし、正常なJSONだけを返す。"""
    try:
        response = requests.post(
            url,
            headers={"Authorization": f"Bearer {P2_API_TOKEN}"},
            json=payload,
            timeout=P2_TIMEOUT_SECONDS,
        )
    except requests.RequestException as error:
        raise HTTPException(status_code=502, detail="P2 connection failed") from error
    if response.status_code != 200:
        raise HTTPException(status_code=502, detail=response.text)
    try:
        result = response.json()
    except ValueError as error:
        raise HTTPException(status_code=502, detail="P2 returned invalid JSON") from error
    if not isinstance(result, dict):
        raise HTTPException(status_code=502, detail="P2 returned unexpected JSON")
    return result


# ---------------------------------------------------------------------------
# 公開API：認証と利用者情報
# ---------------------------------------------------------------------------


@app.post("/login")
def login(request: LoginRequest):
    """メールアドレスとパスワードを検証して短寿命JWTを発行する。"""
    email = request.email.strip().lower()
    with connection() as database:
        user = database.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
    try:
        valid = user is not None and password_hasher.verify(
            user["password_hash"], request.password
        )
    except VerifyMismatchError:
        valid = False
    if not valid or user["status"] != "active":
        raise HTTPException(status_code=401, detail="Invalid email or password")
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {"sub": str(user["id"]), "email": email, "aud": SERVICE_NAME, "iat": now,
         "exp": now + timedelta(minutes=JWT_MINUTES)},
        SECRET_KEY,
        algorithm=JWT_ALGORITHM,
    )
    return {"access_token": token, "token_type": "bearer"}


@app.get("/me")
def me(user=Depends(current_user)):
    """利用者情報と当月利用回数の合計・サービス別内訳を返す。"""
    return {
        "service": SERVICE_NAME,
        "id": user["id"], "email": user["email"], "status": user["status"],
        "plan": user["plan"],
        "used": monthly_usage(user["id"]),
        "usageByService": {
            "typeset": monthly_usage(user["id"], "typeset"),
            "transpose": monthly_usage(user["id"], "transpose"),
        },
        "limit": plan_limit(user),
    }


# ---------------------------------------------------------------------------
# 公開API：PDF生成と移調テキスト生成
# ---------------------------------------------------------------------------

@app.post("/compile")
def compile_score(request: CompileRequest, user=Depends(current_user)):
    """P2のLilyPondでPDFを生成し、typesetとして履歴へ記録する。"""
    ensure_monthly_limit(user)
    started = time.monotonic()
    success = False
    input_bytes = len(request.processingProgram.encode()) + len(request.scoreData.encode())
    try:
        result = post_to_p2(P2_TYPESET_URL, request.model_dump())
        success = True
        return result
    finally:
        record_usage(user["id"], "typeset", started, input_bytes, success)


@app.post("/transpose")
def transpose_score(request: TransposeRequest, user=Depends(current_user)):
    """P2で楽譜テキストを移調し、PDFへ変換せずテキストを返す。"""
    ensure_monthly_limit(user)
    started = time.monotonic()
    input_bytes = len(request.source.encode("utf-8"))
    success = False
    try:
        result = post_to_p2(P2_TRANSPOSE_URL, request.model_dump())
        if not isinstance(result.get("transposedSource"), str):
            raise HTTPException(status_code=502, detail="P2 returned no transposed source")
        success = True
        return {"transposedSource": result["transposedSource"]}
    finally:
        record_usage(user["id"], "transpose", started, input_bytes, success)


@app.exception_handler(HTTPException)
async def http_error(_request: Request, error: HTTPException):
    """クライアントが扱いやすいmessage形式へHTTP例外を統一する。"""
    content = error.detail if isinstance(error.detail, dict) else {
        "message": str(error.detail)
    }
    return JSONResponse(
        status_code=error.status_code,
        content=content,
        headers=error.headers,
    )
