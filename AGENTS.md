# AGENTS.md — AI エージェント伴走ガイド

このファイルは、Claude Code / Cursor / Cline などの AI コーディングエージェントがこのリポジトリで作業するときに読むエントリポイントです。
人間向けの説明は [`README.md`](README.md) と [`docs/SETUP.md`](docs/SETUP.md) にあります。

---

## このリポは何のためのものか

**WSL2 + Windows Terminal の環境で、複数の AI コーディングエージェントを並列で走らせる時に、各エージェントの状態（作業中／承認待ち／完了）を tmux のステータスバーとペイン背景色でひと目で把握するための環境を提供するリポジトリ。**

詳細：[`README.md`](README.md)

---

## 何を伴走できるか

ユーザーがこのリポでセッションを始めたら、以下のタスクを自律的に伴走できます：

| ユーザーの要望 | エージェントが参照すべきスキル |
|---|---|
| 「初めて使うのでセットアップを手伝って」 | [`agents/skills/initial-setup.md`](agents/skills/initial-setup.md) |
| 「並列対象のプロジェクトを変えたい／追加したい」 | [`agents/skills/add-profile.md`](agents/skills/add-profile.md) |
| 「色が変わらない／何かおかしい」 | [`agents/skills/troubleshoot.md`](agents/skills/troubleshoot.md) |

スキルファイルには、確認すべきこと・実行すべきコマンド・破壊的操作を避けるための注意点が手順形式で書かれています。エージェントはユーザーの状況を確認しながらこれを順に実行してください。

---

## リポの構造（エージェント向け）

```
~/tmux-workspace/
├── README.md                              人間向け概要
├── AGENTS.md                              このファイル
├── CLAUDE.md                              Claude Code 向け (AGENTS.md を include)
├── docs/
│   ├── SETUP.md                           人間向け詳細セットアップ
│   └── TMUX_BASICS.md                     tmux 初心者向け入門
├── agents/skills/                         エージェント向けのスキル定義
│   ├── initial-setup.md
│   ├── add-profile.md
│   └── troubleshoot.md
├── tmux.conf                              tmux 本体設定 (~/.tmux.conf にシンボリックリンク)
├── layouts/claude-parallel/               4並列モニタリング用レイアウト
│   ├── start.sh                           プロファイル指定で起動 (`./start.sh <profile>`)
│   ├── install-hooks.sh                   `<worktree> <1-4>` でフック設置
│   ├── switch.sh                          `<1-4> [path]` で稼働中に1スロット差し替え (再起動不要)
│   ├── templates/claude-settings.json.tpl フックの雛形 (SESSION_NUM / PANE_INDEX 置換)
│   └── profiles/
│       ├── example.sh                     Git追跡 (テンプレ)
│       └── *.local.sh                     gitignore対象 (個人パス)
└── bin/                                   共通ユーティリティ (現在未使用)
```

---

## 重要な前提知識

### 関係する外部リソース

リポ外のパスで、このセットアップが触る場所：

- `~/.tmux.conf` — `tmux-workspace/tmux.conf` へのシンボリックリンク
- `~/.tmux-workspace-status/sN` (N=1..4) — フックが書き込む状態文字列
- `<各 worktree>/.claude/settings.json` — 各プロジェクトのフック設定
- `/tmp/claude-hooks.log` — デバッグ用（フック発火ログ。現在のテンプレでは無効）

### 触ってはいけない場所

- `~/.claude/settings.json`（ユーザーグローバル） — 完全に管轄外。ここを変更してはいけない
- 各 worktree の `.claude/settings.json` の **`hooks` 以外のキー**（`env`, `permissions`, `mcpServers` 等） — `install-hooks.sh` がマージしてくれるので、エージェントは手で書き換えない

### 状態フックの仕組み

各 worktree の `.claude/settings.json` に仕込む4つのフックが、対応する tmux ペインの背景色とステータスバーの状態スロットを更新する：

| フック | 状態表示 | ペイン背景 |
|---|---|---|
| `PreToolUse` | 🔵作業中 (青) | 通常 |
| `PermissionRequest` ★ | 🔔承認待ち (オレンジ) | 暗赤 (colour52) |
| `Notification` | 🔔待機 (黄、アイドル) | 暗赤 (colour52) |
| `Stop` | ✅完了 (緑) | 暗緑 (colour22) |

★ Claude Code 2.1 以降では承認ダイアログは `PermissionRequest` で発火する（`Notification` ではない）。旧バージョン仕様で書かれた既存ドキュメントがあっても、最新は `PermissionRequest` を使うこと。

---

## エージェントが守るべきルール

1. **既存ファイルを上書きする前に必ずバックアップ**。`install-hooks.sh` は自動でこれを行うが、エージェントが手動編集する場合も `*.bak.YYYYMMDD_HHMMSS` を残す。
2. **個人パスを含むファイルを Git に commit しない**。`.gitignore` で `layouts/*/profiles/*.local.sh` と `.claude/settings.json` を除外済み。新規にユーザー固有のファイルを作るときは、必ず ignore 済みのパターンに一致させるか、`.gitignore` を更新する。
3. **ユーザーグローバル `~/.claude/settings.json` を触らない**。このリポは worktree 単位の `.claude/settings.json` のみ管理する。
4. **破壊的な tmux 操作（`kill-session`, `kill-server`）はユーザー確認を取ってから**。attach 中のユーザーは強制 detach されるため。
5. **不明点は推測せず、ユーザーに確認**。並列対象として4つ目をどうするか、レイアウトをどれにするかなど、複数の合理的選択肢がある時は AskUserQuestion 形式で聞く。

---

## エージェントへの典型的なやり取り例

ユーザー: 「セットアップ手伝って」
→ [`agents/skills/initial-setup.md`](agents/skills/initial-setup.md) を読み込み、最初の「環境確認」セクションから実行開始。

ユーザー: 「プロジェクト変えたい」「並列対象を変えたい」
→ 4枠まるごと組み替えるなら [`agents/skills/add-profile.md`](agents/skills/add-profile.md) を読み込み、新しいプロファイル作成 → `install-hooks.sh` 実行 → 再起動の流れを案内。
→ **下位スロットだけ／1枠だけ** 差し替えるなら、再起動不要の [`switch.sh`](layouts/claude-parallel/switch.sh) を案内（`./switch.sh <1-4> [path]`、path 省略時は `$PWD`）。常駐スロットを落とさずに済む。

ユーザー: 「色が変わらない／挙動おかしい」
→ [`agents/skills/troubleshoot.md`](agents/skills/troubleshoot.md) を読み込み、切り分け手順を順に実行。
