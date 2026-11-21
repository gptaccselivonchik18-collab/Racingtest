import SwiftUI
import SwiftData

struct MatchDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(StrategyAI.self) private var ai
    @Environment(VoiceCoach.self) private var voice
    @Query private var memories: [MemoryEntry]
    @Bindable var match: MatchRecord
    @AppStorage("profileHero") private var hero = ""
    @AppStorage("profileRole") private var role = ""
    @State private var request: Task<Void, Never>?
    @State private var error: String?
    var body: some View {
        List {
            Section("Запись") {
                Text(match.title).font(.headline)
                LabeledContent("Длительность записи", value: "\(Int(match.duration)) с")
                LabeledContent("Обработано кадров", value: "\(match.frameCount)")
                LabeledContent("Время обработки", value: "\(Int(match.processingSeconds)) с")
                TextField("Ваш герой (указан вами)", text: $hero)
                TextField("Ваша роль", text: $role)
            }
            Section("Тактика • по калиброванным наблюдениям") {
                Text(match.summary).textSelection(.enabled)
                Button("Озвучить тактический разбор") { voice.speak(match.summary, key: match.id.uuidString) }
            }
            Section("Стратегический разбор локальной моделью") {
                Text(ai.status).font(.caption).foregroundStyle(.secondary)
                Text("Модель получает выборку OCR и ваши заметки. Это не полноценное распознавание всех событий матча.").font(.caption).foregroundStyle(.secondary)
                if request != nil { ProgressView(); Button("Отменить") { request?.cancel() } }
                else { Button(match.strategy.isEmpty ? "Разобрать с локальным ИИ" : "Повторить разбор") { analyze() }.disabled(!ai.chatAvailable || ai.busy) }
                if !match.strategy.isEmpty { Text(match.strategy).textSelection(.enabled) }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            Section("Непроверенный OCR и метки модели") { Text(match.transcript.isEmpty ? "Текст не распознан" : match.transcript).font(.caption).textSelection(.enabled) }
            Section { ShareLink(item: "\(match.title)\n\n\(match.summary)\n\n\(match.strategy)\n\n\(match.transcript)") { Label("Экспорт отчёта", systemImage: "square.and.arrow.up") } }
        }.navigationTitle("Разбор матча").onDisappear { request?.cancel() }
    }
    private func analyze() {
        guard request == nil else { return }
        let relevant = MemoryRetrieval.retrieve("\(hero) \(role) \(match.summary)", from: memories.map(\.snapshot))
        let evidence = EvidenceSampling.representative(match.transcript)
        let prompt = "Разбери запись матча по ограниченным наблюдениям. Герой со слов пользователя: \(hero); роль: \(role). Длительность: \(Int(match.duration)) с.\nТактические наблюдения:\n\(match.summary.prefix(1000))\nВыборка OCR и непроверенных меток:\n\(evidence)\nНазови наблюдаемые проблемы, отдельно гипотезы и 1–3 проверяемых совета. Не выдумывай позиции, ротации, исходы боёв, готовность навыков и составы команд. Если выборки недостаточно, скажи прямо."
        request = Task { @MainActor in
            defer { request = nil }
            do {
                let answer = try await ai.respond(question: prompt, memory: MemoryRetrieval.context(relevant))
                match.strategy = answer; try context.save(); error = nil
            } catch is CancellationError { error = "Разбор отменён" }
            catch { context.rollback(); self.error = error.localizedDescription }
        }
    }
}
