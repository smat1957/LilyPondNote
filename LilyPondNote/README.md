# LilyPondNote

SwiftUI で作成した macOS・iPad・iPhone 向けのマルチターゲットアプリです。

## ターゲット

- `LilyPondNote-macOS`
- `LilyPondNote-iPad`
- `LilyPondNote-iPhone`

## ソース構成

- `Core`: 3プラットフォームで共通利用する、プラットフォーム非依存のロジックとデータ
- `macOS`: macOS固有のアプリ入口とUI
- `iPad`: iPad固有のアプリ入口とUI
- `iPhone`: iPhone固有のアプリ入口とUI

各ターゲットは `Core` と、それぞれに対応するプラットフォームフォルダだけを使用します。
プラットフォーム分岐のための条件コンパイルは使用しません。

## Note Package

各ScoreはPDF、楽譜データ、処理プログラムの3点セットです。子Scoreも同じ構造を
再帰的に持ちます。

```text
ノート名/
├── note.json
└── Scores/
    └── Score UUID/
        ├── score.ly
        ├── main.ly
        ├── output.pdf
        └── Scores/
            └── 子Score UUID/
                ├── score.ly
                ├── main.ly
                ├── output.pdf
                └── Scores/
```

各`main.ly`は、同じScoreフォルダの`score.ly`だけをincludeします。親子関係による
暗黙のincludeや継承は行いません。

## 楽譜のインポート

既存のLilyPond楽譜データと任意の処理手続きを、root Scoreまたは選択中のScoreの
子としてインポートできます。処理手続きを選択しない場合は標準テンプレートを使用します。
選択した処理手続きに`\include "score.ly"`がない場合は、内容を保持したまま
インポートし、編集画面での修正を促します。

Xcodeで `LilyPondNote.xcodeproj` を開き、実行するターゲットとデバイスを選択してください。

## 起動時の復元と画面

最後に開いた、または保存したPackageへのbookmarkを保存し、次回起動時に
そのPackageを復元します。bookmarkがない初回起動時や、Packageを復元
できない場合は、楽譜が0個の「名称未設定」Noteを表示します。

主画面の編集ボタンから、次の3タブを持つ編集画面を開きます。

- 楽譜編集
- 処理手続き編集
- エラー表示

iPadとmacOSではScore一覧とPDFを2カラムで表示し、iPhoneではPDFを優先して
表示します。iPadのPDFは1ページ単位で停止する左右スワイプで移動し、Scoreタイトルバーに現在ページと総ページ数を
表示します。iPadとiPhoneの編集画面は全画面で開き、上部の操作列とセグメント型タブ、
ダーク背景のコード編集領域で構成します。現段階では検索と行番号表示は持ちません。

保存では2つのソースを保存し、PDFが再生成待ちであることを管理します。PDF生成に
成功した場合だけソースとPDFを更新し、失敗した場合は既存PDFを維持してエラータブに
ログを表示します。キャンセルでは編集画面の未保存内容を破棄します。
