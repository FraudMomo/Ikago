import SwiftUI

extension CommandPaletteModel {
    func cancelCompletions() {
        completionActive = false
        completionTask?.cancel()
        completionTask = nil
        completions = []
    }

    func refreshCompletions() {
        completionTask?.cancel()
        completions = []
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let engine = state.searchEngine
        guard completionActive, state.browserPreferences.searchEngineAutocomplete == true,
              (1...256).contains(text.count),
              (try? AddressResolver.resolve(text, engine: engine)) == engine.searchURL(text) else { return }
        completionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                guard let provider = self?.completionProvider else { return }
                let values = try await provider(text, engine)
                try Task.checkCancellation()
                guard let self, self.query.trimmingCharacters(in: .whitespacesAndNewlines) == text,
                      self.state.searchEngine == engine, self.state.browserPreferences.searchEngineAutocomplete == true else { return }
                let previous = self.suggestions
                let chosen = previous.indices.contains(self.selection) ? previous[self.selection].kind : nil
                self.completions = values
                self.selection = chosen.flatMap { kind in self.suggestions.firstIndex { $0.kind == kind } } ?? 0
            } catch { /* Local suggestions and direct search still work offline. */ }
        }
    }

    func observeCompletionPreferences() {
        withObservationTracking {
            _ = state.searchEngine
            _ = state.browserPreferences.searchEngineAutocomplete
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshCompletions()
                self?.observeCompletionPreferences()
            }
        }
    }
}
