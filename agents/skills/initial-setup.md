---
name: initial-setup
description: ユーザーがこのリポを初めて使うときの初回セットアップを伴走する。tmuxインストール確認、シンボリックリンク作成、状態ファイル準備、最初のプロファイル作成と起動までを安全に進める。
trigger: ユーザーが「セットアップして」「初期設定」「最初に何すればいい」などと言ったとき
---

# Skill: initial-setup

## 目的

ユーザーがこのリポを初めて使う時に、ゼロから動く状態（claude-parallel が起動してステータスバーが見える状態）まで持っていく。

## 進め方

各ステップで **必ず現状を確認してから実行** すること。ユーザーが既に一部を済ませている可能性がある。

---

### Step 1: 環境確認

最初に以下をユーザーの環境で確認する：

```bash
tmux -V                       # 3.x 以上か
python3 --version             # python3 が入っているか
ls -la ~/.tmux.conf 2>&1      # 既存の tmux.conf があるか
ls -la ~/.tmux-workspace-status/ 2>&1   # 状態ディレクトリがあるか
ls ~/                         # 並列対象になりそうな候補ディレクトリの確認
```

判断：
- tmux 未インストール → `sudo apt install -y tmux` を提案（sudo必要なのでユーザー実行）
- python3 未インストール → 上記同様（Ubuntu はデフォルトで入っているのでまず無い）

### Step 2: シンボリックリンク

`~/.tmux.conf` の状態を確認：
- 存在しない → そのまま `ln -sfn ~/tmux-workspace/tmux.conf ~/.tmux.conf` で作る
- 通常ファイルとして存在 → バックアップしてからシンボリックリンクで上書き
- すでにこのリポへのシンボリックリンク → 何もしない

```bash
if [ -e ~/.tmux.conf ] && [ ! -L ~/.tmux.conf ]; then
  mv ~/.tmux.conf ~/.tmux.conf.bak.$(date +%Y%m%d_%H%M%S)
fi
ln -sfn ~/tmux-workspace/tmux.conf ~/.tmux.conf
```

### Step 3: 状態ファイル置き場

```bash
mkdir -p ~/.tmux-workspace-status
for i in 1 2 3 4; do printf '[%d:⚪待機]' "$i" > ~/.tmux-workspace-status/s$i; done
```

### Step 4: 並列対象を決める（ユーザーとの対話）

ユーザーに「Claude Code（または他の AI エージェント）を並列で走らせたいプロジェクトを4つ教えて」と聞く。
4つ未満ならダミーディレクトリで埋めるか、本人が決める。

ユーザーから候補を聞いた後、`ls -la <path>` で全パスの実在を確認。

> ⚠️ 落とし穴: ユーザーが `~/<自分のユーザー名>/foo` のようなパスを書いた場合、`~` がホーム展開されるので `/home/<user>/<user>/foo` と解釈されてしまう。
> ユーザーは「ホーム直下の foo」のつもりかもしれないので、見つからなかったら `/home/<user>/foo` (ホーム直下) の方を確認すること。

### Step 5: プロファイル作成

```bash
cd ~/tmux-workspace/layouts/claude-parallel
cp profiles/example.sh profiles/<name>.local.sh
```

`<name>` はユーザーに命名してもらう（例: `work`, `myset`, `client-x` など）。

`.local.sh` 拡張子であることが重要 — gitignore 対象になり、個人パスが Git に入らない。

WORKTREE_1..4 と LAYOUT を編集：

```bash
WORKTREE_1="$HOME/path/to/project-1"
WORKTREE_2="$HOME/path/to/project-2"
WORKTREE_3="$HOME/path/to/project-3"
WORKTREE_4="$HOME/path/to/project-4"

# tiled / even-horizontal / even-vertical
LAYOUT="tiled"
```

LAYOUT はユーザーに選んでもらう。判断基準：
- サブディスプレイ全面or大きく使う → `tiled` (2x2)
- 画面の右1/3 などの細い縦帯 → `even-vertical`
- 画面の下端などの細い横帯 → `even-horizontal`

### Step 6: 各 worktree にフックを設置

プロファイルの WORKTREE_N と一致する順番で4回叩く：

```bash
./install-hooks.sh "$HOME/path/to/project-1" 1
./install-hooks.sh "$HOME/path/to/project-2" 2
./install-hooks.sh "$HOME/path/to/project-3" 3
./install-hooks.sh "$HOME/path/to/project-4" 4
```

各実行で `merged hooks into existing settings` か `installed hooks` のメッセージが出ることを確認。

> 重要: 既存の `.claude/settings.json` があると、`env`、`permissions`、`mcpServers` などのフィールドは保持してマージされる。データは失われない。バックアップも自動で `.bak.<timestamp>` で取られる。

### Step 7: 起動

```bash
./start.sh <name>            # 上で作ったプロファイル名
tmux attach -t claude-parallel
```

ユーザーに「ステータスバーに `[1:⚪待機] [2:⚪待機] [3:⚪待機] [4:⚪待機]` が見えるか」確認。

### Step 8: 動作確認

ユーザーに「どれか1つのプロジェクトで VSCode の Claude Code 拡張（または使っているエージェント）を起動して、何か作業させてみて」と頼む。

期待される遷移：
- ツール実行直前 → そのスロットが青「🔵作業中」
- 承認待ちが出るとき → オレンジ「🔔承認待ち」、ペイン背景が暗赤
- 完了 → 緑「✅完了」、ペイン背景が暗緑

エージェントを再起動する必要があるかも（フック設定は起動時にしか読まれない）。
VSCode の場合 `Ctrl+Shift+P` → `Developer: Reload Window` を案内。

---

## 完了の判定

- `tmux attach -t claude-parallel` で4ペインが見える
- ステータスバーが正しく4スロット表示される
- 実際に AI エージェントを動かしたとき、対応スロットの色が遷移する

これらが揃えば完了。

## 失敗時のリカバリ

何かおかしくなったら、状況に応じて [`troubleshoot.md`](troubleshoot.md) に切り替え。
