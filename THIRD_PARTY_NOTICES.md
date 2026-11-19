# Third-party notices

Ikago's own source code is released under the [MIT License](LICENSE). It builds on the
following third-party components, each under its own license.

## Rendering engines

- **WebKit** is Apple's web engine. It ships with macOS and is not distributed with Ikago.
- **Chromium Embedded Framework (CEF) and Chromium**: the build downloads the prebuilt CEF
  distribution pinned in [`CEF/cef-lock.json`](CEF/cef-lock.json). CEF is distributed under a
  BSD-style license, and Chromium under its BSD-style license plus those of its third-party
  dependencies. The license texts are included in the downloaded distribution, in
  `.cef/distribution`.

## Bundled and linked components

- **SVT-AV1** ([`CEF/svtav1-lock.json`](CEF/svtav1-lock.json)) is statically linked for media
  translation. It uses the BSD-3-Clause-Clear license with the Alliance for Open Media
  royalty-free patent license.
- **Sparkle** ([`CEF/sparkle-lock.json`](CEF/sparkle-lock.json)) installs updates in downloaded builds. It is
  distributed under the MIT License, with the notices for its bundled components in its license file.
- **Public Suffix List** ([`Ikago/Resources/public_suffix_list.dat`](Ikago/Resources/public_suffix_list.dat))
  is used to match passwords to sites. It is published by the Mozilla Foundation under the
  Mozilla Public License 2.0.

## Logos

- The **WebKit logo** (`Ikago/Resources/webkit-logo.svg`) is the WebKit project's artwork from webkit.org, © Apple Inc.,
  with its colors converted to sRGB. It only identifies the WebKit engine; WebKit is a trademark of Apple Inc.
- The **agent marks** in `Ikago/Resources/agent-logos/` come from [Simple Icons](https://simpleicons.org) 16.38
  (CC0 1.0; the GitHub Copilot mark under MIT). They only show which agent is connected. Claude is a trademark of
  Anthropic, PBC; OpenAI and Codex of OpenAI; Gemini of Google LLC; Cursor of Anysphere, Inc.; GitHub Copilot of
  GitHub, Inc.; Windsurf and Zed of their owners. Ikago isn't affiliated with or endorsed by any of them.
- The **Chromium logo** is drawn in code from the Chromium project's artwork, © The Chromium Authors, under
  [CC BY 2.5](https://creativecommons.org/licenses/by/2.5/). It only identifies the Chromium engine. Chromium is a
  trademark of Google LLC.
- **WebKit** is a trademark of Apple Inc. Its logo isn't free to reuse, so Ikago identifies WebKit with its own
  original mark instead.

## Showcase image

`docs/showcase.jpg` shows Wikipedia's [Octopus](https://en.wikipedia.org/wiki/Octopus) article. Its text is by
Wikipedia contributors under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), and its images are
under the licenses listed on Wikipedia. The site icons in the sidebar belong to their owners.

## Data downloaded at runtime

These lists are downloaded to the user's Mac and matched locally. They are not distributed
with Ikago.

- **phishunt.io** phishing list, under CC0
- **PhishDestroy** main phishing list, under the MIT License

## Distribution

A distributed build must include Chromium's generated credits and the license notices
above. The build copies them into the app (`Contents/Resources/Acknowledgements`), and Settings ▸ About lists them. Browser extensions that a user installs keep their own licenses and are not
distributed with Ikago.
