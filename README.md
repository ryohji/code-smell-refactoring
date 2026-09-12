# code-smell-refactoring

コードの臭いを検出して優先度づけし、**テストで保護してから小さなステップでグリーンを保ちつつ**リファクタリングするための手順書。『ソフトウェア実装改善ガイド』の方法論を実行可能な形にしたもの。

エージェント製品に依存しない。中身はすべて Markdown とシェルスクリプトで、`SKILL.md` を読ませれば任意のコーディングエージェントで使える。

## ファイル構成

```
code-smell-refactoring/
├── SKILL.md                        ← 中核。全フェーズの流れ。まずこれを読む
├── AGENTS.md                       → SKILL.md への転送（Codex CLI ほか）
├── README.md                       ← この説明
├── .github/
│   └── copilot-instructions.md     → SKILL.md への転送（GitHub Copilot）
├── references/
│   ├── capabilities.md             実行方式の判定（層 1／層 2）
│   ├── smells.md                   臭い 10 分類・優先度マトリクス
│   ├── refactoring-loop.md         保護 → 変更 → 検証の 3 ステップ
│   ├── patterns.md                 臭い別の具体手順（1 行 = 1 コミット）
│   ├── dependency-breaking.md      テストのための依存の切りはなし
│   ├── task-prompts.md             各ステップの指示文（5 種）
│   └── plan-template.md            REFACTORING_PLAN.md の形式
└── scripts/
    ├── verify_harness.sh           テスト実行手段の検出（フェーズ 0）
    └── hotspots.sh                 git 履歴から変更頻度を集計（フェーズ 1）
```

## 導入方法

### Claude Code

```
~/.claude/skills/code-smell-refactoring/     # 個人用
<repo>/.claude/skills/code-smell-refactoring/  # リポジトリ共有
```

置くだけで `SKILL.md` の `description` にもとづいて自動起動する。`/code-smell-refactoring` で明示的に呼びだすこともできる。

### GitHub Copilot

リポジトリのルートに置き、`.github/copilot-instructions.md` を配置する（このディレクトリに同梱のものをコピーするか、リポジトリ既存のファイルに転送行を追記する）。

Copilot はサブタスクを起動できないので**層 2** として動く。`references/capabilities.md` の層 2 の手順に従い、ステップごとにセッションを区切る。

### Codex CLI

リポジトリのルート（または対象ディレクトリ）に `AGENTS.md` を置く。Codex は起動時に `AGENTS.md` を読むので、そこから `SKILL.md` へ誘導する。

### Cursor / Cline / その他

多くのツールは「ルールファイル」の仕組みを持っている（`.cursor/rules/`、`.clinerules` など）。そこに `AGENTS.md` と同じ内容の転送行を書く。仕組みがない場合は、会話の冒頭で次のように指示すれば足りる。

```
skills/code-smell-refactoring/SKILL.md を読んで、その手順に従って
src/parser 以下をリファクタリングしてください。
```

## 使いはじめ方

対象を指定して依頼する。

```
src/parser 以下のコードの臭いを分析して、優先度をつけて報告してください。
```

臭いの一覧と優先度が `REFACTORING_PLAN.md` に書きだされる。内容に合意したら着手を指示する。

```
REFACTORING_PLAN.md の #1 から順に修正してください。
```

## 前提

- **git リポジトリであること。** 1 コミット 1 変更でグリーンを刻む前提。`hotspots.sh` も git 履歴を使う
- **テストが 1 コマンドで実行できること。** ない場合はフェーズ 0 でフレームワークを整える
- **着手時点でテストがグリーンであること。** レッドの状態では「自分が壊したか」を判定できないので、先に既存の失敗を解消する

## 設計の要点

**司令役は実装コードを読まない。** 長いソースを読むと文脈が埋まり、方針や進捗を見失う。コードを読む作業は作業役（層 1 ではサブタスク、層 2 では文脈を切ったあとの自分）に任せ、司令役は台帳の管理と判断に徹する。

**状態は会話ではなくファイルに置く。** `REFACTORING_PLAN.md` が唯一の正本。会話が圧縮されても、セッションが変わっても、ツールを変えても、このファイルを読めば再開できる。

**保護（A）・変更（B）・検証（C）を分ける。** テストを書いた本人が実装を変えると、自分の変更に合わせてテストを緩めてしまう。分離することでテストが独立した基準として機能する。C はテスト件数と assertion の差分を機械的に突きあわせ、「グリーンに見せるための無効化」を検出する。

## 参考文献

- マーチン・ファウラー『リファクタリング（第 2 版）』オーム社、2019
- マイケル・C・フェザーズ『レガシーコード改善ガイド』翔泳社、2009
- ケント・ベック『テスト駆動開発』オーム社、2017
- エリック・ガンマほか『デザインパターン』ソフトバンククリエイティブ、1999
