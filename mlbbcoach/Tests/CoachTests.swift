import Foundation
import SwiftData
import Testing
@testable import CoachCore
@testable import CoachStorage

@Test func liveCalibrationRejectsPortraitAndDifferentAspect() throws {
    let value = LiveCalibration(region: HUDRegion(x: 0.2, y: 0.7, width: 0.2, height: 0.1), aspectRatio: 1920.0 / 1080)
    let restored = try JSONDecoder().decode(LiveCalibration.self, from: JSONEncoder().encode(value))
    #expect(restored.matches(width: 1280, height: 720))
    #expect(!restored.matches(width: 1080, height: 1920))
    #expect(!restored.matches(width: 1920, height: 850))
    #expect(!restored.matches(width: 0, height: 0))
}
@Test func liveTimingRejectsStaleEventsAndSlowsUnderLoad() {
    #expect(LiveTiming.milliseconds(from: 10, to: 10.25) == 250)
    #expect(LiveTiming.milliseconds(from: .nan, to: 11) == nil)
    #expect(LiveTiming.milliseconds(from: 11, to: 10) == nil)
    #expect(!LiveTiming.isFresh(frame: 10, now: 13.1))
    #expect(LiveTiming.isFresh(frame: 10, now: 12))
    #expect(LiveTiming.interval(lowPower: false, seriousHeat: false, previousProcessing: 0.1, confirmedHP: 0.2) == 0.5)
    #expect(LiveTiming.interval(lowPower: false, seriousHeat: false, previousProcessing: 1, confirmedHP: 0.2) == 2)
    #expect(LiveTiming.interval(lowPower: true, seriousHeat: false, previousProcessing: 0.1, confirmedHP: 0.2) == 3)
}
@Test func liveSpeechJournalLinksEventToMeasuredStart() throws {
    let id = UUID()
    let row = LiveDiagnosticRow(kind: "speech-start", detail: "critical-hp", background: true, uptime: 12,
                                eventID: id, detectionToSpeechMS: 100, frameToSpeechMS: 350)
    let restored = try JSONDecoder().decode(LiveDiagnosticRow.self, from: JSONEncoder().encode(row))
    #expect(restored.eventID == id)
    #expect(restored.background)
    #expect(restored.detectionToSpeechMS == 100)
    #expect(restored.frameToSpeechMS == 350)
}

@Test func stateNeedsTwoReadingsAndClearsMissingEvidence() {
    var tracker = GameStateTracker()
    #expect(tracker.observe(HealthObservation(fraction: 0.12, confidence: 0.99, time: 1), at: 1) == nil)
    #expect(tracker.observe(HealthObservation(fraction: 0.13, confidence: 0.99, time: 3), at: 3) != nil)
    #expect(tracker.observe(nil, at: 4) == nil)
    #expect(tracker.health == nil)
    #expect(tracker.observe(HealthObservation(fraction: 0.12, confidence: 0.99, time: 5), at: 5) == nil)
    #expect(tracker.observe(HealthObservation(fraction: 0.13, confidence: 0.99, time: 30), at: 30) == nil)
}
@Test func longMatchSamplingIncludesStartAndEndWithinBudget() {
    let lines = (0..<100).map { "frame-\($0)" }.joined(separator: "\n\n")
    let result = EvidenceSampling.representative(lines, limit: 8)
    #expect(result.contains("frame-0"))
    #expect(result.contains("frame-99"))
    #expect(result.components(separatedBy: "\n").count == 8)
    #expect(EvidenceSampling.representative(lines, limit: 0).isEmpty)
}

@Test func backupRoundTripAndDuplicateProtection() throws {
    let entry = MemorySnapshot(text: "Моя стратегия", kind: "Исправление", patch: "test", enabled: false)
    let data = try JSONEncoder().encode(MemoryBackup(entries: [entry]))
    let restored = try MemoryBackup.decode(data)
    #expect(restored.entries.first?.id == entry.id)
    #expect(restored.entries.first?.enabled == false)
    let duplicate = try JSONEncoder().encode(MemoryBackup(entries: [entry, entry]))
    #expect(throws: (any Error).self) { try MemoryBackup.decode(duplicate) }
}
@Test func knowledgeRejectsUnversionedAndInsecureSources() throws {
    let valid = Data(#"{"schemaVersion":1,"patch":"test","published":"2026-01-01T00:00:00Z","source":"https://example.com/source","license":"test-only","entries":["Непроверенная заметка"]}"#.utf8)
    #expect(try KnowledgePack.decode(valid).patch == "test")
    let insecure = Data(String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "https://", with: "http://").utf8)
    #expect(throws: (any Error).self) { try KnowledgePack.decode(insecure) }
    let wrongVersion = Data(String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2").utf8)
    #expect(throws: (any Error).self) { try KnowledgePack.decode(wrongVersion) }
}

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
