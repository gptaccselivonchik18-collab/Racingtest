import SwiftUI
import SwiftData

struct AppShell: View {
    @State private var monitor = PerformanceMonitor()
    @State private var voice = VoiceCoach()
    @State private var ai = StrategyAI()
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }.tabItem { Label("Главная", systemImage: "waveform.path.ecg") }
            NavigationStack { CoachSettingsView() }.tabItem { Label("Тренер", systemImage: "speaker.wave.2") }
            NavigationStack { BrainView() }.tabItem { Label("ИИ-мозг", systemImage: "brain") }
            NavigationStack { MemoryView() }.tabItem { Label("Память", systemImage: "square.stack") }
            NavigationStack { LibraryView() }.tabItem { Label("Библиотека", systemImage: "square.grid.2x2") }
        }.environment(monitor).environment(voice).environment(ai)
        .task {
            while !Task.isCancelled {
                monitor.refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
    }
}
struct DashboardView: View {
    @Environment(PerformanceMonitor.self) private var monitor
    @Query private var memories: [MemoryEntry]
    @Query private var matches: [MatchRecord]
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "brain.head.profile").font(.system(size: 44)).foregroundStyle(.mint)
                    Text("NEURAL COACH").font(.title.bold())
                    Text("Персональный тренер MLBB").foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }
            Section("Устройство • реальные показатели") {
                LabeledContent("Тепловое состояние", value: monitor.thermal)
                LabeledContent("Энергосбережение", value: monitor.lowPower ? "Включено" : "Выключено")
                LabeledContent("Физическая RAM", value: String(format: "%.1f ГБ", monitor.memoryGB))
                Text("iOS сообщает категорию нагрева, а не температуру в градусах.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Локальная база") {
                LabeledContent("Записей памяти", value: "\(memories.count)")
                LabeledContent("Разобранных матчей", value: "\(matches.count)")
                Text("База хранится на устройстве. iCloud выключен.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Главная")
    }
}
struct CoachSettingsView: View {
    @Environment(VoiceCoach.self) private var voice
    @AppStorage("voiceEnabled") private var enabled = true
    @AppStorage("voiceInterval") private var interval = 15.0
    var body: some View {
        Form {
            Section("Локальное озвучивание") {
                Toggle("Голос тренера", isOn: $enabled).onChange(of: enabled) { _, value in if !value { voice.stop() } }
                Slider(value: $interval, in: 5...60, step: 5)
                LabeledContent("Пауза между подсказками", value: "\(Int(interval)) с")
                Button("Проверить русский голос") { voice.speak("Тренер готов. Все вычисления выполняются на устройстве.", key: "voice-test") }.disabled(!enabled)
                Button("Остановить озвучивание") { voice.stop() }
                if let error = voice.error { Text(error).foregroundStyle(.orange) }
            }
            Section("Приоритеты") {
                Text("1. Угроза жизни\n2. Тактическая возможность\n3. Объекты\n4. Экономика\n5. Обучение")
                Text("Повторы подавляются на 45 секунд. Совместимость с игровым звуком требует проверки на iPhone.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Тренер")
    }
}
struct LibraryView: View {
    @AppStorage("sampleInterval") private var interval = 3.0
    var body: some View {
        List {
            NavigationLink { MatchHistoryView() } label: { Label("Матчи", systemImage: "film") }
            NavigationLink { ModelsView() } label: { Label("Модели", systemImage: "cpu") }
            Section("Производительность") {
                Slider(value: $interval, in: 1...10, step: 1)
                LabeledContent("Интервал анализа записи", value: "\(Int(interval)) с")
                Text("При нагреве и энергосбережении нагрузка будет снижаться. Скорость на iPhone пока не измерена.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Приватность") { Text("Нет платных API и облачной синхронизации. Удаление приложения удаляет локальные данные.") }
        }.navigationTitle("Библиотека")
    }
}
struct MatchHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MatchRecord.created, order: .reverse) private var matches: [MatchRecord]
    @State private var error: String?
    var body: some View {
        List {
            if matches.isEmpty { ContentUnavailableView("Матчей пока нет", systemImage: "film") }
            ForEach(matches) { match in
                NavigationLink {
                    ScrollView { VStack(alignment: .leading, spacing: 16) {
                        Text(match.title).font(.title2.bold())
                        Text("Кадров: \(match.frameCount) • обработка: \(Int(match.processingSeconds)) с")
                        Text(match.summary).foregroundStyle(.mint)
                        Text(match.transcript).textSelection(.enabled)
                    }.padding() }.navigationTitle("Разбор матча")
                } label: { VStack(alignment: .leading) {
                    Text(match.title)
                    Text(match.created.formatted()).font(.caption).foregroundStyle(.secondary)
                } }
            }.onDelete { offsets in
                for index in offsets { context.delete(matches[index]) }
                do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
            }
            if let error { Text(error).foregroundStyle(.orange) }
        }.navigationTitle("Матчи")
    }
}
