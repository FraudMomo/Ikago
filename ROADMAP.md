# Roadmap

Ikago is a native macOS browser built around a calm, keyboard-friendly workspace: vertical
or top tabs, Spaces, split view and a command bar, with web extensions and a choice of
engine. This roadmap describes where the project is and where it is going. It is a
statement of direction, not a schedule.

**Status:** ✅ Complete · 🚧 In progress · 🗓 Planned

---

## Phase 1: Native browser foundation ✅

A complete everyday browser on Apple's WebKit, written in Swift 6 with AppKit and SwiftUI.

- Two layouts, Sidebar and Top Bar, with Separate or Compact tabs and adjustable bar sizes
- Spaces, each with its own tabs, pinned tabs, groups, colors and optionally its own website data
- Split view with up to four panes as columns, rows or a grid, built by dragging tabs onto the page
- Tab groups, pinned essentials, a bookmarks bar, and nested bookmark folders
- Address field with ranked suggestions from history, bookmarks, open tabs and search
- Built-in History, Downloads, Bookmarks and Settings pages
- Atomic session save and restore with a backup, plus optional tab hibernation
- Full screen with a hiding sidebar and top bar, and a media player in the sidebar
- Liquid Glass design that respects Reduce Motion and Reduce Transparency

## Phase 2: Extensions ✅

Run web extensions through WebKit's native `WKWebExtension` runtime.

- Install from the Chrome Web Store, from a local package, or from a Safari extension on this Mac
- Web Store packages are signature-verified (CRX3) before they are unpacked
- A permission review before install, and again when an update asks for more access
- Daily update checks that keep the working copy if an update fails
- Compatibility checks that explain what an extension can't do here
- A site-and-extensions popover in the address field

## Phase 3: Chromium engine ✅

Chromium is an optional second engine, embedded through a prebuilt CEF framework. Ikago
still draws every part of the interface.

- Choose the engine per launch, or per site with your own rules
- Sign-ins carry over when you switch engines or move a site to the other engine
- DevTools docked beside the page; no Chromium windows ever appear
- Web Store extensions sync between engines
- Out-of-process update pipeline: download, verify, build, run the check suite, then install
- Media playback translation for codecs the open-source Chromium build cannot decode

## Phase 4: Security and privacy ✅

- Permissions fail closed: camera, microphone and downloads are denied unless you allow them
- HTTPS by default, with per-site exceptions you choose
- Tracker blocking, blocked third-party cookies and partitioned third-party storage on both engines
- Phishing warnings from look-alike detection and public lists, matched locally on this Mac
- History, sessions, download history and favicons encrypted at rest, with the key in the Keychain
- All browsing data in a team-protected app group container
- A password vault that encrypts each login to a Secure Enclave key, with Touch ID for every fill
- Private windows that leave nothing on disk

## Phase 5: Import ✅

- Finds installed browser profiles automatically and imports with one click
- Bookmarks, history, open tabs, tab groups and website logins where the source format allows
- Exported files: bookmark HTML/JSON/plist, session files, and cookie exports
- Password import from a CSV export, after which the export file is overwritten and deleted
- Reports unsupported or encrypted data instead of claiming a complete import

---

## Phase 6: Passwords and identity 🚧

- Save and update logins from sign-in forms
- Import through Apple's Credential Exchange
- Passkeys, which depend on Apple's browser passkey entitlement
- Manual end-to-end verification of Touch ID and real sign-in flows

## Phase 7: Extension compatibility 🗓

Broader support for unmodified extensions through shared browser capabilities, never
per-extension patches.

- A published capability matrix: implemented, partial and unavailable APIs
- Runtime update events, offscreen documents and consistent extension resource origins
- Native messaging between extensions and their companion Mac apps
- On Chromium: popups that see the current tab, tab and window creation, toolbar icons and
  badges, context menus, side panels and commands
- A permission sheet for Web Store installs on Chromium

## Phase 8: Agent access 🗓

Let AI agents browse with Ikago through a built-in Model Context Protocol server, safely and
visibly.

- Off by default, local connections only, and protected by a token
- Tools for tabs, navigation, reading page text and structure, clicking, typing, scrolling and screenshots
- Script evaluation behind a separate permission
- Driven tabs are always marked, with a Stop button and an activity log
- An optional agent Space with its own website data, so personal sign-ins stay opt-in

## Phase 9: Distribution 🗓

- Developer ID signing and notarization
- App updates through a signed update feed
- Bundled Chromium credits and third-party notices
- App Sandbox review, opt-in crash reporting and a privacy policy
- Private vulnerability reporting and an independent security review
- Accessibility, keyboard and visual regression passes across both layouts
