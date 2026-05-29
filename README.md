# tmux-workspace

**WSL2 + Windows Terminal の環境で、複数の AI コーディングエージェント（Claude Code / Cursor / Cline など）を並列で走らせている時に、各セッションの状態（作業中／承認待ち／完了）を tmux のステータスバーとペイン背景色で「ひと目」で把握するための環境。**

メインディスプレイで VSCode 拡張版の AI エージェントを使いつつ、サブディスプレイの細い帯に tmux を常駐させて、4本の作業がそれぞれどの状態にあるかを色で監視する、というワークフローを想定しています。

---

## なにを解決するか

VSCode 拡張版の AI コーディングエージェントを 4つのプロジェクトで同時に走らせていると、こんな問題が出ます：

- 「あれ、プロジェクトBは承認待ちで止まってる？それともまだ作業中？」
- 「プロジェクトAが終わったのか確認しないと、次の指示を出せない」
- 全部のタブを巡回チェックしないと状態がわからない

このリポは、各プロジェクトの **`.claude/settings.json` にフックを仕込み**、エージェントが状態遷移するたびに tmux のステータスバー＋ペイン背景色を更新する仕組みを提供します。

```
[1:🔵作業中] [2:🔔承認待ち] [3:✅完了] [4:⚪待機]
```

サブディスプレイの隅にこの帯を貼り付けておけば、視線を移すだけで全体状況が掴めます。

---

## なにを解決しないか

- **エージェントの会話画面そのもの** — 会話は VSCode 拡張側で完結します。tmux はあくまで状態モニタです
- **AI エージェントのオーケストレーション** — 並列実行や指示の自動投入はしません
- **macOS / 素の Linux** — WSL2 + Windows Terminal 前提の作りです（他環境でも動く可能性はありますが未検証）

---

## 構成

```
~/tmux-workspace/
├── README.md                              ← このファイル
├── AGENTS.md                              ← AI エージェント向けの伴走指示
├── CLAUDE.md                              ← Claude Code 向け（AGENTS.md を参照）
├── docs/
│   ├── SETUP.md                           ← 詳細セットアップガイド
│   └── TMUX_BASICS.md                     ← tmux 初心者向けの操作入門
├── agents/skills/                         ← エージェントが伴走するための定型タスク
│   ├── initial-setup.md
│   ├── add-profile.md
│   └── troubleshoot.md
├── tmux.conf                              ← tmux 本体の設定 (~/.tmux.conf にシンボリックリンク)
├── layouts/
│   └── claude-parallel/                   ← 4並列モニタリング用レイアウト一式
│       ├── start.sh                       ← 起動スクリプト
│       ├── install-hooks.sh               ← worktree にフックを入れるスクリプト
│       ├── switch.sh                       ← 稼働中に1スロットだけ別プロジェクトへ差し替え
│       ├── templates/
│       │   └── claude-settings.json.tpl
│       ├── profiles/
│       │   ├── example.sh                 ← プロファイルのテンプレ
│       │   └── *.local.sh                 ← 個人用 (gitignore対象)
│       └── README.md                      ← レイアウト固有の詳細
└── bin/                                   ← 将来の共通ユーティリティ置き場
```

`~/.tmux-workspace-status/` （ホーム直下、リポ外）に各レイアウトが書き出す状態ファイルが置かれます。

---

## クイックスタート

人間向けの **詳しいセットアップは [docs/SETUP.md](docs/SETUP.md) を参照**。tmux が初めての場合は [docs/TMUX_BASICS.md](docs/TMUX_BASICS.md) も読むと操作が掴めます。

**AI エージェントに「セットアップ手伝って」と言うと自動で伴走できます**（→ [AGENTS.md](AGENTS.md)）。

ざっくりは以下：

```bash
# 1. このリポをクローン (置き場所は問わないが ~/tmux-workspace 前提で書かれている)
git clone https://github.com/akiratsukakoshi/tmux-workspace.git ~/tmux-workspace

# 2. tmux.conf をシンボリックリンク
ln -sfn ~/tmux-workspace/tmux.conf ~/.tmux.conf

# 3. 状態ファイル置き場を作成
mkdir -p ~/.tmux-workspace-status
for i in 1 2 3 4; do printf '[%d:⚪待機]' "$i" > ~/.tmux-workspace-status/s$i; done

# 4. 並列したい4プロジェクトを決めて、プロファイルを作る
cd ~/tmux-workspace/layouts/claude-parallel
cp profiles/example.sh profiles/my-set.local.sh
$EDITOR profiles/my-set.local.sh        # WORKTREE_1..4 と LAYOUT を編集

# 5. 各プロジェクトにフックを入れる
./install-hooks.sh ~/path/to/project-1 1
./install-hooks.sh ~/path/to/project-2 2
./install-hooks.sh ~/path/to/project-3 3
./install-hooks.sh ~/path/to/project-4 4

# 6. 起動
./start.sh my-set
tmux attach -t claude-parallel
```

詳細・トラブルシュート・カスタマイズは [docs/SETUP.md](docs/SETUP.md) と [layouts/claude-parallel/README.md](layouts/claude-parallel/README.md) を参照。

---

## 日常運用（2回目以降の起動を一発化）

`~/.bashrc` に小さな関数を仕込むと、PC 再起動の有無に関わらず1コマンドで claude-parallel に入れます。

```bash
# ~/.bashrc に追記 (your-profile はあなたが作ったプロファイル名に置き換え)
cp4() {
  local profile="${1:-your-profile}"
  if tmux has-session -t claude-parallel 2>/dev/null; then
    tmux attach -t claude-parallel
  else
    "$HOME/tmux-workspace/layouts/claude-parallel/start.sh" "$profile" && \
      tmux attach -t claude-parallel
  fi
}
```

使い方：

```bash
cp4                       # セッションがあれば attach、無ければ start.sh + attach
cp4 <別プロファイル名>    # 一時的に別プロファイルで起動したいとき
```

挙動：
- セッションが居る（PC再起動後でなく、まだ生きている） → ただ attach するだけ
- セッションが居ない（PC再起動直後） → `start.sh` で起動してから attach

詳細とトラブルシュートは [docs/SETUP.md](docs/SETUP.md#起動停止再接続) を参照。

---

## 下位スロットだけ差し替える（switch）

上位2プロジェクトは常駐、下位はしょっちゅう入れ替える——そんな時に `start.sh` で作り直すと常駐枠まで落ちてしまう。`switch.sh` は **セッションを再起動せず1スロットだけ** 別プロジェクトへ貼り替える。`~/.bashrc` に関数を仕込めば1コマンド：

```bash
# ~/.bashrc に追記
switch() {
  "$HOME/tmux-workspace/layouts/claude-parallel/switch.sh" "$@"
}
```

使い方：

```bash
switch 3              # いまのディレクトリ ($PWD) を S3 に映す
switch 4 ~/some-repo  # 指定パスを S4 に
```

新しく開いたターミナル（VSCode 統合ターミナル含む）から有効。既存ターミナルで今すぐ使うなら一度 `source ~/.bashrc`。仕組みの詳細は [layouts/claude-parallel/README.md](layouts/claude-parallel/README.md#スロットを差し替えるswitchsh) を参照。

---

## 用意済みレイアウト

| 名前 | 用途 |
|------|------|
| [claude-parallel](layouts/claude-parallel/) | AI エージェント 4 並列の状態を色で監視 |

新しいレイアウト（例：監視ダッシュボード、ドキュメント執筆用など）を増やすときは `layouts/<新レイアウト名>/` を切り、`start.sh` を置く運用。
