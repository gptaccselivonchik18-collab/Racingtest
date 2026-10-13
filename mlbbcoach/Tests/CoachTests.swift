import Foundation
import SwiftData
import Testing
@testable import CoachCore
@testable import CoachStorage

@Test func healthRejectsAmbiguousAndImpossibleReadings() {
    for text in ["12/0", "150/100", "-1/100", "12/100/200", "HP 12/100", "3:40", ""] {
        #expect(HealthParser.parse(text, confidence: 0.99, time: 10) == nil)
    }
    #expect(HealthParser.parse("12/100", confidence: 0.5, time: 10) == nil)
    #expect(HealthParser.parse("12/100", confidence: .nan, time: 10) == nil)
    #expect(HealthParser.parse("12/100", confidence: 0.99, time: -1) == nil)
}
@Test func tacticsRequireFreshReliableEvidence() {
    let hp = HealthParser.parse("12/100", confidence: 0.95, time: 10)
    #expect(TacticalDecisionEngine.evaluate(health: hp, at: 11).first?.priority == 1)
    #expect(TacticalDecisionEngine.evaluate(health: hp, at: 30).isEmpty)
    #expect(TacticalDecisionEngine.evaluate(health: hp, at: 9).isEmpty)
    #expect(TacticalDecisionEngine.evaluate(health: nil, at: 11).isEmpty)
    #expect(TacticalDecisionEngine.evaluate(health: HealthObservation(fraction: 0, confidence: 1, time: 10), at: 10).isEmpty)
    #expect(TacticalDecisionEngine.evaluate(health: HealthObservation(fraction: 0.8, confidence: 1, time: 10), at: 10).isEmpty)
}
@Test func calibrationMustFitInsideFrame() {
    #expect(HUDRegion(x: 0.2, y: 0.2, width: 0.3, height: 0.1).isValid)
    #expect(!HUDRegion(x: 0.9, y: 0.2, width: 0.3, height: 0.1).isValid)
    #expect(!HUDRegion(x: .nan, y: 0.2, width: 0.3, height: 0.1).isValid)
}

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
