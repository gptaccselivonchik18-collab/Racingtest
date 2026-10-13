import Foundation
import SwiftData
import Testing
@testable import CoachCore
@testable import CoachStorage

private func barImage(_ filled: Int, width: Int = 200, holes: Range<Int> = 0..<0) -> [UInt8] {
    (0..<5).flatMap { _ in (0..<width).flatMap { x -> [UInt8] in x < filled && !holes.contains(x) ? [20, 210, 30, 255] : [25, 25, 25, 255] } }
}
@Test func calibratedBarFindsEdgeAndRejectsPartialCalibration() throws {
    let tint = try #require(HealthBarSensor.learnTint(rgba: barImage(200), width: 200, height: 5))
    let hp = try #require(HealthBarSensor.observe(rgba: barImage(40), width: 200, height: 5, tint: tint, time: 10))
    #expect(abs(hp.fraction - 0.2) < 0.01)
    #expect(HealthBarSensor.learnTint(rgba: barImage(40), width: 200, height: 5) == nil)
    #expect(HealthBarSensor.observe(rgba: barImage(0), width: 200, height: 5, tint: tint, time: 10) == nil)
    #expect(HealthBarSensor.observe(rgba: barImage(150, holes: 50..<90), width: 200, height: 5, tint: tint, time: 10) == nil)
    #expect(HealthBarSensor.observe(rgba: [1, 2], width: 200, height: 5, tint: tint, time: 10) == nil)
}

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

@Test func outputModesKeepTextOnlySilent() {
    #expect(AdviceMode.voiceAndText.usesVoice && AdviceMode.voiceAndText.usesText)
    #expect(AdviceMode.voiceOnly.usesVoice && !AdviceMode.voiceOnly.usesText)
    #expect(!AdviceMode.textOnly.usesVoice && AdviceMode.textOnly.usesText)
}
@Test func adviceGateSuppressesRepeatsButAllowsUrgentEscalation() {
    var gate = AdviceRepeatGate()
    let admitted1 = gate.admit(key: "low", priority: 2, now: 10, repeatSeconds: 45, interval: 15)
    #expect(admitted1)
    let admitted2 = gate.admit(key: "low", priority: 2, now: 12, repeatSeconds: 45, interval: 15)
    #expect(!admitted2)
    let admitted3 = gate.admit(key: "other", priority: 2, now: 12, repeatSeconds: 45, interval: 15)
    #expect(!admitted3)
    let admitted4 = gate.admit(key: "critical", priority: 1, now: 12, repeatSeconds: 45, interval: 15)
    #expect(admitted4)
    let admitted5 = gate.admit(key: "critical", priority: 1, now: 13, repeatSeconds: 45, interval: 15)
    #expect(!admitted5)
    let admitted6 = gate.admit(key: "low", priority: 2, now: 56, repeatSeconds: 45, interval: 15)
    #expect(admitted6)
    let admitted7 = gate.admit(key: "invalid", priority: 1, now: .nan, repeatSeconds: 45, interval: 15)
    #expect(!admitted7)
}
@Test func adviceFeedbackRoundTripRetainsUnknownsAndSession() throws {
    let session = UUID()
    var episode = AdviceEpisode(id: UUID(), sessionID: session, key: "low", text: "Проверьте HP", priority: 2, observedHP: 0.2)
    episode.rating = -1; episode.correction = "Выделена чужая полоса"
    let value = try JSONDecoder().decode(AdviceEpisode.self, from: JSONEncoder().encode(episode))
    #expect(value.sessionID == session && value.rating == -1)
    #expect(value.correction == episode.correction && value.observedHP == 0.2)
    #expect(value.uncertainty.contains("неизвестны"))
}

@Test func neuralTrainingChangesWeightsImprovesHeldOutAndReloads() throws {
    let train = [LabeledVector(group: "a", features: [-0.9,-0.8], label: 0), LabeledVector(group: "a", features: [-0.8,-0.9], label: 0), LabeledVector(group: "b", features: [-0.7,-1], label: 0), LabeledVector(group: "c", features: [0.9,0.8], label: 1), LabeledVector(group: "c", features: [0.8,0.9], label: 1), LabeledVector(group: "d", features: [0.7,1], label: 1)]
    let heldOut = [LabeledVector(group: "test1", features: [-0.6,-0.9], label: 0), LabeledVector(group: "test2", features: [-0.9,-0.6], label: 0), LabeledVector(group: "test3", features: [0.6,0.9], label: 1), LabeledVector(group: "test4", features: [0.9,0.6], label: 1)]
    try TrainableNetwork.validateSplit(train: train, test: heldOut, classes: 2)
    var model = TrainableNetwork(inputs: 2, hidden: 8, outputs: 2)
    let original = model
    let before = try #require(model.metrics(heldOut))
    try model.train(train, epochs: 60, rate: 0.08)
    let after = try #require(model.metrics(heldOut))
    #expect(model.w1 != original.w1 && model.w2 != original.w2)
    #expect(after.loss < before.loss && after.accuracy == 1)
    #expect(TrainableNetwork.shouldPromote(before: before, after: after))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let active = directory.appendingPathComponent("active.json"), previous = directory.appendingPathComponent("previous.json")
    try JSONEncoder().encode(original).write(to: previous)
    try JSONEncoder().encode(model).write(to: active)
    let reloaded = try JSONDecoder().decode(TrainableNetwork.self, from: Data(contentsOf: active))
    #expect(reloaded.w1 == model.w1 && reloaded.probabilities(heldOut[0].features) == model.probabilities(heldOut[0].features))
    let rollback = try JSONDecoder().decode(TrainableNetwork.self, from: Data(contentsOf: previous))
    #expect(rollback.w1 == original.w1 && rollback.w1 != model.w1)
    print("NEURAL_EXPERIMENT synthetic_features=true before_accuracy=\(before.accuracy) after_accuracy=\(after.accuracy) before_loss=\(before.loss) after_loss=\(after.loss) weights_changed=true reload=true rollback=true")
}
@Test func neuralValidationRejectsLeakageAndWorseCandidate() throws {
    let samples = (0..<6).map { LabeledVector(group: "same-match", features: [0.2,0.3], label: $0 % 2) }
    #expect(throws: NeuralError.self) { try TrainableNetwork.validateSplit(train: samples, test: samples, classes: 2) }
    let model = TrainableNetwork(inputs: 2, outputs: 2)
    #expect(model.probabilities([.nan,0]) == nil)
    #expect(model.probabilities([0]) == nil)
    let strong = NetworkMetrics(count: 20, accuracy: 0.9, loss: 0.2)
    let weak = NetworkMetrics(count: 20, accuracy: 0.6, loss: 0.7)
    #expect(!TrainableNetwork.shouldPromote(before: strong, after: weak))
}
@Test func appleStateContainsOnlyEnglishIdentifiersAndRussianRendererIsLocal() throws {
    let state = StrategicState(ownHealth: 0.4, icons: [RecognizedIcon(slot: "ally", code: "layla", score: 0.9, observedAt: 1)])
    let json = try state.englishJSON()
    #expect(json.utf8.allSatisfy { $0 < 128 })
    let invalid = StrategicState(ownHealth: nil, icons: [RecognizedIcon(slot: "ally", code: "Лейла", score: 0.9, observedAt: 1)])
    #expect(throws: NeuralError.self) { try invalid.englishJSON() }
    let plan = StrategicPlan(selected: .gatherInformation, alternatives: [ActionOption(action: .gatherInformation, reason: .insufficientEvidence, utility: 60, risk: 10), ActionOption(action: .recover, reason: .healthLimited, utility: 40, risk: 20)], confidence: 30)
    #expect(plan.valid && plan.russian().contains("Уточните обстановку"))
    let restored = try JSONDecoder().decode(StrategicPlan.self, from: JSONEncoder().encode(plan))
    #expect(restored.russian() == plan.russian())
}
