# Window Ward

Window Ward protects selected applications from an accidental `Super+W`. The first press warns;
pressing the shortcut again on the same window within the configured interval closes it normally.

## Requirements

- Omarchy Quattro / Hyprland 0.56 or newer
- Bash, jq, util-linux (`flock`) and hyprctl

## Install

```sh
omarchy plugin add https://github.com/r404r/omarchy-window-ward.git --enable
~/.config/omarchy/plugins/io.github.r404r.window-ward/scripts/setup
hyprctl reload
hyprctl configerrors
```

The second command is intentionally explicit: Omarchy plugins do not have install hooks. It adds a
small marked block to the user-owned Hyprland bindings and backs the file up first.

## Configure

```sh
window-ward list
window-ward add-focused "My application"
window-ward remove application-id
window-ward timeout 3000
window-ward enable   # or: disable
window-ward doctor
```

Configuration is stored at `~/.config/window-ward/config.json`. Matching uses window class and
initialClass; Window Ward never needs browser URLs, profiles, titles, passwords or tokens.

## Remove

```sh
~/.config/omarchy/plugins/io.github.r404r.window-ward/scripts/uninstall
omarchy plugin remove io.github.r404r.window-ward
hyprctl reload
```

The uninstall script preserves the application rules.

## Development

```sh
tests/test-window-ward.sh
tests/test-setup.sh
bash -n bin/window-ward scripts/setup scripts/uninstall tests/*.sh
omarchy plugin validate "$PWD"
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under MIT.
