# code-smell-refactoring

コードの臭いを検出して優先度づけし、**テストで保護してから小さなステップでグリーンを保ちつつ**リファクタリングするための手順書。『ソフトウェア実装改善ガイド』の方法論を実行可能な形にしたもの。

エージェント製品に依存しない。中身はすべて Markdown とシェルスクリプトで、**Agent Skills の共通形式**（`SKILL.md` + frontmatter）に従っているので、Claude Code・Codex・GitHub Copilot・Cursor がいずれも同じディレクトリをそのまま読める。

## ファイル構成

```
code-smell-refactoring/
├── SKILL.md                        ← 中核。全フェーズの流れ。まずこれを読む
├── README.md                       ← この説明
├── LICENSE                         CC BY 4.0
├── references/
│   ├── capabilities.md             実行方式の判定（層 1／層 2）
│   ├── smells.md                   臭い 10 分類・優先度マトリクス
│   ├── refactoring-loop.md         保護 → 変更 → 検証の 3 ステップ
│   ├── patterns.md                 臭い別の具体手順（1 行 = 1 コミット）
│   ├── dependency-breaking.md      テストのための依存の切りはなし
│   ├── task-prompts.md             各ステップの指示文（5 種）
│   ├── plan-template.md            REFACTORING_PLAN.md と HANDOVER.md の形式
│   └── lang/                       言語固有の補足（対象言語のものだけ読む）
│       ├── c.md                    C / C++
│       ├── oo.md                   Java / C# / Kotlin ほか
│       └── dynamic.md              Python / JS / TS / Ruby ほか
└── scripts/
    ├── verify_harness.sh           テスト実行手段の検出（フェーズ 0）
    └── hotspots.sh                 git 履歴から変更頻度を集計（フェーズ 1）
```

## 導入方法

このディレクトリを、各ツールが走査する場所に置くだけでよい。**転送用の指示ファイル（`AGENTS.md` や `.github/copilot-instructions.md`）は要らない。** どのツールも frontmatter の `name` と `description` だけを先に読み、依頼が一致したときに本体を読む。

| ツール | 個人 | リポジトリ |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `<repo>/.claude/skills/` |
| Codex | `~/.agents/skills/` | `<repo>/.agents/skills/`（cwd からリポジトリルートまで走査） |
| GitHub Copilot（VS Code / CLI / cloud） | `~/.copilot/skills/`, `~/.claude/skills/`, `~/.agents/skills/` | `.github/skills/`, `.claude/skills/`, `.agents/skills/` |
| Cursor | `~/.cursor/skills/` | `<repo>/.cursor/skills/` |

共通の交差点が `.agents/skills` なので、**そこを正本にして残りは symlink で足す**のが最小構成になる。

### 個人用

```bash
git clone <このリポジトリ> ~/.agents/skills/code-smell-refactoring   # Codex と Copilot はここを直接読む
ln -s ~/.agents/skills/code-smell-refactoring ~/.claude/skills/code-smell-refactoring
ln -s ~/.agents/skills/code-smell-refactoring ~/.cursor/skills/code-smell-refactoring
```

symlink を走査が追わないツールがあれば、その場所にはコピーを置いて更新時に同期する。

### リポジトリ共有

実体を `<repo>/.agents/skills/code-smell-refactoring/` に取りこみ、`.claude/skills/` と `.cursor/skills/` からは相対 symlink を張ってコミットする。

```bash
git subtree add --prefix .agents/skills/code-smell-refactoring <このリポジトリ> master --squash
ln -s ../../.agents/skills/code-smell-refactoring .claude/skills/code-smell-refactoring
```

submodule でも成立するが、`git clone` 直後に中身が空になるので subtree のほうが事故が少ない。symlink が使えない環境（Windows で `core.symlinks` が無効など）ではコピーを置く。

### 呼びだし方

- **自動**：`description` に一致する依頼で読みこまれる（「この関数が長すぎるので整理して」など）
- **明示**：Claude Code と Copilot は `/code-smell-refactoring`、Codex は `$code-smell-refactoring`（`/skills` からも選べる）

### skill 機構を持たないツール

会話の冒頭で場所を教えれば足りる。内容はツールに依存しない。

```
.agents/skills/code-smell-refactoring/SKILL.md を読んで、その手順に従って
src/parser 以下をリファクタリングしてください。
```

サブタスクを起動できないツールでは**層 2**（1 セッション 1 ステップ）として動く。判定と手順は `references/capabilities.md`。

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

## 言語中立と言語パック

コア（`SKILL.md` と `references/*.md`）は**どの言語でも成立する内容だけ**を持つ。
言語ごとの書きかた・落とし穴・「完了の形」は `references/lang/` に分けてあり、
フェーズ 0 で対象言語のパックを 1 つ選んで以後の作業役に読ませる。

パックが無い言語でも作業は成立する。**足りなかった点を最後に報告する**運用に
してあるので、その報告が新しいパックの素材になる。

## 設計の要点

**司令役は実装コードを読まない。** 長いソースを読むと文脈が埋まり、方針や進捗を見失う。コードを読む作業は作業役（層 1 ではサブタスク、層 2 では文脈を切ったあとの自分）に任せ、司令役は台帳の管理と判断に徹する。

**状態は会話ではなくファイルに置く。** `REFACTORING_PLAN.md` が唯一の正本。会話が圧縮されても、セッションが変わっても、ツールを変えても、このファイルを読めば再開できる。

**保護（A）・変更（B）・検証（C）を分ける。** テストを書いた本人が実装を変えると、自分の変更に合わせてテストを緩めてしまう。分離することでテストが独立した基準として機能する。C はテスト件数と assertion の差分を機械的に突きあわせ、「グリーンに見せるための無効化」を検出する。

## 参考文献

- マーチン・ファウラー『リファクタリング（第 2 版）』オーム社、2019
- マイケル・C・フェザーズ『レガシーコード改善ガイド』翔泳社、2009
- ケント・ベック『テスト駆動開発』オーム社、2017
- エリック・ガンマほか『デザインパターン』ソフトバンククリエイティブ、1999

本文は上記を参照しつつ、筆者の講義資料をもとに書きおろしたもの。

## ライセンス

© 2026 Ryohji Ikebe

このリポジトリの内容（文書・スクリプトを含む）は [Creative Commons 表示 4.0 国際（CC BY 4.0）](https://creativecommons.org/licenses/by/4.0/deed.ja)で提供する。全文は [`LICENSE`](LICENSE)。改変・再配布・商用利用ができ、条件は出典の表示のみ。

表示の例：

> code-smell-refactoring by Ryohji Ikebe（https://github.com/ryohji/code-smell-refactoring）, CC BY 4.0

リポジトリへ取りこんで使う場合は、`.agents/skills/code-smell-refactoring/LICENSE` をそのまま残せば条件を満たす。
