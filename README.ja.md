# Window Ward

[English](README.md) | [简体中文](README.zh-CN.md) | **日本語**

Window Ward は、選択したアプリケーションを誤って `Super+W` で閉じることから保護します。最初のキー操作では警告が表示され、設定した時間内に同じウィンドウで再度このショートカットを押すと、通常どおり閉じます。

[Omarchy Plugin Marketplace の Window Ward ページを見る](https://omarchyplugins.com/plugin.html?id=io.github.r404r.window-ward)。

![アプリケーションごとの操作を表示する Window Ward パネル](preview.png)

## 要件

- Omarchy 4.0.1 / Hyprland 0.56.2 で検証済み
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
tests/test-setup.sh
python -B bin/window-ward --help >/dev/null
cache_dir=$(mktemp -d); trap 'rm -rf "$cache_dir"' EXIT; PYTHONPYCACHEPREFIX="$cache_dir" python -m py_compile scripts/window_ward_integration.py scripts/setup scripts/uninstall
bash -n tests/*.sh
omarchy plugin validate "$PWD"
QMLLINT=${QMLLINT:-/usr/lib/qt6/bin/qmllint}
"$QMLLINT" -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
```

Omarchy の `qs.*` モジュールは Quickshell が実行時に解決するため、正しいインポートパスを指定していても、単体の `qmllint` では未解決インポートに関する警告が出る場合があります。これらの警告はベストエフォートとして扱ってください。リリース前の検証では、検証済みの Omarchy バージョンでプラグインを読み込み、ログを確認することも必要です。

[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。MIT ライセンスです。
