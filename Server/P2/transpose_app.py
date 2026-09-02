"""LilyPond移調テキストを生成するP2内部API。

LilyPond_transposeのCLIへ楽譜テキストを標準入力で渡し、移調後テキストだけを返す。
LilyPondコマンドは実行せず、PDFも生成しない。利用者JWTの検証はP1が担当し、
このAPIはP1と共有する固定内部トークンだけを検証する。
"""

import asyncio
import hmac
import os
import resource
import subprocess
import sys
from pathlib import Path
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field


app = FastAPI(title="LilyPond Transpose API", version="1.0.0")

# 移調CLIの配置先は試験時だけ環境変数で差し替えられる。
TRANSPOSE_MAIN = Path(
    os.getenv(
        "LILYPOND_TRANSPOSE_MAIN",
        "/opt/lilypond-transpose/P2/engine/main.py",
    )
)
MAX_REQUEST_BYTES = 4 * 1024 * 1024
MAX_SOURCE_CHARACTERS = 2_000_000
MAX_OUTPUT_BYTES = 4 * 1024 * 1024
MAX_ERROR_CHARACTERS = 4_000
TIMEOUT_SECONDS = 10
slots = asyncio.Semaphore(2)

# CLIが理解するLilyPond音名だけをAPIでも受け付ける。
PitchName = Literal[
    "ces", "c", "cis", "cisis", "ceses",
    "des", "d", "dis", "disis", "deses",
    "ees", "es", "e", "eis", "eisis", "eeses",
    "fes", "f", "fis", "fisis", "feses",
    "ges", "g", "gis", "gisis", "geses",
    "ases", "as", "a", "ais", "aisis", "aseses",
    "beses", "bes", "b", "bis",
]


class TransposeRequest(BaseModel):
    """移調元・移調先の音名と、変換対象のLilyPondテキスト。"""
    model_config = ConfigDict(extra="forbid")

    sourcePitch: PitchName
    destinationPitch: PitchName
    source: str = Field(min_length=1, max_length=MAX_SOURCE_CHARACTERS)


class TransposeResponse(BaseModel):
    """PDFではなく、移調済みLilyPondテキストだけを返す。"""
    transposedSource: str


@app.middleware("http")
async def limit_request_size(request: Request, call_next):
    """Content-Lengthが上限を超える要求を処理前に拒否する。"""
    content_length = request.headers.get("content-length")
    if content_length is not None:
        try:
            if int(content_length) > MAX_REQUEST_BYTES:
                return JSONResponse(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    content={"message": "Request is too large"},
                )
        except ValueError:
            return JSONResponse(
                status_code=status.HTTP_400_BAD_REQUEST,
                content={"message": "Invalid Content-Length"},
            )
    return await call_next(request)


def authorize(authorization: str | None = Header(default=None)) -> None:
    """P1と共有する内部トークンを一定時間比較で検証する。"""
    expected = os.environ.get("LILYPONDNOTE_API_TOKEN")
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="API token is not configured",
        )
    supplied = authorization.removeprefix("Bearer ") if authorization else ""
    if not supplied or not hmac.compare_digest(supplied, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
            headers={"WWW-Authenticate": "Bearer"},
        )


@app.get("/health")
def health():
    """移調CLIのmain.pyが配置済みか返す。"""
    return {
        "status": "ok" if TRANSPOSE_MAIN.is_file() else "unavailable",
        "transposeProgram": TRANSPOSE_MAIN.is_file(),
    }


@app.post(
    "/v1/transpose",
    response_model=TransposeResponse,
    dependencies=[Depends(authorize)],
)
async def transpose_source(request: TransposeRequest) -> TransposeResponse:
    """同時実行枠を確保し、ブロッキングするCLI処理を別スレッドで行う。"""
    if not TRANSPOSE_MAIN.is_file():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Transpose program is not installed",
        )
    async with slots:
        result = await asyncio.to_thread(run_transpose, request)
    return TransposeResponse(transposedSource=result)


def run_transpose(request: TransposeRequest) -> str:
    """シェルを介さず移調CLIを実行し、検査済みの標準出力を返す。"""
    try:
        result = subprocess.run(
            [
                sys.executable,
                str(TRANSPOSE_MAIN),
                request.sourcePitch,
                request.destinationPitch,
            ],
            cwd=TRANSPOSE_MAIN.parent,
            env={
                "HOME": "/nonexistent",
                "PATH": "/usr/bin:/bin",
                "LANG": "C.UTF-8",
                "PYTHONUTF8": "1",
            },
            input=request.source,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=TIMEOUT_SECONDS,
            check=False,
            preexec_fn=apply_limits,
        )
    except subprocess.TimeoutExpired as error:
        raise HTTPException(status_code=408, detail="Transpose timed out") from error
    except OSError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Transpose program could not be started",
        ) from error

    if result.returncode != 0:
        detail = result.stderr[-MAX_ERROR_CHARACTERS:].strip()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=detail or "Transpose failed",
        )

    encoded = result.stdout.encode("utf-8")
    if len(encoded) > MAX_OUTPUT_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Transposed source is too large",
        )
    if not result.stdout:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Transpose produced no output",
        )
    return result.stdout


def apply_limits() -> None:
    """移調CLI子プロセスへCPU・メモリ・出力等の上限を設定する。"""
    resource.setrlimit(resource.RLIMIT_CPU, (5, 6))
    resource.setrlimit(resource.RLIMIT_AS, (256_000_000, 256_000_000))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_OUTPUT_BYTES, MAX_OUTPUT_BYTES))
    resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))
