<p align="center">
  <img src="Ikago/Resources/AppIconSource.png" width="128" alt="Ikago icon">
</p>

<h1 align="center">Ikago</h1>

<p align="center">
  A lightweight, native macOS browser with Spaces, split view, web extensions and a choice of engine.
</p>

---

Ikago is written in **Swift 6 with AppKit and SwiftUI**. Pages render with **Apple's WebKit**
by default, or with **Chromium** through a prebuilt Chromium Embedded Framework (CEF). Either
way, Ikago draws all of its own interface.

> **Status:** Ikago is in active development and has not had a stable release yet. See the
> [roadmap](ROADMAP.md) for what is done and what is next.

## Features

**Browsing**
- **Two layouts:** a Sidebar, which can also collapse to a rail of icons or hide, and a Top Bar with Separate or Compact tabs
- **Spaces:** separate sets of tabs, pinned tabs and groups, each with its own colors and optionally its own website data
- **Split view:** up to four pages side by side as columns, rows or a grid, made by dragging a tab onto the page
- **Address field:** ranked suggestions from history, bookmarks, open tabs and search, with inline completion
- **Library:** History, Downloads and Bookmarks open as pages in tabs, with nested bookmark folders and a bookmarks bar

**Engines and extensions**
- **Engine choice:** WebKit or Chromium, chosen globally or per site, and sign-ins move with you when you switch
- **Extensions:** install from the Chrome Web Store, from a package file, or from Safari extensions on this Mac

**Security and privacy**
- **Privacy:** HTTPS by default, tracker blocking, blocked third-party cookies, phishing warnings and private windows
- **Passwords:** a built-in vault that encrypts each login to the Secure Enclave and asks for Touch ID before every fill

**Getting started**
- **Import:** bring bookmarks, history, open tabs and sign-ins from other browsers installed on this Mac

## Requirements

- macOS 26 or later on Apple Silicon
- Xcode 26 or later
- CMake and Ninja: `brew install cmake ninja`

The first build downloads the CEF distribution pinned in [`CEF/cef-lock.json`](CEF/cef-lock.json)
and verifies its checksum. Chromium itself is never compiled.

## Building

```sh
python3 scripts/build.py                  # build/Ikago.app: optimized, no test code
open build/Ikago.app
```

| Flavor | Output | Contents |
| --- | --- | --- |
| `release` (default) | `build/Ikago.app` | Optimized app with no test code |
| `debug` | `build/debug/Ikago.app` | Adds the scripted WebKit test driver |
| `checks` | `build/checks/Ikago.app` | Adds the Chromium runtime checks |

Builds are signed with your Apple Development identity when one is available, or ad hoc
otherwise. Set `IKAGO_SIGN_IDENTITY` to choose a specific identity. A team-signed build
stores its data in a protected app group container. An ad hoc build uses
`~/Library/Application Support/Ikago`.

To build and install into `/Applications`:

```sh
scripts/install.sh
```

## Project layout

| Path | Contents |
| --- | --- |
| `Ikago/App` | Entry point, app delegate, menus and keyboard shortcuts, protected storage |
| `Ikago/Browser` | Model and state with no views: tabs, Spaces, sessions, address suggestions, downloads, favicons, passwords |
| `Ikago/Engine` | Page engines behind the `WebTab` protocol: `Shared`, `WebKit` and `Chromium` |
| `Ikago/Extensions` | Web extension support for each engine, Web Store installs and package verification |
| `Ikago/Import` | Importing data from other browsers and exported files |
| `Ikago/UI` | Windows, sidebar, top bar, tabs, address field, overlays, settings and internal pages |
| `Ikago/Checks` | Runtime checks and the scripted test driver; excluded from release builds |
| `CEF` | Objective-C++ bridge to CEF, CMake build and the pinned SDK version |
| `scripts` | Build, packaging, installation, dependency updates and check runners |

[AGENTS.md](AGENTS.md) documents the architecture rules and conventions in detail. Read it
before making changes.

## Testing

Debug builds include a scripted test driver. With `IKAGO_TEST_MODE=1`, Ikago uses in-memory
website data and a temporary session folder, so your own profile is never touched.
`IKAGO_TEST_ACTIONS` drives the app through the same command paths as its menus:

```sh
IKAGO_TEST_MODE=1 IKAGO_TEST_ACTIONS="wait:4;new:https://example.com/;split;wait:3;dump;quit" \
  build/debug/Ikago.app/Contents/MacOS/Ikago
```

`dump` prints model and page state as a single `IKTEST {json}` line. All actions are
listed in [`TestDriver.swift`](Ikago/Checks/Debug/TestDriver.swift) and
[`TestDriver+Checks.swift`](Ikago/Checks/Debug/TestDriver+Checks.swift).

Run the WebKit feature checks against a local fixture server:

```sh
scripts/check-browser-features.sh
```

Run the Chromium suite. It uses disposable profiles and a mock keychain, and keeps every
Chromium window hidden:

```sh
python3 scripts/build.py --flavor checks
python3 scripts/run_chromium_checks.py
```

## Data and privacy

Ikago keeps your data on your Mac. It has no accounts, analytics or telemetry.

- History, sessions, download history and favicons are encrypted at rest with AES-GCM. The key is kept in the login Keychain.
- Saved passwords are encrypted to a Secure Enclave key, and each fill requires Touch ID or your Mac password.
- Phishing lists are downloaded and matched locally. The addresses you visit are never sent anywhere.
- Remote search suggestions are off unless you turn them on.

See [SECURITY.md](SECURITY.md) for the security model and how to report a vulnerability.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and
[AGENTS.md](AGENTS.md) first.

## License

Ikago is released under the [MIT License](LICENSE). Third-party components are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
