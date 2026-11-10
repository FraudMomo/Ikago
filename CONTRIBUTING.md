# Contributing to Ikago

Thanks for your interest in Ikago. Bug reports, fixes and focused improvements are all
welcome.

## Before you start

- Read [AGENTS.md](AGENTS.md). It holds the architecture rules, the engine-specific pitfalls
  and the design conventions every change is expected to follow.
- For a larger change, open an issue first so the approach can be agreed before you write code.
- Report security issues privately, as described in [SECURITY.md](SECURITY.md).

## Development

```sh
python3 scripts/build.py --flavor debug   # build with the scripted test driver
scripts/check-browser-features.sh         # WebKit feature checks
python3 scripts/build.py --flavor checks  # build with the Chromium runtime checks
python3 scripts/run_chromium_checks.py    # Chromium suite on disposable profiles
```

## Guidelines

- **Keep changes small and focused.** One topic per pull request.
- **Follow the structure.** Keep files under 300 lines and views small and single-purpose,
  and put each type in the folder that owns its concern.
- **Use public APIs.** Use public WebKit and CEF APIs. Private SPI needs a strong
  justification, a `// SPI:` comment and an entry in AGENTS.md §7.
- **Never weaken security to make a site work.** That means permission prompts, the popup
  blocker, TLS checks, script isolation and storage protection.
- **Support both engines and both layouts.** A feature should work on WebKit and Chromium,
  and in the Sidebar and Top Bar layouts, or say clearly where it doesn't.
- **Build without warnings.** New code should compile cleanly in the debug flavor.
- **Verify in the running app.** Add a check to the test driver when the behaviour can be
  scripted.
- **Never commit generated or personal files.** That includes build output, profiles,
  signing material, API keys and user data.

## Pull requests

Describe the user-visible change, any security impact, and how you verified it. Include
screenshots for interface changes, in both light and dark mode.

By contributing, you agree that your contributions are licensed under the project's
[MIT License](LICENSE).
