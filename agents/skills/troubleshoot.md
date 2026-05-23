---
name: troubleshoot
description: 状態色やステータスバーが期待通りに動かないときの切り分けを伴走する。ファイル更新の有無、tmux 設定、フック発火の3レイヤーで切り分ける。
trigger: ユーザーが「色が変わらない」「ステータスバー変わらない」「フックが効いてない」などと言ったとき
---

# Skill: troubleshoot

## 切り分けの基本フレーム

問題は次の3レイヤーのどこかで起きている：

```
[A] AIエージェント側のフック発火
        ↓
        書き込み: ~/.tmux-workspace-status/sN
        書き込み: tmux select-pane -P 'bg=...'
        ↓
[B] ステータスファイルの更新
        ↓
[C] tmux 側の表示更新
        ↓ (status-interval 1秒)
        画面表示
```

「色は変わるけどステータスバーが変わらない」「全く何も動かない」など、症状によってどこを疑うか変わる。

---

## まずやる：現状把握

```bash
# 1. tmux サーバとセッション
tmux list-sessions 2>&1
tmux list-panes -t claude-parallel 2>&1

# 2. ペインで何が動いているか
tmux list-panes -t claude-parallel -F '#{pane_index}: #{pane_current_command}  pid=#{pane_pid}  path=#{pane_current_path}'

# 3. 各ステータスファイルの中身
for i in 1 2 3 4; do printf 's%d: ' "$i"; cat ~/.tmux-workspace-status/s$i; echo; done

# 4. tmux クライアント接続状況
tmux list-clients 2>&1

# 5. 各 worktree のフック設定確認
for d in ~/path1 ~/path2 ~/path3 ~/path4; do  # ←実際のパスに置き換える
  echo "--- $d ---"
  python3 -c "
import json
try:
  d = json.load(open('$d/.claude/settings.json'))
  print('hooks:', list(d.get('hooks', {}).keys()))
  print('top-level keys:', list(d.keys()))
except FileNotFoundError:
  print('settings.json なし')
"
done
```

これでだいたいの状況が掴める。

---

## 症状別

### 症状1: ステータスバーに何も表示されない

- `~/.tmux-workspace-status/` ディレクトリが存在するか
- `s1〜s4` のファイルが存在するか
- 中身が読めるか（`cat`）

無ければ：
```bash
mkdir -p ~/.tmux-workspace-status
for i in 1 2 3 4; do printf '[%d:⚪待機]' "$i" > ~/.tmux-workspace-status/s$i; done
```

### 症状2: ペイン色は変わるのにステータスバーの状態テキストが古いまま

→ tmux 側の表示更新の問題。

```bash
# 手動で書き込んで挙動を確認
printf '#[bg=colour220,fg=colour16] [1:TEST] #[default]' > ~/.tmux-workspace-status/s1

# tmux に re-render を促す
tmux refresh-client -S
```

それでも変わらないなら `tmux source-file ~/.tmux.conf` で設定を再読み込み。

### 症状3: 色もテキストも全く変わらない

フック自体が発火していない可能性が高い。発火を確認するためデバッグログを有効化：

`layouts/claude-parallel/templates/claude-settings.json.tpl` の各 `command` の冒頭に `echo "$(date '+%H:%M:%S.%3N') S{{SESSION_NUM}} <EventName>" >> /tmp/claude-hooks.log; ` を追加して install-hooks.sh で4 worktree に再 install。AI エージェントを再起動した上で動かし、`/tmp/claude-hooks.log` を確認：

- ログが空 → エージェント側がフック発火していない（再起動忘れ？ settings.json のパスを正しく読んでいるか確認）
- ログにフックは出るが状態反映されない → tmux コマンド実行で失敗。PATH や session 名を確認

### 症状4: 別ペインの色が更新される

`install-hooks.sh` の番号と `start.sh` プロファイル内の WORKTREE_N の N がズレている可能性。

```bash
# 各 worktree の settings.json から、どのペイン番号にひもづいているか確認
for d in ~/path1 ~/path2 ~/path3 ~/path4; do
  echo "--- $d ---"
  python3 -c "
import json, re
try:
  d = json.load(open('$d/.claude/settings.json'))
  cmd = d['hooks']['PreToolUse'][0]['hooks'][0]['command']
  m = re.search(r'claude-parallel:0\.(\d+)', cmd)
  print('pane index:', m.group(1) if m else '?')
except Exception as e:
  print('error:', e)
"
done
```

ズレていたら正しい番号で `install-hooks.sh` を叩き直す。

### 症状5: 「承認待ち」が検出されない

`Notification` フックではなく `PermissionRequest` フックが必要（Claude Code 2.1+）。
現在のテンプレに `PermissionRequest` が含まれているか確認：

```bash
grep PermissionRequest ~/tmux-workspace/layouts/claude-parallel/templates/claude-settings.json.tpl
```

含まれていれば、各 worktree の settings.json にもあるか確認：
```bash
python3 -c "
import json
d = json.load(open('/path/to/worktree/.claude/settings.json'))
print('PermissionRequest:', 'PermissionRequest' in d.get('hooks', {}))
"
```

無ければ `install-hooks.sh` で再設置。

### 症状6: emoji が豆腐 (□)

Windows Terminal のフォントの問題。`Cascadia Code` などの絵文字対応フォントを使う。
tmux 側では対処不可。

### 症状7: tmux 再接続したらレイアウトが崩れる

ウィンドウサイズが attach 直前と違うと、リサイズフックは動かない（attach 時点の状態で表示される）。

```bash
# 手動で再均等化
tmux select-layout -t claude-parallel <LAYOUT名>   # 例: even-vertical
# または tmux 内で prefix =
```

レイアウト名はプロファイルの `LAYOUT` を参照。

### 症状8: PC 再起動後、claude-parallel が消えた

これは仕様。tmux サーバは WSL の中で動いているので、Windows を切ると WSL ごと死ぬ → tmux も死ぬ。
`start.sh` で立ち上げ直す。

---

## 切り分けが終わったら

問題が解決したら、テンプレやスクリプトに修正が必要だったかを振り返り、必要なら：
- テンプレ修正 → `install-hooks.sh` を4 worktree に再実行
- スクリプト修正 → 該当ファイルを edit
- ドキュメント不足ならこのファイル or `docs/SETUP.md` に追記
