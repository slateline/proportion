import Foundation
import Observation

/// Surfaces captures the Share Extension left in the App Group so the app
/// can offer to review them. Refreshed whenever the app becomes active.
@MainActor
@Observable
final class PendingImportsController {
    let store = PendingImportStore()
    private(set) var items: [PendingImport] = []

    func refresh() {
        items = store.loadAll()
    }

    func remove(_ item: PendingImport) {
        store.remove(item)
        items.removeAll { $0.id == item.id }
    }

    /// Custom URL entry point (proportion://import?url=…) for shortcuts and
    /// deep links; the Share Extension itself uses the App Group instead.
    func handle(url: URL) {
        guard url.scheme == "proportion", url.host == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if let target = components.queryItems?.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)) {
            try? store.save(PendingImport(kind: .url, url: target))
        } else if let text = components.queryItems?.first(where: { $0.name == "text" })?.value, !text.isEmpty {
            try? store.save(PendingImport(kind: .text, text: text))
        }
        refresh()
    }
}
