import Foundation
import IKCEFBridge

/// Packaged English UI resources must retain native controls and multilingual webpage support.
@MainActor
enum CEFLocaleChecks {
    static func run(_ page: IKCEFPage, context: Int) async throws {
        let framework = Bundle.main.bundleURL.appending(path: "Contents/Frameworks/Chromium Embedded Framework.framework")
        let resources = framework.appending(path: "Resources")
        guard let bundle = Bundle(url: framework),
              FileManager.default.fileExists(atPath: resources.appending(path: "en.lproj/locale.pak").path),
              FileManager.default.fileExists(atPath: resources.appending(path: "icudtl.dat").path) else {
            throw CEFError.script("Packaged Chromium is missing its English fallback or Unicode data.")
        }
        for locale in ["sv", "ar", "zh_CN", "ja", "fr"] {
            guard let selected = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: [locale]).first,
                  let fallback = bundle.url(forResource: "locale", withExtension: "pak", subdirectory: nil, localization: selected),
                  fallback.deletingLastPathComponent().lastPathComponent == "en.lproj" else {
                throw CEFError.script("A missing Chromium UI locale did not fall back to English: \(locale).")
            }
        }
        let result = try await CEFSmoke.method(page, "Runtime.evaluate", ["contextId": context, "returnByValue": true,
            "expression": """
            (() => {
              const host = document.createElement('div');
              const texts = ['العربية', '中文', '日本語', 'Svenska åäö', 'हिन्दी'];
              document.body.append(host);
              try {
                const labels = texts.map(text => {
                  const label = document.createElement('p'); label.textContent = text; host.append(label); return label;
                });
                labels[0].dir = 'rtl';
                const input = document.createElement('input'); input.required = true; host.append(input);
                return {text: labels.every((label, index) => label.textContent === texts[index] && label.getBoundingClientRect().width > 0),
                  rtl: getComputedStyle(labels[0]).direction === 'rtl',
                  intl: Intl.DateTimeFormat.supportedLocalesOf(['ar', 'zh-CN', 'ja', 'sv', 'hi']).length === 5
                    && new Intl.NumberFormat('de-DE').format(1234.5) === '1.234,5',
                  control: !input.checkValidity() && input.validationMessage.length > 0};
              } finally { host.remove(); }
            })()
            """])
        guard let value = (result["result"] as? [String: Any])?["value"] as? [String: Any],
              ["text", "rtl", "intl", "control"].allSatisfy({ value[$0] as? Bool == true }) else {
            throw CEFError.script("Packaged Chromium lost multilingual text, international formatting or native control strings.")
        }
        print("CEF_LOCALES_OK english-fallback missing-system-locales multilingual-text rtl intl native-controls")
    }
}
