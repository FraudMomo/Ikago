import Foundation

enum ExtensionURL {
    static func isExtension(_ string: String) -> Bool {
        guard string.count <= 8192, let parts = URLComponents(string: string),
              ["chrome-extension", "webkit-extension"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return false }
        return true
    }
}

@MainActor
extension ExtensionManager {
    /// Chrome-style links target the matching loaded package, using WebKit's native resource origin.
    func resourceURL(_ url: URL) -> URL {
        guard ExtensionURL.isExtension(url.absoluteString), let context = context(for: url),
              let source = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var destination = URLComponents(url: context.baseURL, resolvingAgainstBaseURL: false) else { return url }
        destination.percentEncodedPath = source.percentEncodedPath
        destination.percentEncodedQuery = source.percentEncodedQuery
        destination.percentEncodedFragment = source.percentEncodedFragment
        return destination.url ?? url
    }

    /// Persist a package's stable ID rather than WebKit's per-context random resource host.
    func canonicalURL(_ string: String) -> String {
        guard let url = URL(string: string), let context = context(for: url),
              let record = records.first(where: { $0.id == context.uniqueIdentifier }),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return string }
        parts.scheme = record.appexPath == nil ? "chrome-extension" : "webkit-extension"
        parts.host = context.uniqueIdentifier
        return parts.url?.absoluteString ?? string
    }
}
