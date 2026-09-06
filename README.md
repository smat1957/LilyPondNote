# LilyPondNote

LilyPondNoteは、LilyPondの楽譜ソース、処理手続き、生成したPDFを、階層を持つ
Note Packageとして管理するSwiftUIアプリです。macOS、iPad、iPhoneの3つの
ターゲットを提供します。

## 主な機能

- LilyPondソースと処理手続きの編集
- 構文強調配色と文字サイズの選択
- LilyPondによるPDF楽譜の生成と表示
- 楽譜グループおよび子・孫楽譜の階層管理
- 新規、複製、移調による派生楽譜の生成
- Note Packageの新規作成、読込み、保存、名前を付けて保存
- 楽譜データとPDFの書き出し
- ローカルまたはリモートでの移調処理
- リモートサービスのFree、Standard、Pro契約プラン表示
- 日本語と英語の表示

## 対応ターゲット

- `LilyPondNote-macOS`
- `LilyPondNote-iPad`
- `LilyPondNote-iPhone`

各ターゲットは、共通の`Core`と、それぞれに対応するプラットフォームフォルダを
使用します。プラットフォームを切り替えるための`#if os(...)`による条件分岐は
使用しません。

## ディレクトリ構成

```text
LilyPondNote/
├── README.md                 このファイル
├── LilyPondNote/             Appleプラットフォーム向けアプリ
│   ├── Core/                 全ターゲットで共有するモデルと処理
│   ├── macOS/                macOS固有のUIとローカルコンパイラ
│   ├── iPad/                 iPad固有のUI
│   ├── iPhone/               iPhone固有のUI
│   └── LilyPondNote.xcodeproj
└── Server/                   リモートサービス関連資料
```

`Core`には、Note Packageの読み書き、楽譜階層、PDF生成状態、移調、リモート認証
などの共通ロジックを置きます。AppKit、UIKit、PDF表示操作などの
プラットフォーム固有処理は、`macOS`、`iPad`、`iPhone`の各フォルダに置きます。

詳しいアプリ構成は[アプリREADME](LilyPondNote/README.md)、サーバー構成は
[サーバーREADME](Server/README.md)を参照してください。

## Note Package

「保存」では保存先フォルダを選び、その中に現在のNote名と同じ名前の
`.lilypondnote` Packageを作成します。「名前を付けて保存」では、新しいNote名を
入力してから保存先フォルダを選び、同じ形式のPackageを作成します。

```text
Note名.lilypondnote/
├── note.json
└── Scores/
    └── Score UUID/
        ├── score.ly
        ├── main.ly
        ├── output.pdf
        ├── compile.log
        └── Scores/
            └── 子Score UUID/
                ├── score.ly
                ├── main.ly
                ├── output.pdf
                ├── compile.log
                └── Scores/
```

各楽譜は独立した`score.ly`、`main.ly`、PDF、コンパイルログを持ちます。
親子関係による暗黙のLilyPondソース継承は行いません。

## PDF生成と移調

macOS版では、端末にインストールされたLilyPondを利用したローカルPDF生成に
対応します。リモートサービスへログインした場合は、サーバーでPDFを生成できます。
PDFタイトルには、コンパイル結果またはPDFから取得したLilyPondバージョンを
表示します。

移調処理は設定からローカルまたはリモートを選択できます。リモート移調だけが
サービス側の利用回数として記録されます。

## 開発環境

本リポジトリと同じ親ディレクトリに、移調ライブラリのリポジトリを配置します。
Xcodeプロジェクトは次のローカルSwift Packageを参照します。

```text
Git/
├── LilyPondNote/
└── LilyPond_transpose/
    └── swift/
```

プロジェクトを開くには、次のファイルをXcodeで開きます。

```text
LilyPondNote/LilyPondNote.xcodeproj
```

Xcode上で実行するターゲットと端末を選択してビルドしてください。

## リモートサービス

リモート構成では、クライアントは公開入口P0へHTTPS接続し、P1が利用者認証、
契約プラン、利用回数を管理します。P2は内部APIとしてPDF生成と移調を担当します。
構成、環境変数、起動例は[Server/README.md](Server/README.md)に記載しています。

認証トークン、秘密鍵、実際のメールアドレス、内部サーバーのアドレスなどは、
GitHubへcommitしないでください。

## Git管理時の注意

`.gitignore`では、`DerivedData`、`xcuserdata`、`.DS_Store`、ユーザー固有の
Xcode状態を除外しています。commit前には、認証情報や端末固有設定が含まれて
いないことを確認してください。
