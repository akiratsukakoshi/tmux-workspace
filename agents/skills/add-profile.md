---
name: add-profile
description: 並列対象セットの追加・変更を伴走する。新規プロファイル作成、各 worktree へのフック設置、レイアウトの切替、起動までを安全に進める。既存セッションを kill する前に必ずユーザー確認を取る。
trigger: ユーザーが「プロジェクトを変えたい」「並列対象を増やしたい」「別のセットを試したい」などと言ったとき
---

# Skill: add-profile

## 目的

並列対象のセット（4プロジェクト）を新規に追加、もしくは既存のセットを変更する。

## ユースケース別の分岐

```
[A] 全く新しいセットを作りたい (今のセットは残す)
    → 新規プロファイルファイルを作って、新セットで起動

[B] 既存セットの一部を差し替えたい (1つだけ別プロジェクトに、など)
    → 既存プロファイルを直接編集 or コピーして新ファイル

[C] 一時的に違うセットを試したい
    → コピーして .local.sh で別名にする (元のセットは温存)
```

ユーザーがどのパターンかを最初に確認すること。

---

## 共通手順

### Step 1: 新セットの並列対象ディレクトリを決める

ユーザーから4つの対象パスを聞く。実在を `ls -la` で確認。

> ⚠️ 落とし穴: ユーザーが `~/<自分のユーザー名>/foo` のようなパスを書いた場合、`~` がホーム展開されるので `/home/<user>/<user>/foo` と解釈される。「ホーム直下の foo」のつもりだったら、`/home/<user>/foo` を確認すること。

### Step 2: プロファイル作成

```bash
cd ~/tmux-workspace/layouts/claude-parallel
cp profiles/example.sh profiles/<新名前>.local.sh
$EDITOR profiles/<新名前>.local.sh
```

ファイル名は必ず `.local.sh` 拡張子 — gitignore 対象。
中身：
```bash
WORKTREE_1="$HOME/path/to/project-1"
WORKTREE_2="$HOME/path/to/project-2"
WORKTREE_3="$HOME/path/to/project-3"
WORKTREE_4="$HOME/path/to/project-4"
LAYOUT="tiled"   # tiled / even-horizontal / even-vertical
```

### Step 3: 各 worktree にフックを設置

WORKTREE_N と同じ順番で：

```bash
./install-hooks.sh "$WORKTREE_1" 1
./install-hooks.sh "$WORKTREE_2" 2
./install-hooks.sh "$WORKTREE_3" 3
./install-hooks.sh "$WORKTREE_4" 4
```

> 既に他のプロファイルで使われている worktree でも、上書き（マージ）する。`env` などは保持される。
> ただし「同じ worktree を別のプロファイルで違うペイン番号に割り当てる」と、最後に install-hooks.sh を叩いた番号で固定されてしまう。同時に複数プロファイルで運用する場合は要注意。

### Step 4: 既存セッションの扱い

`tmux has-session -t claude-parallel 2>/dev/null && echo "session exists" || echo "no session"` で確認。

セッションが既にある場合、`start.sh` は何もせず終わる仕様。なので新プロファイルで起動するには既存セッションを kill する必要がある。

**ユーザーに必ず確認**：
- 「既存のセッションを kill して、新プロファイルで起動し直してもいい？」
- 「kill するとペイン内のシェル（と、もしあれば動作中のコマンド）は失われる」

OK が出たら：
```bash
tmux kill-session -t claude-parallel
~/tmux-workspace/layouts/claude-parallel/start.sh <新プロファイル名>
tmux attach -t claude-parallel
```

ユーザーが attach 中なら、kill した瞬間に detach される。事前に伝えること。

### Step 5: 動作確認

[`initial-setup.md`](initial-setup.md) の Step 8 と同様、何か作業させて色遷移を確認。

---

## レイアウトを変えるだけのケース

並列対象は同じで、LAYOUT だけ変えたいなら：

```bash
# プロファイル編集 (LAYOUT=... の行のみ)
$EDITOR profiles/<name>.local.sh

# 再起動
tmux kill-session -t claude-parallel
~/tmux-workspace/layouts/claude-parallel/start.sh <name>
tmux attach -t claude-parallel
```

実行中に **試行錯誤** したい場合は、kill せず tmux 内で：
```
prefix Alt-1   → even-horizontal
prefix Alt-2   → even-vertical
prefix Alt-5   → tiled
prefix =       → tiled (このリポで追加したショートカット)
```

ただし、リサイズフックは起動時のLAYOUT固定なので、Windows Terminal のサイズを変えると元のLAYOUTに戻る。本決まりしたら profiles ファイルを編集して再起動。
