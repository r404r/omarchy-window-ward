# Window Ward

[English](README.md) | [简体中文](README.zh-CN.md) | **日本語**

Window Ward は、選択したアプリケーションを誤って `Super+W` または `Super+Q` で閉じることから保護します。最初の保護対象の終了操作では警告が表示され、設定した時間内に同じウィンドウでどちらかのショートカットを再度押すと、通常どおり閉じます。

[Omarchy Plugin Marketplace の Window Ward ページを見る](https://omarchyplugins.com/plugin.html?id=io.github.r404r.window-ward)。

![アプリケーションごとの操作を表示する Window Ward パネル](preview.png)

## 要件

- 互換性の対象：Omarchy 4.0.4 / Hyprland 0.56.2。0.4.2 候補はリリース前に、
  公式インストール経路と実環境での独立した検証が必要です。
- Python 3.10 以降および hyprctl

## インストール

```sh
omarchy plugin add https://github.com/r404r/omarchy-window-ward.git --enable
~/.config/omarchy/plugins/io.github.r404r.window-ward/scripts/setup
hyprctl reload
hyprctl configerrors
```

2 番目のコマンドをあえて明示しているのは、Omarchy プラグインにはインストールフックがないためです。このコマンドは、ユーザー所有の Hyprland バインディングに識別可能な小さなブロックを追加し、先にそのファイルのバックアップを作成します。
既存の `~/.local/bin/window-ward` ファイル、または変更済みの管理対象ブロックは置き換えません。
この管理対象ブロックは `Super+W` と `Super+Q` の両方を明示的に管理します。`Super+Q` がまだ標準の終了ショートカットではない古い Omarchy では、setup によって保護対象の終了ショートカットとして追加されます。個人用の `Super+Q` バインドがある場合は、setup の実行前に競合を解消してください。

0.4.0 から更新した後は setup コマンドを再実行し、その後 `hyprctl reload` を実行してください。setup は以前の W のみの管理対象ブロックと完全一致する場合だけ認識し、バックアップ後に W と Q の両方を保護するブロックへアトミックに移行します。編集済みまたは不明なブロックは引き続き拒否します。

0.4.1 以降からダウングレードする前に、現在のバージョンの `scripts/uninstall` を実行してください。0.4.0 のアンインストーラーは新しい 2 ショートカットの管理対象ブロックを認識できません。その後、旧バージョンを再インストールして setup を再実行してください。

## 設定

```sh
window-ward list
window-ward add-focused "My application"
window-ward set-app-enabled application-id false  # or: true
window-ward remove application-id
window-ward timeout 3000
window-ward enable   # or: disable
window-ward doctor
```

設定は `~/.config/window-ward/config.json` に保存されます。照合にはウィンドウの class と initialClass を使います。Window Ward が必要とするのはブラウザーの URL、プロファイル、タイトル、パスワード、トークンではありません。
設定入力は 48 KiB、`status` JSON レスポンスは 64 KiB に制限されています。
パネルは各アイコンを、アプリケーションルール ID、完全一致する class、initialClass の順に、アクティブなシステムアイコンテーマから自動的に解決します。最後のフォールバックは汎用アプリケーションアイコンです。
リストの各行は個別に一時停止でき、2 回目の確認クリック後に削除できます。

既存ルールで保護されているアプリを追加しても、元のルールと有効状態を保持します。
グループ化されたルールを狭い一致条件へ黙って置き換えません。状態の読み込みが失敗した
場合は編集できません。更新に成功してからルールを変更してください。

### 確認時間と通知の消去

`window-ward timeout 3000` は `confirmWindowMs` を 3000 ミリ秒に設定します。同じ
ウィンドウで保護対象の終了ショートカットを再度押して閉じることを確認できる時間です。時間が過ぎただけで
アプリが閉じることはありません。CLI は通知にも同じ時間を要求しますが、実際の表示時間は
通知サーバーが決めます。

2026-09-05 に調べた Omarchy の実装では、通常通知は最低 8 秒、最大 30 秒表示され、
マウスを重ねるとカウントダウンが停止します。したがって 3 秒の確認時間より通知が長く
残ることがあります。表示中でも確認が有効とは限りません。これはホスト側の方針であり、
Window Ward の `timeout` を短くしても最低表示時間は変更できません。

通知を右クリックすると直ちに消せます。左クリックでもホストの既定アクション／フォーカス
処理後に消えますが、Window Ward はアプリを閉じるアクションを登録していません。
通知を消しても独立した確認状態は解除されません。プラグインはホストの通知カードを
再利用しており、独自の閉じるボタンを備えたポップアップではありません。
この操作は Omarchy の更新で変わる可能性があります。

## 削除

```sh
~/.config/omarchy/plugins/io.github.r404r.window-ward/scripts/uninstall
omarchy plugin remove io.github.r404r.window-ward
hyprctl reload
```

常に `omarchy plugin remove` より**前に** `uninstall` を実行してください。そうしないと、グローバルバインディングが削除済みプラグインを指したままになります。先にリポジトリを削除してしまった場合は、`~/.config/hypr/bindings.lua` から印の付いた `WINDOW WARD` ブロックを削除し、その後 `hyprctl reload` を実行してください。アンインストールスクリプトはアプリケーションルールを保持します。
ぶら下がったインストーラーリンクは、シンボリックリンクであることを確認した後にのみ削除してください。

```sh
[[ -L ~/.local/bin/window-ward ]] && rm ~/.local/bin/window-ward
```

## 開発

```sh
tests/test-window-ward.sh
python3 -B tests/test_backend.py
tests/test-setup.sh
python3 -B tests/test_integration.py
node tests/test-ward-model.mjs
tests/test-panel-theme.sh
tests/test-controller-smoke.sh # Quickshell 必須・隔離されたヘッドレステスト
python -B bin/window-ward --help >/dev/null
cache_dir=$(mktemp -d); trap 'rm -rf "$cache_dir"' EXIT; PYTHONPYCACHEPREFIX="$cache_dir" python -m py_compile scripts/window_ward_integration.py scripts/setup scripts/uninstall
bash -n tests/*.sh
omarchy plugin validate "$PWD"
QMLLINT=${QMLLINT:-/usr/lib/qt6/bin/qmllint}
"$QMLLINT" -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml WardController.qml
```

Omarchy の `qs.*` モジュールは Quickshell が実行時に解決するため、正しいインポートパスを指定していても、単体の `qmllint` では未解決インポートに関する警告が出る場合があります。これらの警告はベストエフォートとして扱ってください。リリース前の検証では、検証済みの Omarchy バージョンでプラグインを読み込み、ログを確認することも必要です。

[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。MIT ライセンスです。

Node.js は開発テストのみの依存関係です。モデル／静的テストは実際のパネルの
ライフサイクルや通知動作を保証しません。最終候補ごとに公式インストールと実環境での
検証が必要です。ヘッドレス controller smoke は Quickshell がある環境での必須の
ローカル公開前チェックです（Ubuntu CI には Quickshell がありません）。候補 SHA と
出力を保存し、Node／静的テストで代用しないでください。生成キャッシュはプラグインの
ディレクトリ外に置いてください。
