import SwiftUI
import SwiftData
import ProportionCore

@main
struct ProportionApp: App {
    private let container: ModelContainer
    @State private var services = AppServices()

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .onOpenURL { url in services.pendingImports.handle(url: url) }
        }
        .modelContainer(container)
    }

    /// CloudKit-backed store, falling back to local-only if iCloud is
    /// unavailable so the app always launches with the user's data.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([StoredRecipe.self])
        let synced = ModelConfiguration("Proportion", schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [synced]) {
            return container
        }
        let local = ModelConfiguration("Proportion", schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Could not create the recipe store: \(error)")
        }
    }
}
