# layout: claude-parallel

Claude Code を4並列で走らせ、各セッションの状態（作業中／入力待ち／完了）を **ペイン背景色** と **ステータスバー** の両方で視覚的に把握できるレイアウト。

## 仕組み

- tmux セッション名: `claude-parallel`
- 4ペイン (2×2 tiled) を作成、各ペインは **bash シェルのまま**（claude は起動しない）
- 実際の Claude Code とのやり取りは **VSCode 拡張**（または別ターミナルでの `claude` CLI）など、tmux の外で行う想定
- ペイン内に claude を起動しないのは、VSCode 拡張で起動する claude と二重になり、tmux ペイン内の claude が「誰とも会話していない空殻」になるのを避けるため
- ペイン番号は固定:

  ```
  +-------------+-------------+
  | 0 (S1)      | 1 (S2)      |
  +-------------+-------------+
  | 2 (S3)      | 3 (S4)      |
  +-------------+-------------+
  ```

- 各 worktree の `.claude/settings.json` にフックを仕込み、Claude Code の状態遷移時に下記を実行:

  | フック | 状態 | ステータスバー | ペイン背景 |
  |---|---|---|---|
  | `PreToolUse`        | 作業中     | 青 `[n:🔵作業中]`        | 通常 (default) |
  | `PermissionRequest` | 承認待ち   | オレンジ `[n:🔔承認待ち]` | 暗赤 (colour52) |
  | `Notification`      | 入力待ち   | 黄 `[n:🔔待機]`          | 暗赤 (colour52) |
  | `Stop`              | 完了       | 緑 `[n:✅完了]`          | 暗緑 (colour22) |

  状態文字列は `~/.tmux-workspace-status/sN` に書き出され、tmux の status-right が 1 秒間隔で読み取って表示する。

  状態遷移は **イベント駆動**（フック発火時にのみ変わる）なので、`✅完了` の状態は **次に Claude が動き出す（次の PreToolUse か Stop が発火する）まで継続** する。明示的に「⚪待機」初期状態に戻すフックは無く、これは仕様。

  Claude がツールを使わずテキストだけで返事した場合は `PreToolUse` が発火しないため、`✅完了 → ✅完了` で見た目に変化はない。これも仕様。

---

## 使い方

並列対象のセット（4つのディレクトリ）は **プロファイル** として `profiles/` 配下に置く。
`profiles/<name>.local.sh` は gitignore 対象（個人パスを含めても安全）、`profiles/<name>.sh` は Git 追跡対象（チーム共有や example 用）。

### 1. 並列対象ディレクトリを用意する

「Claude Code を起動したい4つのディレクトリ」を用意。中身は問わない（git クローンでもworktreeでも単なるディレクトリでも可）。

### 2. プロファイルを作る

`profiles/example.sh` をコピーして個人用プロファイルにする：

```bash
cd ~/tmux-workspace/layouts/claude-parallel
cp profiles/example.sh profiles/my-set.local.sh
$EDITOR profiles/my-set.local.sh
```

中身は `WORKTREE_1` 〜 `WORKTREE_4` を定義するだけ：

```bash
WORKTREE_1="$HOME/path/to/project-a"
WORKTREE_2="$HOME/path/to/project-b"
WORKTREE_3="$HOME/path/to/project-c"
WORKTREE_4="$HOME/path/to/project-d"
```

並列セットが複数ある場合は `profiles/<別名>.local.sh` を増やすだけ。`start.sh` 自体は触らない。

### 3. 各ディレクトリにフックを配置

`install-hooks.sh` を WORKTREE_N の順番通りに4回叩く：

```bash
./install-hooks.sh "$HOME/path/to/project-a" 1
./install-hooks.sh "$HOME/path/to/project-b" 2
./install-hooks.sh "$HOME/path/to/project-c" 3
./install-hooks.sh "$HOME/path/to/project-d" 4
```

第2引数の **セッション番号 (1–4) はプロファイル内 WORKTREE_N の N と必ず一致させる** こと。
番号が合わないと、別ペインの背景色が書き換わる。

既存の `.claude/settings.json` があれば `.bak.<timestamp>` でバックアップしてから上書きする。

> 注: フックはディレクトリ単位で固定されるので、別プロファイルで同じディレクトリを違うペイン番号に割り当てると不整合が起きる。並列セットを増やすときは、同じディレクトリを別番号で使わないように。

### 4. 起動

```bash
./start.sh               # プロファイル一覧を表示
./start.sh my-set        # 起動 (profiles/my-set.local.sh を読む)
tmux attach -t claude-parallel
```

`start.sh` はセッションを作るだけで attach はしない。attach は別途上記コマンドで行う。

detach は `prefix + d`、再接続は `tmux attach -t claude-parallel`。
セッションを完全終了するには `tmux kill-session -t claude-parallel`。

---

## スロットを差し替える（switch.sh）

下位スロットだけ頻繁に別プロジェクトへ切り替えたいとき、`start.sh` でセッションを作り直すと常駐中の上位スロットまで落ちてしまう。`switch.sh` は **セッションを再起動せず1スロットだけ** 別の worktree に貼り替える。

```bash
./switch.sh <スロット> [worktree_path]
#   <スロット>        1..4
#   [worktree_path]  省略時はカレントディレクトリ ($PWD)
```

例：

```bash
# 開いているプロジェクトのターミナルから、それを S3 に映す
cd ~/project-Y && ~/tmux-workspace/layouts/claude-parallel/switch.sh 3

# パス指定で S4 に
./switch.sh 4 ~/some-other-repo
```

中でやること：

1. `install-hooks.sh <path> <slot>` を呼び、その worktree のフックを当該スロットに貼り直す（以後その worktree の状態が当該ペインに出る）
2. ライブのペイン `0.<slot-1>` を新ディレクトリで `respawn-pane`（中の素のシェルは作り直される）＋ タイトルを `S<slot>:<名前>` に更新
3. そのスロットの状態文字列 `~/.tmux-workspace-status/sN` を消して背景色をリセットし、`[N:-]` のニュートラルに戻す（前のプロジェクトの「✅完了」等が残らないように）

触らなかったスロット（典型的には常駐の上位2つ）はそのまま生き続ける。セッションが起動していなければフックの貼り直しだけ行い、次回 `start.sh` 起動時に反映される。

毎回フルパスを打たずに済むよう `~/.bashrc` に `switch` 関数を仕込んでおくと `switch 3` だけで使える（→ ルートの [README.md](../../README.md#日常運用2回目以降の起動を一発化) 参照）。

> 注: `switch.sh` を叩くたびに対象 worktree へ `.claude/settings.json.bak.<timestamp>` が1つ増える（`install-hooks.sh` の通常動作）。気になれば古い `.bak` は手で間引いてよい。

---

## フックの動作確認

1. `tmux attach -t claude-parallel` で接続
2. どれかのペインで Claude Code に何かを依頼（例: 「現在のディレクトリを ls して」）
3. 期待される遷移:
   - ツール実行が始まると → そのペインのステータスが **青「🔵作業中」** に
   - 入力を促されると → **黄「🔔待機」** に、ペイン背景が暗赤に
   - 応答が完了すると → **緑「✅完了」** に、ペイン背景が暗緑に
4. tmux 画面下のステータスバー右側に4スロット分の状態がリアルタイムに反映される

ステータスファイルを直接書き換えても挙動が確認できる:

```bash
printf '#[bg=colour28,fg=colour231] [S1:✅完了] #[default]' > ~/.tmux-workspace-status/s1
```

---

## トラブルシューティング

### ペイン番号が合わない／別ペインの色が変わる

- `tmux display-message -p -t claude-parallel:0.0 '#P'` などで実際のペイン index を確認
- `start.sh` がペインを4つ作る順番は `WORKTREE_1 → 2 → 3 → 4` で、`select-layout tiled` で 2×2 化される
- tiled 後のペイン index は **作成順** に振られる（左上=0, 右上=1, 左下=2, 右下=3）
- 配置が想定と違う場合、tmux のバージョン差や端末サイズが影響することがある。`tmux list-panes -t claude-parallel` で実際の状態を確認

### フックが効かない (色も状態も変わらない)

- `<worktree>/.claude/settings.json` が存在するか確認
- Claude Code はセッション開始時にしか settings.json を読まない。フック追加後は Claude を一度終了して再起動する
- フックは shell 経由で実行される。tmux コマンドが PATH にあるか確認: `which tmux`
- フックのコマンドを手で叩いてみる:
  ```bash
  printf '#[bg=colour28,fg=colour231] [S1:✅完了] #[default]' > ~/.tmux-workspace-status/s1
  tmux select-pane -t claude-parallel:0.0 -P 'bg=colour22'
  tmux refresh-client -S
  ```

### ステータスバーに色が表示されず生のエスケープ文字列 (`#[bg=...]`) が見える

- tmux.conf の `status-right` は外部コマンドの出力をそのまま埋め込む
- tmux はステータスバー内の `#[...]` 構文を解釈するので、ステータスファイルにそのまま書いてあれば反映される
- 反映されない場合は `~/.tmux.conf` が当リポジトリの tmux.conf を指しているか確認: `ls -la ~/.tmux.conf`

### ペイン背景色が変わらない／変な所が変わる

- `tmux select-pane -t TARGET -P 'bg=COLOR'` はターゲットペインの style だけ変えてアクティブペインは変更しない動作のはず
- うまく動かない場合、`set-option -p -t TARGET window-style 'bg=COLOR'` に置き換える手もある（テンプレートを書き換えて `install-hooks.sh` で再配置）

### `tmux attach` 後、ペインタイトルが見えない

- tmux.conf 側で `pane-border-status top` を設定済み。表示されない場合は再読み込み: `tmux source-file ~/.tmux.conf`
- shell の PROMPT 設定がペインタイトルを上書きすることがある。気になる場合は shell 側の OSC エスケープ送信を止める

### Claude Code のグローバル設定 (`~/.claude/settings.json`) との関係

- このレイアウトは **worktree ごとの** `.claude/settings.json` だけを編集する
- ユーザーグローバルの `~/.claude/settings.json` は触らない
- 両方に hooks があると重複実行される可能性があるので注意
