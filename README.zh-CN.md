# Window Ward

[English](README.md) | **简体中文** | [日本語](README.ja.md)

Window Ward 可保护指定应用免受意外触发 `Super+W` 的影响。首次按下会发出警告；在配置的时间间隔内，对同一窗口再次按下该快捷键则会正常关闭窗口。

[在 Omarchy 插件市场查看 Window Ward](https://omarchyplugins.com/plugin.html?id=io.github.r404r.window-ward)。

![显示按应用控制项的 Window Ward 面板](preview.png)

## 要求

- 已在 Omarchy 4.0.1 / Hyprland 0.56.2 上验证
- Python 3.10 或更高版本，以及 hyprctl

## 安装

```sh
omarchy plugin add https://github.com/r404r/omarchy-window-ward.git --enable
~/.config/omarchy/plugins/io.github.r404r.window-ward/scripts/setup
hyprctl reload
hyprctl configerrors
```

第二条命令特意写明：Omarchy 插件没有安装钩子。它会向用户拥有的 Hyprland 绑定添加一个带标记的小块，并先备份该文件。
它拒绝替换现有的 `~/.local/bin/window-ward` 文件或已修改的受管理块。

## 配置

```sh
window-ward list
window-ward add-focused "My application"
window-ward set-app-enabled application-id false  # or: true
window-ward remove application-id
window-ward timeout 3000
window-ward enable   # or: disable
window-ward doctor
```

配置存储在 `~/.config/window-ward/config.json`。匹配使用窗口 class 和 initialClass；Window Ward 从不需要浏览器 URL、配置文件、标题、密码或令牌。
配置输入上限为 48 KiB，`status` JSON 响应上限为 64 KiB。
面板会根据应用规则 ID、其精确的 class 和 initialClass 值，使用当前活跃的系统图标主题自动解析每个图标；通用应用图标是最后的回退选项。
每个列表行都可单独暂停，也可在再次点击确认后移除。

## 移除

```sh
~/.config/omarchy/plugins/io.github.r404r.window-ward/scripts/uninstall
omarchy plugin remove io.github.r404r.window-ward
hyprctl reload
```

务必在 `omarchy plugin remove` **之前**运行 `uninstall`；否则全局绑定会指向已移除的插件。
如果仓库先被移除，请从 `~/.config/hypr/bindings.lua` 删除带标记的 `WINDOW WARD` 块，然后运行 `hyprctl reload`。卸载脚本会保留应用规则。
仅在确认安装程序链接是符号链接后，再移除悬空链接：

```sh
[[ -L ~/.local/bin/window-ward ]] && rm ~/.local/bin/window-ward
```

## 开发

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

Omarchy 的 `qs.*` 模块由 Quickshell 在运行时解析，因此即使导入路径正确，独立运行的 `qmllint` 仍可能报告未解析导入警告。请将这些警告视为尽力而为；发布验证还要求在经验证的 Omarchy 版本上加载插件并检查日志。

参见 [CONTRIBUTING.md](CONTRIBUTING.md)。依据 MIT 许可证发布。
