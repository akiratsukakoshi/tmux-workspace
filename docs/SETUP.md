# セットアップガイド

このドキュメントは **人間向け** の詳細な手順書です。tmux に触ったことが無い前提で書いています。
AI エージェントに伴走してもらいたい場合は [`AGENTS.md`](../AGENTS.md) を参照してください（このリポを開いて「初期セットアップを手伝って」と頼めば、エージェントがこのファイルを参照しながら進めます）。

---

## 目次

1. [前提環境](#前提環境)
2. [tmux のインストール](#tmux-のインストール)
3. [リポジトリの配置と初期化](#リポジトリの配置と初期化)
4. [tmux の基本操作](#tmux-の基本操作)
5. [claude-parallel レイアウトのセットアップ](#claude-parallel-レイアウトのセットアップ)
6. [起動・停止・再接続](#起動停止再接続)
7. [Windows Terminal を細い帯として配置する](#windows-terminal-を細い帯として配置する)
8. [トラブルシューティング](#トラブルシューティング)

---

## 前提環境

- Windows 10/11
- WSL2 + 任意の Linux ディストリ（Ubuntu 22.04+ で動作確認）
- Windows Terminal（推奨。VSCode の統合ターミナルでも動くが、色や絵文字の見え方が安定するのは Windows Terminal）
- python3 (フック設定のマージに使う。Ubuntu はデフォルトで入っている)
- Claude Code または他の AI コーディングエージェントが各 worktree で起動できること

確認コマンド：
```bash
# WSL の中で:
tmux -V          # 3.x 以上推奨
python3 --version
git --version
```

---

## tmux のインストール

未導入なら：
```bash
sudo apt update && sudo apt install -y tmux
tmux -V
```

---

## リポジトリの配置と初期化

このリポは **`~/tmux-workspace` に置いてある前提** で各スクリプトが書かれています。別の場所に置くときは各スクリプト内のパスを調整してください。

```bash
# 1. クローン
git clone https://github.com/akiratsukakoshi/tmux-workspace.git ~/tmux-workspace
cd ~/tmux-workspace

# 2. tmux.conf を ~/.tmux.conf にシンボリックリンク
#    既存ファイルがあればバックアップ
[ -e ~/.tmux.conf ] && [ ! -L ~/.tmux.conf ] && \
  mv ~/.tmux.conf ~/.tmux.conf.bak.$(date +%Y%m%d_%H%M%S)
ln -sfn ~/tmux-workspace/tmux.conf ~/.tmux.conf

# 3. 状態ファイル置き場を作成
mkdir -p ~/.tmux-workspace-status
for i in 1 2 3 4; do printf '[%d:⚪待機]' "$i" > ~/.tmux-workspace-status/s$i; done
```

ここまで終われば、tmux 自体はもう快適に動く設定が入っている状態です（ステータスバー・ペイン枠・キーバインドなど）。

---

## tmux の基本操作

> tmux 初心者向けの詳細は [`TMUX_BASICS.md`](TMUX_BASICS.md) に分けてあります。ここでは「最低限これだけ覚えれば claude-parallel を使える」コマンドだけ。

### 概念

```
tmux server (バックグラウンドに常駐)
 └── session    ← attach / detach する単位 (例: claude-parallel)
      └── window
           └── pane (画面の1ブロック、ここでシェルが動く)
```

- **detach**：tmux 画面から離れる。セッションは生き続ける（`prefix d`）
- **attach**：セッションに繋ぎ直す（`tmux attach -t <name>`）
- **kill-session**：セッションを完全に終了する（`tmux kill-session -t <name>`）

### prefix キー

tmux のキー操作はすべて「**prefix を押してから次のキー**」の形。
デフォルト prefix は `Ctrl-b`。

### 最低限のキー一覧（tmux 内で使う）

| キー | 意味 |
|---|---|
| `prefix d` | detach（離脱） |
| `prefix 矢印キー` | 隣のペインに移動 |
| `prefix z` | アクティブペインをズーム／元に戻す |
| `prefix =` | レイアウトを 2x2 に再均等化（このリポで追加したショートカット） |
| `prefix Alt-1` | 横4分割レイアウトに切替 |
| `prefix Alt-2` | 縦4分割レイアウトに切替 |
| `prefix Alt-5` | 2x2 レイアウトに切替 |
| `prefix r` | tmux.conf を再読み込み（このリポで追加） |
| `prefix ?` | 全コマンド一覧 |

マウスも `mouse on` を入れているので、ペインクリック切替やドラッグでの境界移動も可能です。

### 最低限のコマンド（シェルから使う、tmux の外）

```bash
tmux ls                              # セッション一覧
tmux attach -t claude-parallel       # セッションに繋ぐ
tmux kill-session -t claude-parallel # セッションを完全終了
tmux kill-server                     # tmux サーバごと全終了
```

### PC を切ると？

tmux サーバは WSL の中で動くプロセスなので、**PC をシャットダウン／再起動すると死にます**。
detach しただけ、ターミナルを閉じただけ、ではセッションは生き続けますが、PC を切ったら諦めて、また `start.sh` で立ち上げ直してください（claude 側の会話履歴は別途残るので、各エージェントの `--continue` 系コマンドで復旧可能）。

---

## claude-parallel レイアウトのセットアップ

「4プロジェクトを並列で監視する」用途のレイアウト。

### 1. 並列対象を決める

並列で監視したい4つのディレクトリを決めます。git クローンでも worktree でも、要は AI エージェントを起動したい4つのディレクトリならOK。

例:
- `~/projects/web-app`
- `~/projects/api-server`
- `~/projects/admin-dashboard`
- `~/playground`

### 2. プロファイルを作る

並列対象のセットを「プロファイル」という単位でまとめます。`profiles/example.sh` をコピーして編集：

```bash
cd ~/tmux-workspace/layouts/claude-parallel
cp profiles/example.sh profiles/myset.local.sh
$EDITOR profiles/myset.local.sh
```

中身：
```bash
WORKTREE_1="$HOME/projects/web-app"
WORKTREE_2="$HOME/projects/api-server"
WORKTREE_3="$HOME/projects/admin-dashboard"
WORKTREE_4="$HOME/playground"

# tiled / even-horizontal / even-vertical
LAYOUT="even-vertical"
```

`*.local.sh` は `.gitignore` 対象なので、個人パスを安心して書けます。
`*.sh`（`.local` 無し）は Git 追跡対象 — チーム共有用 or example 用。

### 3. 各ディレクトリにフックを入れる

`install-hooks.sh` を **プロファイル内の WORKTREE_N と同じ順番で** 4回叩く：

```bash
./install-hooks.sh "$HOME/projects/web-app"          1
./install-hooks.sh "$HOME/projects/api-server"       2
./install-hooks.sh "$HOME/projects/admin-dashboard"  3
./install-hooks.sh "$HOME/playground"                4
```

これで各ディレクトリの `.claude/settings.json` に次の4つのフックが入ります（既存 settings は env など他フィールドは保持してマージされる）：

- `PreToolUse` — ツール実行直前
- `PermissionRequest` — 承認ダイアログ表示時 ★Claude Code 2.1+ で承認待ちの正しい検出フック
- `Notification` — アイドル通知時
- `Stop` — AI エージェントの応答完了時

### 4. 起動

```bash
./start.sh                  # 引数なし → プロファイル一覧表示
./start.sh myset            # プロファイル指定で起動
tmux attach -t claude-parallel
```

---

## 起動・停止・再接続

```bash
# 起動 (セッション作成のみ、attach は別途)
~/tmux-workspace/layouts/claude-parallel/start.sh myset

# attach (繋ぐ)
tmux attach -t claude-parallel

# detach (画面から離れる、セッションは生存)
# tmux 内で: prefix d  (= Ctrl-b → d)

# 完全終了 (セッションを殺す)
tmux kill-session -t claude-parallel
```

セッションは PC を切るまで生き続けるので、普段は `attach` ⇄ `detach` で十分。

### よく使うシナリオ別の動き

| 状況 | やること |
|---|---|
| 初回 / プロファイル新規 | `start.sh <profile>` → `tmux attach -t claude-parallel` |
| ターミナル閉じた / detach した後の復帰 | `tmux attach -t claude-parallel` (start.sh は不要) |
| PC 再起動の後 | `tmux ls` で no server → `start.sh <profile>` → `tmux attach -t claude-parallel` |
| プロファイル変更したい | 一度 `kill-session` してから新プロファイルで `start.sh` |

### 一発化したい（推奨）

毎回これらを判断するのが面倒なら、`~/.bashrc` に関数を仕込むと **どの状況でも `cp4` 一発** で済みます：

```bash
# ~/.bashrc に追記。your-profile は自分のプロファイル名に置き換え。
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

追記後は新しいシェルから自動で読まれます。既に開いているシェルで使いたければ `source ~/.bashrc` を一度実行。

使い方：

```bash
cp4                 # セッションがあれば attach、無ければ start.sh + attach
cp4 别のprofile      # 一時的に別プロファイルで起動したい時
```

関数名は `cp4` 以外でも好みのものに変えてOK（ただし `cp` だけは `cp` (copy) コマンドと被るので避ける）。

---

## Windows Terminal を細い帯として配置する

`LAYOUT="even-vertical"` を選んだ場合、Windows Terminal のウィンドウを「サブディスプレイの右1/3」のような **縦長で細い帯** にすると効果的です。

- 手動：Windows Terminal をドラッグしてサイズ／位置調整
- 半自動：`Win + Z` のスナップアシスト（Windows 11、3列レイアウトがあれば1/3に貼れる）

リサイズフックを仕込んであるので、ウィンドウサイズを変えても4ペインが均等に並び直します。

---

## トラブルシューティング

### ペインの色は変わるのにステータスバーが変わらない

ステータスファイルへの書き込みは効いているが、tmux 側の更新が止まっている可能性。

```bash
# 1. ファイル自体が更新されているか確認
cat ~/.tmux-workspace-status/s1

# 2. tmux を refresh
tmux refresh-client -S
```

### フックが効かない（色も状態も変わらない）

- AI エージェントはセッション開始時にしか `.claude/settings.json` を読まないので、フック追加後は **エージェントを一度再起動** が必要
- VSCode 拡張なら `Ctrl+Shift+P` → `Developer: Reload Window`

### emoji が豆腐（□）になる

Windows Terminal のフォントが絵文字非対応の可能性。
- Cascadia Code（既定）でOK
- 個別調整したい場合は `Settings` → `Profiles` → `Defaults` → `Appearance` → `Font face`

### ペイン番号と表示がズレている

`install-hooks.sh` 実行時の番号と `start.sh` プロファイル内 WORKTREE_N の N が一致しているか確認。
ズレていると別ペインの色が更新されます。

### その他

[`layouts/claude-parallel/README.md`](../layouts/claude-parallel/README.md) のトラブルシュート節も参照。
