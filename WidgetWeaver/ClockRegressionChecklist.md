# Clock regression checklist (manual)

This checklist exists to protect the **Home Screen clock widget** invariants while the editor becomes context-aware.

Scope guardrails:

- Do **not** change `WidgetWeaverWidget/Clock/*` timing/ticking logic.
- Editor tool-suite work must not regress clock widget behaviour (minute accuracy, seconds hand, caching).

---

## 1) Feature flag smoke test (editor tool suite)

Feature flag key:

- `widgetweaver.feature.editor.contextAwareToolSuite.enabled`

Defaults:

- When the key is **absent**, the app uses the default in `FeatureFlags.defaultContextAwareEditorToolSuiteEnabled`.
- When the key is present, its boolean value forces the mode.

Simulator toggle (booted simulator):

```sh
# Disable context-aware tool filtering (legacy tools)
xcrun simctl spawn booted defaults write com.conornolan.WidgetWeaver \
  widgetweaver.feature.editor.contextAwareToolSuite.enabled -bool false

# Re-enable context-aware tool filtering
xcrun simctl spawn booted defaults write com.conornolan.WidgetWeaver \
  widgetweaver.feature.editor.contextAwareToolSuite.enabled -bool true

# Return to default behaviour (delete the override)
xcrun simctl spawn booted defaults delete com.conornolan.WidgetWeaver \
  widgetweaver.feature.editor.contextAwareToolSuite.enabled
