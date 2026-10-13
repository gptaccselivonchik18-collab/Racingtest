import SwiftUI
import SwiftData

struct BrainView: View {
    @Environment(\.modelContext) private var context
    @Environment(StrategyAI.self) private var ai
    @Query(sort: \ChatEntry.created) private var messages: [ChatEntry]
    @Query private var memories: [MemoryEntry]
    @Query(sort: \KnowledgeEntry.updated, order: .reverse) private var knowledge: [KnowledgeEntry]
    @State private var draft = ""
    @State private var failure: String?
    @State private var request: Task<Void, Never>?
    @State private var teaching: ChatEntry?
    @AppStorage("activePatch") private var activePatch = ""
    var body: some View {
        VStack(spacing: 0) {
            Text(ai.status).font(.caption).foregroundStyle(ai.available ? .mint : .orange).padding(8)
            if !ai.chatAvailable { NavigationLink("Установить модель для русского общения") { LanguageModelsView() }.font(.caption).padding(8) }
            ScrollViewReader { proxy in
                List {
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message.role == "user" ? "Вы" : "Локальный тренер • вывод модели").font(.caption).foregroundStyle(.mint)
                            Text(message.text).textSelection(.enabled)
                            if message.role == "assistant" {
                                HStack {
                                    Button { rate(message, 1) } label: { Image(systemName: message.rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsup") }
                                    Button { rate(message, -1) } label: { Image(systemName: message.rating == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown") }
                                    Button("Исправить / запомнить") { teaching = message }
                                }.buttonStyle(.borderless).font(.caption)
                            }
                        }.id(message.id)
                    }
                    if ai.busy { ProgressView("Думаю на устройстве…") }
                    if let failure { Text(failure).foregroundStyle(.orange) }
                }.onChange(of: messages.count) { _, _ in if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            HStack(alignment: .bottom) {
                TextField("Вопрос тренеру", text: $draft, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                if request != nil {
                    Button { request?.cancel() } label: { Image(systemName: "stop.circle") }.accessibilityLabel("Остановить ответ")
                } else {
                    Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ai.chatAvailable)
                        .accessibilityLabel("Отправить")
                }
            }.padding()
        }.navigationTitle("ИИ-мозг")
        .sheet(item: $teaching) { message in NavigationStack { MemoryEditor(initialText: "Исправление ответа тренера:\n\(message.text)\n\nПравильное решение: ", initialKind: "Исправление") } }
        .onDisappear { request?.cancel() }
    }
    private func rate(_ message: ChatEntry, _ value: Int) {
        message.rating = message.rating == value ? 0 : value
        do { try context.save() } catch { context.rollback(); failure = error.localizedDescription }
    }
    private func send() {
        let question = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6000))
        let recalled = MemoryRetrieval.retrieve(question, from: memories.map(\.snapshot))
        let facts = knowledge.filter { activePatch.isEmpty || $0.patch == activePatch }.map {
            MemorySnapshot(id: $0.id, text: $0.text, kind: "Данные из внешнего пакета (непроверенные)", patch: $0.patch, source: $0.source)
        }
        let known = MemoryRetrieval.context(MemoryRetrieval.retrieve(question, from: facts, limit: 4))
        let recent = messages.suffix(4).map { "\($0.role): \($0.text.prefix(600))" }.joined(separator: "\n")
        context.insert(ChatEntry(role: "user", text: question))
        do { try context.save() } catch { context.rollback(); failure = error.localizedDescription; return }
        draft = ""; failure = nil
        request = Task { @MainActor in
            defer { request = nil }
            do {
                let reply = try await ai.respond(question: question, memory: MemoryRetrieval.context(recalled) + "\n" + known, recent: recent)
                context.insert(ChatEntry(role: "assistant", text: reply))
                try context.save()
            } catch is CancellationError { failure = "Ответ остановлен" }
            catch { context.rollback(); failure = error.localizedDescription }
        }
    }
}

struct ModelsView: View {
    @Environment(StrategyAI.self) private var ai
    var body: some View {
        List {
            NavigationLink { CustomModelView() } label: { Label("Управление Core ML-моделью зрения", systemImage: "eye") }
            NavigationLink("Выбор языковой модели и русский чат") { LanguageModelsView() }
            NavigationLink("Обучаемая нейросеть иконок") { IconLearningView() }
            Section("Языковая модель") {
                LabeledContent("Провайдер", value: ai.provider == "llama" ? "llama.cpp • CPU" : "Apple • SystemLanguageModel")
                Text(ai.status).foregroundStyle(ai.available ? .mint : .orange)
                if ai.provider == "apple" { Text("Apple используется локально для английских структурированных решений. Включение и загрузка системной модели управляются настройками iOS.") }
                Text("Размер модели и занятая ей RAM не публикуются этим API; приложение их не выдумывает.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Обучение") { Text("Раздел «Обучаемая нейросеть иконок» изменяет веса небольшой нейросети на размеченных изображениях и сравнивает отложенную выборку. Память и языковые веса — отдельные компоненты.") }
        }.navigationTitle("Модели")
    }
}
