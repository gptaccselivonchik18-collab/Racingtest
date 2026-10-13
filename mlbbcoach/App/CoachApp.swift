import SwiftUI

@main
struct CoachApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentUnavailableView("MLBB Neural Coach", systemImage: "brain.head.profile", description: Text("Локальный тренер • анализ записанных матчей"))
            }
            .preferredColorScheme(.dark)
        }
    }
}
