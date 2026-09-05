# Changelog

## 0.4.0 - Unreleased

- Normalize first-run defaults and preserve existing application rules when adding
  a focused application; reject ambiguous replacement instead of losing protection.
- Use session/window-scoped monotonic confirmation state and reject stale tokens.
- Reject special files before blocking reads and bound lock waits; keep compositor
  queries outside the configuration critical section.
- Separate panel view from controller/model logic; queue refreshes, reject stale or
  malformed status, and bound UI requests.
- Keep bindings and launcher coherent after uncertain installation writes; avoid
  writing Python caches into the shell-watched plugin checkout.
- Add negative/concurrency/transaction regressions and document notification
  dismissal and the difference between confirmation time and toast lifetime.

## 0.3.0 - Unreleased

- Migrate the CLI to Python's standard library for bounded subprocess output,
  descriptor-relative no-follow file access, private locks, and atomic writes.
- Reject symlinked installer files and use random temporary backup names.

## 0.1.0

- Initial configurable close-protection CLI.
- Explicit, reversible Hyprland setup and uninstall scripts.
- Omarchy bar widget and management panel MVP.
- Hardened configuration validation, concurrent writes, transactional setup/uninstall, and QML error reporting after independent A/B review.
