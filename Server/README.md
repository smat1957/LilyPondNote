# Raspberry Pi server

外部端末はP0のHTTPSリバースプロキシへ接続し、P1やP2へ直接接続しません。
P1はLilyPond用の一つのユーザーDBとJWT認証で、PDF生成と移調テキスト生成の両方を
認可します。

```text
iPad / iPhone -- HTTPS --> P0 -- user JWT --> P1:8001
                                               |-- internal token --> P2:8001 PDF生成
                                               `-- internal token --> P2:8002 移調テキスト生成
```

P1に必要な環境変数は`LILYPONDNOTE_AUTH_SECRET_KEY`、
`LILYPONDNOTE_API_TOKEN`、`LILYPONDNOTE_P2_TYPESET_URL`、
`LILYPONDNOTE_P2_TRANSPOSE_URL`です。P2のPDF APIと移調APIには同じ
`LILYPONDNOTE_API_TOKEN`を設定し、PDF APIには必要なら`LILYPOND_EXECUTABLE`も設定します。
P1とP2の`LILYPONDNOTE_API_TOKEN`は同じ値にし、JWT署名鍵とは別の値にします。

P1では仮想環境へ`requirements.txt`を導入後、`python useradd.py`で利用者を
登録します。P2にはOSのパッケージ管理機能でLilyPondを導入します。

環境設定は、同梱の`.env.example`を実際の`.env`ファイル名へコピーしてから、
秘密鍵、内部トークン、接続先を実環境に合わせて変更します。実際の`.env`ファイルは
Git管理対象外です。

```sh
cp P1/p1.env.example P1/p1.env
cp P2/lilypondnote-p2.env.example P2/lilypondnote-p2.env
cp P2/lilypond-transpose-p2.env.example P2/lilypond-transpose-p2.env
```

起動例:

```sh
uvicorn main:app --host 192.168.30.10 --port 8001
uvicorn app:app --host 192.168.40.10 --port 8001
uvicorn transpose_app:app --host 192.168.40.10 --port 8002
```

同梱の`lilypondnote-p1.service`と`lilypondnote-p2.service`は専用ユーザー、
`NoNewPrivileges`、読み取り専用システム領域を前提にしています。P2のTCP 8001と8002は
ファイアウォールでP1のIPアドレスからだけ許可してください。
移調APIは`LilyPond_transpose/python/main.py`を隔離して実行し、移調後の
`transposedSource`だけを返します。LilyPondを実行せず、PDFを生成しません。
P1の`usage.service`にはPDF生成を`typeset`、移調を`transpose`として記録します。
