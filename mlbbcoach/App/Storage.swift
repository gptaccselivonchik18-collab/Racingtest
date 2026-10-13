import Foundation
import SwiftData

@Model final class MemoryEntry {
    @Attribute(.unique) var id: UUID
    var created: Date
    var text: String
    var kind: String
    var hero: String
    var role: String
    var patch: String
    var source: String
    var enabled: Bool
    init(text: String, kind: String = "Предпочтение", hero: String = "", role: String = "", patch: String = "", source: String = "") {
        id = UUID(); created = .now; self.text = text; self.kind = kind
        self.hero = hero; self.role = role; self.patch = patch; self.source = source; enabled = true
    }
}
@Model final class ChatEntry {
    @Attribute(.unique) var id: UUID
    var created: Date
    var role: String
    var text: String
    var rating: Int
    init(role: String, text: String) {
        id = UUID(); created = .now; self.role = role; self.text = text; rating = 0
    }
}
@Model final class MatchRecord {
    @Attribute(.unique) var id: UUID
    var created: Date
    var title: String
    var duration: Double
    var frameCount: Int
    var processingSeconds: Double
    var transcript: String
    var summary: String
    var strategy: String = ""
    init(title: String, duration: Double, frameCount: Int, processingSeconds: Double, transcript: String) {
        id = UUID(); created = .now; self.title = title; self.duration = duration
        self.frameCount = frameCount; self.processingSeconds = processingSeconds
        self.transcript = transcript; summary = ""
    }
}
@Model final class KnowledgeEntry {
    @Attribute(.unique) var id: UUID
    var updated: Date
    var patch: String
    var source: String
    var text: String
    var license: String = ""
    init(patch: String, source: String, text: String) {
        id = UUID(); updated = .now; self.patch = patch; self.source = source; self.text = text
    }
}
enum MemoryKind {
    static let all = ["Факт с источником", "Предпочтение", "Гипотеза", "Исправление"]
}
