# Changelog

## 0.3.0 - Unreleased

- Migrate the CLI to Python's standard library for bounded subprocess output,
  descriptor-relative no-follow file access, private locks, and atomic writes.
- Reject symlinked installer files and use random temporary backup names.

## 0.1.0

- Initial configurable close-protection CLI.
- Explicit, reversible Hyprland setup and uninstall scripts.
- Omarchy bar widget and management panel MVP.
- Hardened configuration validation, concurrent writes, transactional setup/uninstall, and QML error reporting after independent A/B review.
