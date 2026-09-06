import SwiftUI
import SwiftData
import ProportionCore

struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingToReview: PendingImport?

    var body: some View {
        TabView {
            Tab("Library", systemImage: "book.closed") { LibraryView() }
            Tab("Search", systemImage: "text.magnifyingglass") { SearchView() }
            Tab("Capture", systemImage: "plus.circle") { CaptureView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
        .tint(Theme.accent)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                services.pendingImports.refresh()
                pendingToReview = services.pendingImports.items.first
            }
        }
        .sheet(item: $pendingToReview) { item in
            let importer = services.importer
            let store = services.pendingImports.store
            ImportFlowView(
                title: "Shared recipe",
                job: { try await importer.importPending(item, store: store) },
                onFinished: { services.pendingImports.remove(item) })
        }
    }
}
