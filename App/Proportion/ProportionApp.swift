import SwiftUI
import SwiftData
import ProportionCore

@main
struct ProportionApp: App {
    private let container: ModelContainer
    @State private var services = AppServices()

    /// Launched by the UI tests: in-memory store seeded with sample recipes.
    static var isUITesting: Bool { CommandLine.arguments.contains("-ui-testing") }

    /// UI tests can pin the appearance; `-AppleInterfaceStyle` is not
    /// honoured reliably by the simulator, so the app applies it itself.
    static var forcedColorScheme: ColorScheme? {
        if CommandLine.arguments.contains("-ui-testing-dark") { return .dark }
        if CommandLine.arguments.contains("-ui-testing-light") { return .light }
        return nil
    }

    init() {
        if Self.isUITesting {
            container = Self.makeTestContainer()
            for recipe in SampleData.recipes {
                container.mainContext.insert(StoredRecipe(recipe: recipe))
            }
        } else {
            container = Self.makeContainer()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .preferredColorScheme(Self.forcedColorScheme)
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

    private static func makeTestContainer() -> ModelContainer {
        let schema = Schema([StoredRecipe.self])
        let config = ModelConfiguration("Proportion-UITest", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create the in-memory store: \(error)")
        }
    }
}
