import SwiftUI
import SwiftData
import Observation
import UserNotifications

@MainActor @Observable final class AdviceJournal {
    static let shared = AdviceJournal()
    private(set) var episodes: [AdviceEpisode] = []
    private(set) var notificationStatus = "Разрешение не проверено"
    private(set) var error: String?
    private var gate = AdviceRepeatGate()
    private var generation = 0
    private var notificationID: String?
    private var expiry: Task<Void, Never>?
    private let center = UNUserNotificationCenter.current()
    private let disk = DispatchQueue(label: "org.mlbbcoach.advice-journal", qos: .utility)
    var url: URL { URL.documentsDirectory.appendingPathComponent("AdviceJournal.json") }
    var mode: AdviceMode { AdviceMode(rawValue: UserDefaults.standard.string(forKey: "adviceMode") ?? "") ?? .voiceAndText }
    private init() {
        if let data = try? Data(contentsOf: url), data.count <= 2_000_000 {
            do { episodes = Array(try JSONDecoder().decode([AdviceEpisode].self, from: data).suffix(300)) }
            catch { self.error = "Не удалось прочитать журнал: \(error.localizedDescription)" }
        }
    }
    func permissions(request: Bool = false) async {
        if request {
            do { _ = try await center.requestAuthorization(options: [.alert]) }
            catch { self.error = error.localizedDescription }
        }
        let settings = await center.notificationSettings()
        notificationStatus = settings.authorizationStatus == .authorized
            ? (settings.alertSetting == .enabled ? "Разрешены; показ баннеров зависит от iOS и Фокусирования" : "Баннеры отключены в настройках iOS")
            : "Нет разрешения на баннеры"
    }
    // One accepted recommendation feeds both channels; no independently generated text advice.
    func accept(_ episode: AdviceEpisode, now: Double) -> Bool {
        let settings = UserDefaults.standard
        let repeatSeconds = settings.object(forKey: "adviceRepeat") == nil ? 45 : settings.double(forKey: "adviceRepeat")
        let interval = settings.object(forKey: "voiceInterval") == nil ? 15 : settings.double(forKey: "voiceInterval")
        guard gate.admit(key: episode.key, priority: episode.priority, now: now, repeatSeconds: repeatSeconds, interval: interval) else { return false }
        episodes.append(episode)
        if episodes.count > 300 { episodes.removeFirst(episodes.count - 300) }
        save()
        return true
    }
    func showText(_ episode: AdviceEpisode, valid: @escaping () -> Bool) {
        cancelText()
        guard mode.usesText else { return }
        let token = generation
        let identifier = "mlbbcoach-live-" + episode.id.uuidString
        notificationID = identifier
        let settings = UserDefaults.standard
        let lifetime = min(15, max(2, settings.object(forKey: "adviceLifetime") == nil ? 5 : settings.double(forKey: "adviceLifetime")))
        expiry = Task { [weak self] in
            guard let self else { return }
            let config = await center.notificationSettings()
            guard !Task.isCancelled, token == generation, mode.usesText, valid(), config.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = episode.priority == 1 ? "Тренер • срочное предупреждение" : "Тренер • совет"
            content.body = settings.bool(forKey: "adviceDetailed") ? episode.text + " " + episode.uncertainty : episode.text
            content.sound = nil
            content.interruptionLevel = .active
            do {
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
                guard !Task.isCancelled, token == generation, valid() else {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [identifier]); return
                }
                // Check validity while the banner is present; never keep a recovered-HP instruction visible.
                let expires = ProcessInfo.processInfo.systemUptime + lifetime
                while !Task.isCancelled, token == generation, valid(), ProcessInfo.processInfo.systemUptime < expires {
                    try await Task.sleep(for: .milliseconds(250))
                }
                if token == generation { cancelText() }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    func cancelText() {
        generation += 1; expiry?.cancel(); expiry = nil
        if let id = notificationID {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.removeDeliveredNotifications(withIdentifiers: [id])
        }
        notificationID = nil
    }
    func update(id: UUID, rating: Int, correction: String) {
        guard let index = episodes.firstIndex(where: { $0.id == id }) else { return }
        episodes[index].rating = min(1, max(-1, rating)); episodes[index].correction = String(correction.prefix(4000)); save()
    }
    func delete(id: UUID) { episodes.removeAll { $0.id == id }; save() }
    private func save() {
        let snapshot = episodes, target = url
        disk.async { [weak self] in
            do { try JSONEncoder().encode(snapshot).write(to: target, options: .atomic) }
            catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in self?.error = message }
            }
        }
    }
}

struct AdviceSettingsView: View {
    @Environment(VoiceCoach.self) private var voice
    @AppStorage("adviceMode") private var mode = AdviceMode.voiceAndText.rawValue
    @AppStorage("adviceLifetime") private var lifetime = 5.0
    @AppStorage("adviceRepeat") private var repeatSeconds = 45.0
    @AppStorage("adviceDetailed") private var detailed = false
    @AppStorage("adviceFontSize") private var fontSize = 18.0
    @State private var journal = AdviceJournal.shared
    var body: some View {
        Form {
            Section("Каналы подсказок") {
                Picker("Режим", selection: $mode) {
                    Text("Голос + текст").tag(AdviceMode.voiceAndText.rawValue)
                    Text("Только голос").tag(AdviceMode.voiceOnly.rawValue)
                    Text("Только текст • без звука").tag(AdviceMode.textOnly.rawValue)
                }.onChange(of: mode) { _, _ in voice.stop(); journal.cancelText() }
                Button("Разрешить текстовые баннеры") { Task { await journal.permissions(request: true) } }
                Text(journal.notificationStatus).font(.caption)
                Text("Баннеры не издают звук. iOS управляет их видом и показом поверх игры: проверьте горизонтальный режим и Фокусирование на iPhone. Это не постоянный overlay.").font(.caption)
            }
            Section("Текст и актуальность") {
                Toggle("Подробное объяснение в баннере", isOn: $detailed)
                Slider(value: $lifetime, in: 2...15, step: 1)
                Text("Удаление уведомления через \(Int(lifetime)) с или при потере актуальности. Система сама выбирает длительность баннера.")
                Slider(value: $repeatSeconds, in: 5...120, step: 5)
                Text("Подавление одинаковых советов: \(Int(repeatSeconds)) с")
                Slider(value: $fontSize, in: 14...30, step: 1)
                Text("Размер текста журнала: \(Int(fontSize)). Размер системного баннера задаёт iOS.")
            }
            NavigationLink("Журнал и исправления") { AdviceJournalView() }
            if let error = journal.error { Text(error).foregroundStyle(.orange) }
        }.navigationTitle("Подсказки").task { await journal.permissions() }
    }
}

struct AdviceJournalView: View {
    @State private var journal = AdviceJournal.shared
    @AppStorage("adviceFontSize") private var fontSize = 18.0
    var body: some View {
        List {
            Text("Последние 300 принятых советов. Оценки и исправления сохраняются; это ещё не обновление параметров модели.").font(.caption)
            ShareLink("Экспорт журнала JSON", item: journal.url)
            ForEach(journal.episodes.reversed()) { episode in
                NavigationLink { AdviceFeedbackView(episode: episode) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(episode.text).font(.system(size: fontSize))
                        Text(episode.created.formatted()).font(.caption)
                        Text(episode.priority == 1 ? "Срочное" : "Обычное").foregroundStyle(episode.priority == 1 ? Color.orange : Color.secondary)
                        if episode.rating != 0 { Text(episode.rating > 0 ? "Полезный совет" : "Требует исправления").font(.caption) }
                    }
                }.swipeActions { Button("Удалить", role: .destructive) { journal.delete(id: episode.id) } }
            }
            if journal.episodes.isEmpty { Text("Советов пока нет") }
            if let error = journal.error { Text(error).foregroundStyle(.orange) }
        }.navigationTitle("Журнал советов")
    }
}

struct AdviceFeedbackView: View {
    let episode: AdviceEpisode
    @Environment(\.modelContext) private var context
    @State private var rating = 0
    @State private var correction = ""
    @State private var status = ""
    var body: some View {
        Form {
            Section("Совет") { Text(episode.text); Text(episode.evidence); Text(episode.uncertainty).foregroundStyle(.secondary) }
            Section("Ваша проверка") {
                Picker("Оценка", selection: $rating) { Text("Не оценён").tag(0); Text("Полезен").tag(1); Text("Ошибочен").tag(-1) }
                TextEditor(text: $correction).frame(minHeight: 120)
                Button("Сохранить оценку и исправление") {
                    AdviceJournal.shared.update(id: episode.id, rating: rating, correction: correction)
                    status = "Сохранено в журнале"
                }
                Button("Добавить исправление в память ИИ") {
                    let source = "Живой совет \(episode.id.uuidString)"
                    do {
                        let existing = try context.fetch(FetchDescriptor<MemoryEntry>()).first { $0.source == source }
                        if let existing { existing.text = correction; existing.enabled = true }
                        else { context.insert(MemoryEntry(text: correction, kind: "Исправление", source: source)) }
                        try context.save(); status = "Сохранено в памяти; параметры нейросети не менялись"
                    } catch { context.rollback(); status = error.localizedDescription }
                }.disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text(status).font(.caption)
            }
        }.navigationTitle("Проверить совет")
        .onAppear { rating = episode.rating; correction = episode.correction }
    }
}
