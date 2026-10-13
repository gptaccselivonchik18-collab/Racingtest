import SwiftUI
import SwiftData

@main
struct CoachApp: App {
    @State private var container: ModelContainer?
    @State private var failure: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootWithCapture().modelContainer(container)
                } else if let failure {
                    ContentUnavailableView {
                        Label("Хранилище недоступно", systemImage: "externaldrive.badge.exclamationmark")
                    } description: { Text(failure) } actions: {
                        Button("Повторить") { loadStore() }
                    }
                } else {
                    ProgressView("Открываю локальную базу…").task { loadStore() }
                }
            }
            .preferredColorScheme(.dark)
            .tint(.mint)
        }
    }
    private func loadStore() {
        do {
            let schema = Schema([MemoryEntry.self, ChatEntry.self, MatchRecord.self, KnowledgeEntry.self])
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [config])
            failure = nil
        } catch { failure = error.localizedDescription }
    }
}

struct RootWithCapture: View {
    var body: some View {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) { CaptureRoot() } else { AppShell() }
        #else
        AppShell()
        #endif
    }
}
#if canImport(ScreenCaptureKit)
@available(iOS 27.0, *)
private struct CaptureRoot: View {
    @State private var capture = ScreenCaptureService()
    var body: some View { AppShell().environment(capture) }
}

#endif
