import SwiftUI
@preconcurrency import Translation

/// Runs the translation of the current job with Apple's Translation framework. The framework only runs from a view, so
/// this sits in the shell without drawing anything; it also shows the system's language download sheet when needed.
struct TranslationHost: View {
    let chrome: ChromeModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
            // Runs once the person picks Translate; closing the card (or a new one) cancels the run.
            .onChange(of: runKey, initial: true) { _, _ in
                configuration = chrome.translationJob?.phase == .translating ? chrome.translationJob?.configuration : nil
            }
            .translationTask(configuration) { session in await Self.run(session, chrome: chrome) }
    }

    private var runKey: String {
        guard let job = chrome.translationJob else { return "" }
        return "\(job.id)\(job.phase == .translating)"
    }

    /// Off the main actor: the session belongs to the framework's task; only the job (main actor) is touched, by await.
    private nonisolated static func run(_ session: TranslationSession, chrome: ChromeModel) async {
        guard let job = await chrome.translationJob, await job.phase == .translating else { return }
        let texts = job.texts
        do {
            try await session.prepareTranslation()
            let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: String($0)) }
            var batch: [(Int, String)] = []
            for try await response in session.translate(batch: requests) {
                guard let index = response.clientIdentifier.flatMap(Int.init) else { continue }
                batch.append((index, response.targetText))
                if batch.count >= 40 { await job.apply(batch, total: texts.count); batch = [] }
            }
            await job.apply(batch, total: texts.count)
            await job.finish()
        } catch {
            let message: String
            if let failure = error as? TranslationError {
                switch failure {
                case TranslationError.unsupportedLanguagePairing, TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage:
                    message = "This language pair isn’t available for on-device translation."
                default: message = "The page couldn’t be translated."
                }
            } else { message = error is CancellationError ? "Translation was cancelled." : "The page couldn’t be translated." }
            await job.fail(message)
        }
    }
}

/// Translate Page's card: from and to which language, then "Translating to English…", then "Translated to English"
/// with Show Original.
struct TranslationCard: View {
    let job: TranslationJob
    let colors: Palette
    let remember: (Locale.Language) -> Void
    let showOriginal: () -> Void
    let close: () -> Void
    @State private var languages: [Locale.Language] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(2) }
                }
                Spacer(minLength: 8)
                if job.phase == .done { Button("Show Original", action: showOriginal).buttonStyle(SettingsButtonStyle()).controlSize(.small) }
                ChromeButton(symbol: "xmark", help: "Close", colors: colors, size: 22, glass: false, action: close)
            }
            if job.phase == .choosing { chooser }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: 400)
        .foregroundStyle(colors.text)
        .modalSurface(colors, radius: Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .task { languages = await PageTranslation.supported() }
        .task(id: job.phase) {
            // Like a notification: the confirmation goes away on its own; choosing and failures stay until closed.
            if job.phase == .done {
                try? await Task.sleep(for: .seconds(7))
                if !Task.isCancelled { close() }
            }
        }
    }

    /// From [language] → To [language]   Translate
    private var chooser: some View {
        HStack(spacing: 8) {
            CompactMenu(value: job.source.map(PageTranslation.name) ?? "Detect Language", choices: sourceChoices)
                .help("The page’s language")
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(colors.tertiary)
            CompactMenu(value: PageTranslation.name(job.target), choices: targetChoices)
                .help("The language to translate into")
            Spacer(minLength: 6)
            Button("Translate") { job.start() }
                .buttonStyle(SettingsButtonStyle(prominent: true)).controlSize(.small)
                .disabled(job.sameLanguage)
        }
        .padding(.leading, 42)
    }

    private var sourceChoices: [MenuChoice] {
        var choices = [MenuChoice(title: "Detect Language", isOn: job.source == nil) { job.source = nil }]
        if let detected = job.detected {
            choices.append(MenuChoice(title: "\(PageTranslation.name(detected)) (Detected)", isOn: job.source == detected, separatorBefore: true) {
                job.source = detected
            })
        }
        for (index, language) in languages.enumerated() where language.minimalIdentifier != job.detected?.minimalIdentifier {
            choices.append(MenuChoice(title: PageTranslation.name(language), isOn: job.source?.minimalIdentifier == language.minimalIdentifier,
                                      separatorBefore: index == 0) { job.source = language })
        }
        return choices
    }

    private var targetChoices: [MenuChoice] {
        languages.map { language in
            MenuChoice(title: PageTranslation.name(language), isOn: language.minimalIdentifier == job.target.minimalIdentifier) {
                job.target = language
                remember(language)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        Group {
            if job.phase == .translating { ProgressView(value: max(0.04, job.progress)).progressViewStyle(.circular).controlSize(.small) }
            else {
                Image(systemName: job.phase == .done ? "checkmark" : job.phase == .choosing ? "translate" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(job.phase == .done || job.phase == .choosing ? .white : colors.text)
            }
        }
        .frame(width: 32, height: 32)
        .background(Circle().fill(job.phase == .done || job.phase == .choosing ? AnyShapeStyle(colors.accent) : AnyShapeStyle(colors.hover)))
    }

    private var target: String { PageTranslation.name(job.target) }
    private var source: String? { job.source.map(PageTranslation.name) }

    private var title: String {
        switch job.phase {
        case .choosing: "Translate This Page"
        case .translating: "Translating to \(target)…"
        case .done: "Translated to \(target)"
        case .failed: "Couldn’t translate"
        }
    }

    private var detail: String? {
        switch job.phase {
        case .choosing: job.sameLanguage ? "The page is already in \(target)." : "On this Mac. The page never leaves it."
        case .translating, .done: source.map { "From \($0), on this Mac" } ?? "On this Mac"
        case .failed(let message): message
        }
    }
}
