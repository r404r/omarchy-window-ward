# Window Ward

[English](README.md) | **简体中文** | [日本語](README.ja.md)

Window Ward 可保护指定应用免受意外触发 `Super+W` 的影响。首次按下会发出警告；在配置的时间间隔内，对同一窗口再次按下该快捷键则会正常关闭窗口。

[在 Omarchy 插件市场查看 Window Ward](https://omarchyplugins.com/plugin.html?id=io.github.r404r.window-ward)。

![显示按应用控制项的 Window Ward 面板](preview.png)

## 要求

- 兼容目标：Omarchy 4.0.1 / Hyprland 0.56.2；0.4.0 候选发布前仍须独立完成官方安装与真实运行验收。
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

添加已被规则覆盖的应用会保留原规则及启用状态，不会静默把组合规则替换为更窄的匹配。
未知或读取失败的状态不可编辑；成功刷新后才能修改规则。

### 确认时限与通知关闭

`window-ward timeout 3000` 将 `confirmWindowMs` 设为 3000 毫秒，即对同一窗口再次按
`Super+W` 可确认关闭的时间间隔。超时本身不会关闭应用。CLI 也用这个值请求通知时长，
但实际显示多久由通知服务决定。

2026-09-05 检查的 Omarchy 通知实现对普通通知设定至少 8 秒、最多 30 秒，鼠标悬停时
暂停倒计时。因此 3 秒确认可能对应更久的消息提示；提示仍可见，不代表确认仍有效。
这是宿主策略，不是 Window Ward 的设置，调低 `timeout` 不能覆盖宿主的最低显示时长。

右键点击消息即可立即关闭消息。左键也会在宿主处理默认动作/聚焦后关闭消息；Window Ward
没有绑定“关闭应用”动作。关闭消息不会清除独立的确认状态。插件复用宿主通知卡片，
不是带自定义关闭按钮的独立弹窗。这些交互细节可能随 Omarchy 升级变化。

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
python3 -B tests/test_backend.py
tests/test-setup.sh
python3 -B tests/test_integration.py
node tests/test-ward-model.mjs
tests/test-panel-theme.sh
tests/test-controller-smoke.sh # 需要 Quickshell；隔离的无窗口测试
python -B bin/window-ward --help >/dev/null
cache_dir=$(mktemp -d); trap 'rm -rf "$cache_dir"' EXIT; PYTHONPYCACHEPREFIX="$cache_dir" python -m py_compile scripts/window_ward_integration.py scripts/setup scripts/uninstall
bash -n tests/*.sh
omarchy plugin validate "$PWD"
QMLLINT=${QMLLINT:-/usr/lib/qt6/bin/qmllint}
"$QMLLINT" -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml WardController.qml
```

Omarchy 的 `qs.*` 模块由 Quickshell 在运行时解析，因此即使导入路径正确，独立运行的 `qmllint` 仍可能报告未解析导入警告。请将这些警告视为尽力而为；发布验证还要求在经验证的 Omarchy 版本上加载插件并检查日志。

参见 [CONTRIBUTING.md](CONTRIBUTING.md)。依据 MIT 许可证发布。

Node.js 仅为开发测试依赖。模型/静态测试不能证明真实面板生命周期或通知行为；每个最终
候选仍需官方安装与真实运行验收。无窗口 controller smoke 是具备 Quickshell 的机器上
必跑的本地发布前检查（Ubuntu CI 不提供 Quickshell）；需连同候选 SHA 保存输出，不能
用 Node/静态检查替代。生成的缓存必须放在插件目录之外。
