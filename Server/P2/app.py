"""LilyPondNote P2 PDF生成サーバー。

P1から内部トークン付きで受け取った2個のLilyPondソースを一時領域へ書き、
LilyPondを制限付きで実行してPDFとログを返す。利用者認証やDB管理は行わない。
"""

import asyncio
import base64
import os
import resource
import subprocess
import tempfile
from pathlib import Path
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field

app = FastAPI(title="LilyPondNote Typesetting API", version="1.0.0")
LILYPOND = os.getenv("LILYPOND_EXECUTABLE", "/usr/bin/lilypond")
MAX_LOG_CHARACTERS = 200_000
TIMEOUT_SECONDS = 40
slots = asyncio.Semaphore(2)


# ---------------------------------------------------------------------------
# APIの入出力モデル
# ---------------------------------------------------------------------------

class TypesetRequest(BaseModel):
    """1回のPDF生成に必要な楽譜ID、処理用ソース、楽譜本体。"""
    model_config = ConfigDict(extra="forbid")
    scoreID: UUID
    processingProgram: str = Field(min_length=1, max_length=2_000_000)
    scoreData: str = Field(min_length=1, max_length=2_000_000)


def authorize(authorization: str | None = Header(default=None)) -> None:
    """P1と共有する固定内部トークンを検証する。"""
    expected = os.environ.get("LILYPONDNOTE_API_TOKEN")
    if not expected:
        raise HTTPException(status_code=503, detail="API token is not configured")
    if authorization != f"Bearer {expected}":
        raise HTTPException(status_code=401, detail="Unauthorized")


@app.get("/health")
def health():
    """LilyPond実行ファイルが利用可能か返す。"""
    return {"status": "ok", "lilypond": os.access(LILYPOND, os.X_OK)}


@app.post("/v1/typeset", dependencies=[Depends(authorize)])
async def typeset(request: TypesetRequest):
    """入力検査後、同時実行枠を確保してPDF生成を開始する。"""
    if not os.access(LILYPOND, os.X_OK):
        raise HTTPException(status_code=503, detail="LilyPond executable not found")
    if not includes_local_score(request.processingProgram):
        raise HTTPException(status_code=422, detail="main.ly must include score.ly")
    async with slots:
        return await asyncio.to_thread(compile_score, request)


def includes_local_score(program: str) -> bool:
    """処理用ソースが同じ一時領域のscore.lyを読み込むことを確認する。"""
    return any(
        line.strip() == '\\include "score.ly"'
        for line in program.splitlines()
    )


def compile_score(request: TypesetRequest):
    """一時領域でLilyPondを実行し、PDFをBase64文字列として返す。"""
    with tempfile.TemporaryDirectory(prefix="lilypondnote-") as temporary:
        directory = Path(temporary)
        (directory / "main.ly").write_text(request.processingProgram, encoding="utf-8")
        (directory / "score.ly").write_text(request.scoreData, encoding="utf-8")
        try:
            result = subprocess.run(
                [LILYPOND, "--pdf", "-o", "output", "main.ly"],
                cwd=directory,
                env={"HOME": temporary, "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                timeout=TIMEOUT_SECONDS,
                check=False,
                preexec_fn=apply_limits,
            )
        except subprocess.TimeoutExpired as error:
            raise HTTPException(status_code=408, detail="LilyPond timed out") from error
        log = result.stdout[-MAX_LOG_CHARACTERS:]
        if result.returncode != 0:
            raise HTTPException(status_code=422, detail=log)
        pdf = directory / "output.pdf"
        if not pdf.is_file():
            raise HTTPException(status_code=422, detail="PDF was not produced")
        return {"pdfBase64": base64.b64encode(pdf.read_bytes()).decode(), "log": log}


def apply_limits():
    """LilyPond子プロセスへCPU・メモリ・出力等の上限を設定する。"""
    resource.setrlimit(resource.RLIMIT_CPU, (35, 40))
    resource.setrlimit(resource.RLIMIT_AS, (1_500_000_000, 1_500_000_000))
    resource.setrlimit(resource.RLIMIT_FSIZE, (50_000_000, 50_000_000))
    resource.setrlimit(resource.RLIMIT_NOFILE, (256, 256))
