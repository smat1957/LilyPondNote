# LilyPondNote

LilyPondNoteは、LilyPondの楽譜ソース、処理手続き、生成したPDFを、階層を持つ
Note Packageとして管理するSwiftUIアプリです。macOS、iPad、iPhoneの3つの
ターゲットを提供します。

## 主な機能

- LilyPondソースと処理手続きの編集
- 構文強調配色と文字サイズの選択
- LilyPondによるPDF楽譜の生成と表示
- 楽譜グループおよび子・孫楽譜の階層管理
- 新規、複製、移調、既存ファイルのインポートによる派生楽譜の生成
- 五度圏に沿った移調元・移調先の選択と、移調先のオクターブ上下指定
- 楽譜データと任意の処理手続きファイルをroot楽譜または派生楽譜としてインポート
- Note Packageの新規作成、読込み、保存、名前を付けて保存
- 楽譜データとPDFの書き出し
- ローカルまたはリモートでの移調処理
- リモートサービスのFree、Standard、Pro契約プラン表示
- 日本語と英語の表示
- macOS・iPhone・iPad起動時の前回Note復元と段階別の読み込み表示
- iPhone・iPadの主要操作に、48ptのタップ領域を持つ半透明ボタンを採用

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
iPad用のPDFページ画像描画も`iPad`側に置き、共通の選択範囲補正は`Core`で共有します。

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

## 楽譜のインポート

macOS、iPad、iPhoneの各画面から、既存のLilyPond楽譜データをroot楽譜または
選択中の楽譜の子としてインポートできます。楽譜名はファイル名から設定され、
インポート前に編集できます。

処理手続きファイルは任意です。選択しなかった場合は、`score.ly`をincludeする
標準テンプレートを自動的に使用します。選択した処理手続きに
`\include "score.ly"`がない場合も内容を保持したままインポートし、編集画面での
修正を促す警告を表示します。

## PDF生成と移調

macOS版では、端末にインストールされたLilyPondを利用したローカルPDF生成に
対応します。リモートサービスへログインした場合は、サーバーでPDFを生成できます。
PDFタイトルには、コンパイル結果またはPDFから取得したLilyPondバージョンを
表示します。

移調処理のローカル／リモートは、派生楽譜の生成で「移調楽譜」を選んだときに表示される
「リモートで移調」スイッチで選択します。リモート移調だけがサービス側の利用回数として
記録されます。派生楽譜の移調元は楽譜内の最初の`\key`から取得し、移調先は属調を
初期値として表示します。移調元と移調先の選択欄は右端を揃え、移調先の右側で通常、
1オクターブ上、1オクターブ下を選択できます。

ローカル移調は、Xcodeプロジェクトが参照する隣接リポジトリ
`LilyPond_transpose/swift`の`LilyPondTransposeCore`をアプリのビルド時に組み込みます。
リモート移調はP2の`/opt/lilypond-transpose/P2/engine`へ配置したPython版を使用するため、
Swift版の再ビルドだけでは更新されません。Python版を更新した場合はP2へ8ファイルを
再配置し、`lilypond-transpose-p2.service`を再起動してください。

各プラットフォームでは、ウィンドウまたは画面を先に表示してから前回のNoteを復元し、
確認・コピー・楽譜を開く段階を読み込み表示で知らせます。iPadではPDFを左右にスワイプしてページを送り、
先頭ページで右へスワイプするとサイドバーを開けます。

iPhone・iPadのタイトルバーにある新規作成、編集、Note操作、楽譜操作には、
ライト／ダーク表示に追従する半透明のMaterialを使用します。主要ボタンは48ptの
操作領域を確保し、VoiceOver向けの日英アクセシビリティラベルを備えます。
iPhoneで楽譜を削除する操作はPDF表示画面の楽譜操作メニューに置き、実行前に
確認ダイアログを表示します。

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

## 動作確認

macOS、iPad、iPhoneの3ターゲットについて、ビルド後にアプリが起動することを
確認しています。端末やシミュレータの空き容量が少ない場合、Xcodeの生成物や
アプリの作業用Packageを保存できず、起動に影響することがあります。

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
