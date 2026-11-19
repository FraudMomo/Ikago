import AppKit

/// Addresses and cards on Chromium (`FormFillScript`, in the password world of the top document). As with passwords,
/// the page never talks to Ikago: after a real click or Tab Ikago asks the script for the focused field, and after
/// Return or a click for a submitted form.
extension CEFWebTab {
    /// Lists saved addresses or cards under the focused field, if it is one.
    func autofillAtFocusedField() {
        guard hasPasswordKey, let context = passwordKeyState.context, let url = URL(string: currentURL), AutofillFlow.isSecure(url) else { return }
        let generation = documentGeneration
        Task { @MainActor in
            for delay in [60, 140, 300] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard generation == documentGeneration else { return }
                guard let report = await passwordCall(context, "function () { return window.__ikagoFormFill ? window.__ikagoFormFill.focusInfo() : null }",
                                                      generation: generation) as? [String: Any] else { continue }
                guard let chosen = await AutofillFlow.choose(report: report, url: url, in: page, field: fieldRect(report)),
                      generation == documentGeneration, currentURL == url.absoluteString else { return }
                // The values travel as call arguments, never as script text.
                let filled = await passwordCall(context, "function (values, card, origin) { return window.__ikagoFormFill.fill(values, card, origin) }",
                                                [chosen.values, chosen.card, PasswordChooser.origin(of: url)], generation: generation)
                #if IKAGO_CHECKS
                print("CEF_AUTOFILL_FILLED \(filled as? Int ?? 0)")
                #endif
                _ = filled
                return
            }
        }
    }

    /// After Return or a click: a submitted address or card is offered for saving.
    func checkForSubmittedForm() {
        guard AutofillFlow.offersSave, !isPrivatePage, hasPasswordKey, let context = passwordKeyState.context else { return }
        let generation = documentGeneration, pageURL = URL(string: currentURL)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard generation == documentGeneration,
                  let found = await passwordCall(context, "function () { return window.__ikagoFormFill ? window.__ikagoFormFill.takeSubmitted() : null }",
                                                 generation: generation) as? [String: Any] else { return }
            AutofillFlow.submitted(address: found["address"] as? [String: String], card: found["card"] as? [String: String],
                                   pageURL: pageURL, isPrivate: isPrivatePage, in: page)
        }
    }
}
