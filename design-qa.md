# Window Ward Panel Design QA

- Source visual truth: `../../research/2026-08-28-window-ward-panel-redesign/evidence/selected-option-2.png`
- Implementation screenshot: `../../research/2026-08-28-window-ward-panel-redesign/evidence/implementation-final.png`
- Full comparison: `../../research/2026-08-28-window-ward-panel-redesign/evidence/comparison-final.png`
- Multi-application stress capture: `../../research/2026-08-28-window-ward-panel-redesign/evidence/implementation-multi-app-scroll.png`
- Source pixels: 1513×1040; normalized comparison source: 525×355
- Implementation pixels: 525×355
- Intended logical component width: 420 px before monitor scaling and panel padding
- State: dark theme, protection enabled, one enabled Google Chrome rule

## Full-view comparison

The implementation preserves the selected direction's application-list-first hierarchy: compact identity and
status header, one protected-application row with a real system icon and read-only rule state, matcher detail,
then global protection and add-app actions. It intentionally uses Omarchy's native theme tokens and controls
instead of copying the generated mock's platform-neutral chrome.

A focused-region comparison was not required: the full 525×355 normalized pair keeps all type, icons,
controls, dividers, and matcher content readable at native capture density.

## Required fidelity surfaces

- **Fonts and typography:** Native Omarchy font family and Style scale replace the mock font by design.
  Title, section, application, metadata, and matcher levels are distinct; no visible clipping remains.
- **Spacing and layout rhythm:** Header, section, rule, dividers, and footer use consistent Style spacing.
  The count badge no longer collides with the section title, and persistent actions fit inside the viewport.
- **Colors and tokens:** Popup foreground/background/border, accent, muted text, and control fills come from
  Omarchy theme tokens. No hard-coded light-theme assumptions or bar-palette leakage remains.
- **Image quality and assets:** The shield and Chrome mark resolve from installed system icon themes at native
  resolution. No emoji, handcrafted SVG, placeholder, or stretched raster is used.
- **Copy and content:** Raw TSV was replaced by the user-facing app name, matcher count, matcher classes,
  global state, and plain actions. Per-app state is visibly read-only because the CLI does not support a
  per-rule toggle; the global control is the only interactive switch.

## Comparison history

### Pass 1 — blocked

- P1: shield icon did not resolve.
- P2: application count collided with the section heading.
- P2: header description clipped; the visual rhythm was too dense.
- P2: terminal-only instruction remained as an unattractive footer rather than an action.

### Pass 2 — blocked

- Fixed the shield by using the available symbolic system icon.
- Added a functional Add focused app action and verified opening the layer panel does not change the active
  Hyprland window address.
- Increased title hierarchy and improved the action footer.
- Remaining P2: count still collided and header copy still truncated.

### Pass 3 — blocked

- Replaced the fragile count spacer with a compact count badge beside the section heading.
- Shortened the header description to an unclipped status phrase.
- A/B review then found three P1/P2 issues: an uncapped non-scrollable multi-app list, busy state blocking
  Escape, and overly heavy secondary actions. A first whole-panel Flickable made controls scroll away, so it
  was rejected after an eight-application stress render.

### Pass 4 — passed

- Kept the header and global controls fixed while moving only applications into a height-capped ListView
  with an as-needed scrollbar; the eight-application capture proves the footer remains reachable.
- Removed busy key blocking, so Escape and navigation remain available while a process is running.
- Changed Refresh and Add focused app to low-emphasis native actions; keyboard focus remains visible.
- Namespaced Qt Controls so its ScrollBar cannot shadow `qs.Ui.Button`.
- Final comparison has no actionable P0, P1, or P2 visual differences. Native theme/control differences from
  the generated concept are intentional product constraints.

## Interaction evidence and residual checks

- Status JSON parsed successfully in the live Quickshell host and rendered the real Chrome rule.
- Opening the panel preserved the prior active window address, supporting the Add focused app behavior.
- CLI behavior and setup paths remain covered by automated shell tests; Refresh is safe and keyboard shortcut
  `R` is wired through `PanelKeyCatcher`.
- Real pointer activation of Refresh, Window protection, and Add focused app remains on the final user
  acceptance checklist because the latter two mutate the user's live configuration.

## Findings

No actionable P0/P1/P2 findings remain.

P3 follow-up: if the project later gains per-rule CLI enable/disable support, the read-only rule switch can
become interactive without changing the information architecture.

final result: passed
