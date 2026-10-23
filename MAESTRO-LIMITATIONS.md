# Maestro — what is supported and what is not

Two parts. **Part A** is general Maestro, sourced from the official docs and from
the command surface that `cheat_sheet` generates from the flow parser. **Part B**
is what we proved ourselves on this project, which is where the sharp edges are.

Claim types are marked throughout:

- **[docs]** — stated in Maestro's official documentation (links at the bottom).
- **[parser]** — from the generated command surface, which `cheat_sheet` describes
  as "derived from the flow parser, so it is complete and current". Absence from
  that list means no first-class command exists.
- **[verified]** — proven on this machine, Maestro 2.10.0, evidence in run artifacts.

---

# Part A — General Maestro

## A1. Platforms

**[docs]**

| Platform | Supported | Notes |
|---|---|---|
| Android | yes | Emulators and physical devices |
| iOS | yes | Xcode Simulators and physical devices |
| Web | **Beta** | **Chromium only** |
| React Native | yes | Both Android and iOS |
| Flutter | yes | Via Semantics Tree; `identifier` needs Flutter 3.19+ |

**UI framework support [docs]:** Android Views and Jetpack Compose (via the
Accessibility layer); iOS UIKit and SwiftUI (via `accessibilityLabel` /
`accessibilityIdentifier`); web is framework-agnostic — React, Vue, Angular,
plain HTML all work the same way.

**Not supported:** desktop apps (Windows/macOS/Linux native), Firefox, Safari or
any non-Chromium browser, and mobile browsers.

## A2. Official web limitations

**[docs]** The web docs explicitly list these as unsupported:

- **Browser engines** — Chromium only.
- **Localization** — locale fixed to `en-US`.
- **Screen dimensions** — "custom screen sizes and viewport configurations cannot be configured".

⚠️ That last one is **out of date for 2.10.0**. `maestro test --help` on this
machine shows `--screen-size` documented as "(Web only) Set the size of the
headless browser", e.g. `--screen-size 1920x1080`. Treat the docs as lagging the
CLI here.

## A3. Official known issues

**[docs]**

**Cross-platform**
- Java version sensitivity — "may fail or behave unexpectedly when used with very old or very new Java versions". **17 or 21 recommended.**
- App launch fails on a wrong `appId`.

**Android**
- **`inputText` supports ASCII only — no Unicode.** Big one for non-English test data.
- Maestro installs a **companion APK**; devices that block it (hardened/MDM-locked enterprise devices) **are not supported**.
- WebView content may be invisible to accessibility APIs unless Chrome DevTools inspection is enabled.
- `clearState` fails on some Oppo/Realme devices (disable USB app verification).
- "Failed to activate device" on some physical devices, notably Redmi (reset Developer Settings).
- Google Maps screens may crash **on Maestro Cloud** (missing legacy HTTP libs in `google_apis` images).

**iOS**
- `hideKeyboard` "does not always dismiss the keyboard" — iOS has no native dismissal API.
- UITableView/UICollectionView scroll-based pagination behaves unpredictably, due to XCTest bugs triggering unintended data loads.

**Maestro Cloud**
- **20-minute soft limit per test execution.** Split long suites into parallel flows.

## A4. What Maestro can do — the full command set

**[parser]** Complete list for 2.10.0, grouped.

**Interaction** — `tapOn`, `doubleTapOn`, `longPressOn`, `swipe`, `scroll`,
`scrollUntilVisible`, `inputText`, `eraseText`, `pressKey`, `pasteText`,
`hideKeyboard`, `back`

**Assertions** — `assertVisible`, `assertNotVisible`, `assertTrue`,
`assertScreenshot` (visual regression, 2.2.0+), `assertDarkMode`, `assertLightMode`

**Waiting** — `extendedWaitUntil` (`visible` / `notVisible`), `waitForAnimationToEnd`

**App lifecycle** — `launchApp`, `stopApp`, `killApp`, `clearState`,
`clearKeychain`, `openLink`, `setPermissions`

**Control flow** — `runFlow` (file or inline, with `when` conditions and `env`),
`repeat` (`times` or `while`), `retry` (max 3), `onFlowStart` / `onFlowComplete`

**Scripting** — `runScript` (JS file), `evalScript` (inline expression)

**Device state** — `setLocation`, `travel`, `setOrientation`, `setAirplaneMode`,
`toggleAirplaneMode`, `setDarkMode`, `toggleDarkMode`

**Capture** — `takeScreenshot` (with `cropOn`, 2.2.0+), `startRecording`, `stopRecording`

**Clipboard** — `copyTextFrom`, `setClipboard` (2.1.0+), `pasteText`

**Media** — `addMedia` (device gallery / camera roll — **not** a file upload)

**Random data** — `inputRandomText`, `inputRandomNumber`, `inputRandomEmail`,
`inputRandomPersonName`, `inputRandomCityName`, `inputRandomCountryName`,
`inputRandomColorName`

**AI (experimental, `optional: true` by default)** — `assertWithAI`,
`assertNoDefectsWithAI`, `extractTextWithAI`

**Selectors** — `text`, `id`, `index`, `enabled`, `checked`, `focused`,
`selected`, `point`, `width`/`height`/`tolerance`, `traits`, `css`, and the
relative matchers `below`, `above`, `leftOf`, `rightOf`, `childOf`,
`containsChild`, `containsDescendants`

## A5. What Maestro cannot do

**[parser]** — no such command exists, on any platform:

| Missing | Impact |
|---|---|
| **File upload** | No command at all. `addMedia` is a device-gallery command, not a web/file-input upload. This is the single biggest web gap. |
| **iframe switching** | Content inside iframes is not addressable |
| **Tab / window switching** | Single-context only |
| **Cookies** | No get/set/delete; only wholesale `clearState` |
| **Network interception / mocking / stubbing** | No request stubbing, no offline simulation on web |
| **HTTP headers, basic auth** | Cannot pre-authenticate via headers |
| **Native JS dialogs** | No `alert` / `confirm` / `prompt` handling |
| **Hover** | Only tap/double-tap/long-press |
| **Right-click / context menu** | — |
| **HTML5 drag-and-drop between elements** | `swipe` exists but is a gesture, not a DnD event sequence |
| **Native `<select>` handling** | No `selectOption` |
| **Download verification** | Cannot assert a file finished downloading |
| **Browser forward / reload** | `back` is Android-only; no reload command |
| **Modifier key combos** | `pressKey` is a fixed enum (`Enter`, `Tab`, `Escape`, `Backspace`, TV/remote keys). No Ctrl+A, no arrow keys for desktop |
| **XPath** | `css` exists; there is no `xpath` |
| **Reading a value out of JS into a variable** | `evalScript`/`runScript` set `${output.x}` but run in Maestro's engine, not the page (see B2) |

## A6. Platform matrix for platform-specific commands

**[docs]**

| Command | Android | iOS | Web |
|---|---|---|---|
| `launchApp` permissions / `setPermissions` | yes | yes | no |
| `addMedia` | yes | yes | no |
| `back` | yes | **no** | **no** |
| `clearKeychain` | no | yes | no |
| `setOrientation` | yes | yes | **no** |
| `setAirplaneMode` / `toggleAirplaneMode` | yes | no effect | no effect |
| `setLocation` / `travel` | yes (API 31+) | yes | no |
| `killApp` | real process death | alias for `stopApp` | alias for `stopApp` |
| `hideKeyboard` | yes | flaky **[docs]** | n/a |
| `clearState` | yes | yes | yes |
| `--headless`, `--screen-size` | no | no | yes |

---

# Part B — Verified on this project

Maestro 2.10.0, Chromium, the HCM workbench-ui. Everything below is **[verified]**.

## B1. File upload is impossible on web

No command exists, and every workaround failed against a real dropzone:

1. Assign `input.files` from a base64-built `File` + dispatch bubbling `change` — returns true, `input.files.length === 1`, component ignores it.
2. Synthetic `dragenter`/`dragover`/`drop` with the same `DataTransfer`, up four ancestors — ignored.
3. Invoke the component's React `onDrop`/`onChange` directly via `__reactProps$*`, up eight ancestors — a handler genuinely ran (the condition returned the invoked count and passed) — still ignored.
4. Tap "Browse in my files" and answer the native Windows dialog from a parallel process — **the dialog never appears**; ChromeDriver intercepts the browser file chooser, so there is no OS window to drive.

**Use Playwright `set_input_files` or Selenium `send_keys` for this one step, or hit the API.**

## B2. The two JavaScript engines

- `runScript` / `evalScript` run in Maestro's own **graaljs** engine — **no DOM**. Browser JS dies with `TypeError: undefined is not a function`.
- **`assertTrue` runs real JS in the page.** `document`, `atob`, `DataTransfer`, `querySelectorAll`, and IIFEs with side effects all work. Control-tested: `assertTrue: "false"` correctly fails.

So `assertTrue` is the only way to execute page JS — but it can only return a boolean.

## B3. Scrolling and hit-testing

- **No auto-scroll.** `tapOn`/`assertVisible` only match what is already in the viewport.
- **`scrollUntilVisible` is unreliable** — reported "no visible element found" for a button the failure screenshot showed fully on screen, and kept failing after raising `timeout`, lowering `visibilityPercentage` to 80, and setting `waitToSettleTimeoutMs`. Two plain `- scroll` commands are dumber and reliable.
- **`swipe: from: <element>` does not scroll a scrollable modal** — it scrolls the page behind it. Use a coordinate swipe: `start: "48%, 70%"` → `end: "48%, 30%"`.
- **Sticky headers silently swallow taps.** The element is in the viewport but visually covered; the tap hits the header and **Maestro reports it as successful**. The failure surfaces later as an unrelated assertion.

## B4. Selector behaviour

- **`text:` is full-string, literal-OR-regex.** `"...(SMC)"` with raw parentheses **passes** (literal path); `"Seasonal Malaria"` as a substring **fails**. Metacharacters need no escaping.
- **Trailing spaces are real and invisible** — this app renders `"Rows Per Page: "`. Use `"prefix.*"` regexes.
- **A `css:` selector that matches nothing hangs 30+ minutes** instead of failing. Avoid `css:` entirely.
- Generated ids drift — the same buttons went from `btn-67/68/69` to `btn-225/226/227` within one session. Prefer `text:` or semantic ids, or anchor with `below:` / `childOf:`.
- `id` + `text` compound selectors work, and are how you assert a field's *value* rather than a same-named heading elsewhere.

## B5. Tooling traps

- **`optional: true` lies.** An optional `assertTrue` reports `COMPLETED` even when the condition is false — a probe battery containing both `length === 1` and `length > 1` passed every line. Keep diagnostic assertions non-optional.
- **`--test-output-dir` + `--flatten-debug-output` silently writes nothing.** Use `--debug-output` + `--flatten-debug-output`.
- **`--output` does not create parent directories** — throws `FileNotFoundException`.
- **`takeScreenshot` paths differ by invocation.** Under the CLI they resolve inside the run folder (`<run>/<flow>/takeScreenshot/<path>.png`); under the MCP tools they are cwd-relative. Same YAML, two destinations.
- **The hierarchy dump drops zero-size and freshly appended nodes**, so you cannot smuggle diagnostics out via an injected `<div>`.
- **Every `-e` value is written in plain text** into `commands.json` and `maestro.log`, including passwords, even for flows that never reference them.
- **`file://` URLs fail** — the web driver prepends `https://`.
- **The Maestro MCP server caches a dead browser session** and returns `invalid session id` forever; killing chromedriver does not help. Fall back to the CLI.

## B6. Getting a hierarchy dump on demand

There is no dump command. End the flow with a deliberately impossible wait:

```yaml
- extendedWaitUntil:
    visible:
      text: "zzz-force-a-hierarchy-dump-zzz"
    timeout: 10000
```

Maestro writes `screen-hierarchy/step-NNN-*.json` for the failing step. Use
`text:`, never `css:`, which would hang instead of failing.

---

## Sources

- [Supported platforms](https://docs.maestro.dev/get-started/supported-platform.md)
- [Web browser support](https://docs.maestro.dev/get-started/supported-platform/web-browser.md)
- [Known issues](https://docs.maestro.dev/extra-materials/troubleshooting/known-issues.md)
- [Maestro Cloud limits](https://docs.maestro.dev/maestro-cloud/limits.md)
- Command surface: `cheat_sheet` (Maestro 2.10.0) and `maestro test --help`
