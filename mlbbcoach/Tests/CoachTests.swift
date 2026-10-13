import Foundation
import SwiftData
import Testing
@testable import CoachCore
@testable import CoachStorage

@Test func retrievalIgnoresDisabledAndUnrelatedNotes() {
    let match = MemorySnapshot(text: "Лейла: держать дистанцию", hero: "Лейла")
    let disabled = MemorySnapshot(text: "Лейла покупка", enabled: false)
    let unrelated = MemorySnapshot(text: "Стратегия лесника")
    #expect(MemoryRetrieval.retrieve("Лейла дистанция", from: [disabled, unrelated, match]).map(\.id) == [match.id])
    #expect(MemoryRetrieval.retrieve("", from: [match]).isEmpty)
    #expect(MemoryRetrieval.retrieve("Лейла", from: [match], limit: 0).isEmpty)
}
@Test func contextPreservesUncertaintyAndPatch() {
    let note = MemorySnapshot(text: "Проверить механику", kind: "Гипотеза", patch: "test-patch")
    #expect(MemoryRetrieval.context([note]).contains("Гипотеза"))
    #expect(MemoryRetrieval.context([note]).contains("test-patch"))
}
@Test @MainActor func memoryPersistsToDiskAcrossContainers() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("test.store")
    let schema = Schema([MemoryEntry.self, ChatEntry.self, MatchRecord.self, KnowledgeEntry.self])
    do {
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let note = MemoryEntry(text: "Тест сохранения", kind: "Исправление", patch: "test")
        container.mainContext.insert(note)
        try container.mainContext.save()
    }
    let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    let reopened = try ModelContainer(for: schema, configurations: [config])
    let notes = try reopened.mainContext.fetch(FetchDescriptor<MemoryEntry>())
    #expect(notes.count == 1)
    #expect(notes.first?.text == "Тест сохранения")
    #expect(notes.first?.kind == "Исправление")
    #expect(notes.first?.patch == "test")
}
