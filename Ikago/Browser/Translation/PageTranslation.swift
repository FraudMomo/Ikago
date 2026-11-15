import Foundation
import NaturalLanguage
import Observation
@preconcurrency import Translation

/// A page shown translated: from and to which language.
struct PageTranslation {
    let source: Locale.Language
    let target: Locale.Language

    static func name(_ language: Locale.Language) -> String {
        let identifier = language.minimalIdentifier
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// Settings ▸ General ▸ Translation: unset follows the Mac's language.
    static func target(_ preferences: BrowserPreferences) -> Locale.Language {
        preferences.translationLanguage.map(Locale.Language.init(identifier:)) ?? Locale.current.language
    }

    /// The page's language: what its text reads as, or what it says it is.
    static func detect(_ texts: [String], declared: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(texts.joined(separator: " ").prefix(6000)))
        if let dominant = recognizer.dominantLanguage, (recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0) > 0.5 {
            return Locale.Language(identifier: dominant.rawValue)
        }
        return declared.isEmpty ? nil : Locale.Language(identifier: declared)
    }

    static func same(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode == b.languageCode && (a.languageCode?.identifier != "zh" || a.script == b.script || a.script == nil || b.script == nil)
    }

    /// Every language Apple's Translation offers on this Mac, by name; asked once per launch.
    @MainActor static func supported() async -> [Locale.Language] {
        if let supportedCache { return supportedCache }
        var seen = Set<String>()
        let languages = await fetchSupported()
            .filter { seen.insert($0.minimalIdentifier).inserted }
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        supportedCache = languages.isEmpty ? choices.map(Locale.Language.init(identifier:)) : languages
        return supportedCache ?? []
    }
    @MainActor private static var supportedCache: [Locale.Language]?
    private nonisolated static func fetchSupported() async -> [Locale.Language] { await LanguageAvailability().supportedLanguages }

    /// Languages offered in Settings (the Translation framework decides which pairs it can really do).
    static let choices: [String] = ["en", "es", "fr", "de", "it", "pt", "nl", "sv", "da", "nb", "fi", "pl", "tr", "ru", "uk", "ar", "he",
                                    "hi", "id", "th", "vi", "ja", "ko", "zh-Hans", "zh-Hant"]
}

/// One translation run for the active tab, shown as a card: first the languages (from the detected one, to the last
/// chosen), then the run itself by `TranslationHost` (Apple's on-device Translation framework, which asks to download
/// a language the first time).
@MainActor @Observable
final class TranslationJob: Identifiable {
    enum Phase: Equatable { case choosing, translating, done, failed(String) }
    let id = UUID()
    /// What the page reads as (nil: unknown, the framework detects it).
    let detected: Locale.Language?
    var source: Locale.Language?
    var target: Locale.Language
    let texts: [String]
    var phase = Phase.choosing
    var progress = 0.0
    @ObservationIgnored weak var controller: TabController?

    init(source: Locale.Language?, target: Locale.Language, texts: [String], controller: TabController?, phase: Phase = .choosing) {
        self.detected = source
        self.source = source
        self.target = target
        self.texts = texts
        self.controller = controller
        self.phase = phase
    }

    var configuration: TranslationSession.Configuration { .init(source: source, target: target) }

    /// Whether the page is already in the chosen language.
    var sameLanguage: Bool { source.map { PageTranslation.same($0, target) } ?? false }

    func start() {
        guard phase == .choosing, !sameLanguage else { return }
        progress = 0
        phase = .translating
    }

    func apply(_ batch: [(Int, String)], total: Int) async {
        guard phase == .translating, !batch.isEmpty, let script = TranslationScript.apply(batch) else { return }
        _ = try? await controller?.page?.evaluate(script)
        progress = min(1, progress + Double(batch.count) / Double(max(1, total)))
    }

    func finish() {
        guard phase == .translating else { return }
        phase = .done
        if let controller { controller.translation = PageTranslation(source: source ?? target, target: target) }
    }

    /// A failed run puts back whatever it had already translated.
    func fail(_ message: String) {
        phase = .failed(message)
        let page = controller?.page
        Task { @MainActor in _ = try? await page?.evaluate(TranslationScript.restore) }
    }
}
