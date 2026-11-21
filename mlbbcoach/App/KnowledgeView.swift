import SwiftUI
import SwiftData
import UniformTypeIdentifiers

actor KnowledgeUpdater {
    func download(_ url: URL) async throws -> KnowledgePack {
        guard url.scheme == "https", url.host != nil else { throw DataValidationError.invalid("Нужна HTTPS-ссылка на JSON-пакет") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.url?.scheme == "https" else { throw DataValidationError.invalid("Сервер не вернул доступный HTTPS-пакет") }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < 2_000_000 else { throw DataValidationError.invalid("Пакет знаний превышает 2 МБ") }
            data.append(byte)
        }
        return try KnowledgePack.decode(data)
    }
}
struct KnowledgeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \KnowledgeEntry.updated, order: .reverse) private var entries: [KnowledgeEntry]
    @AppStorage("activePatch") private var activePatch = ""
    @State private var urlText = ""
    @State private var importer = false
    @State private var candidate: KnowledgePack?
    @State private var status: String?
    @State private var operation: Task<Void, Never>?
    var body: some View {
        List {
            Section("Версия игры") { TextField("Текущий патч (неизвестен, если пусто)", text: $activePatch) }
            Section("Импорт без переустановки") {
                Button("Открыть JSON-пакет из Файлов") { importer = true }
                TextField("HTTPS-ссылка на JSON-пакет", text: $urlText).textInputAutocapitalization(.never).keyboardType(.URL)
                Button("Загрузить пакет") { download() }.disabled(operation != nil || URL(string: urlText) == nil)
                if operation != nil { ProgressView(); Button("Отменить") { operation?.cancel() } }
                Text("Источник и лицензия задаются в пакете. Импорт не подтверждает истинность данных. Автоматический сбор игровых сайтов не выполняется.").font(.caption).foregroundStyle(.secondary)
            }
            if let candidate {
                Section("Проверка перед добавлением") {
                    Text("Патч: \(candidate.patch) • записей: \(candidate.entries.count)")
                    Text(candidate.source).font(.caption).textSelection(.enabled)
                    Text("Лицензия: \(candidate.license)").font(.caption)
                    Text(candidate.entries.prefix(2).joined(separator: "\n")).lineLimit(8)
                    Button("Добавить пакет в локальную базу") { install(candidate) }
                    Button("Отбросить") { self.candidate = nil }
                }
            }
            if let status { Text(status).foregroundStyle(.orange) }
            Section("Установленные знания • требуют проверки") {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Патч \(entry.patch)").foregroundStyle(.mint)
                        Text(entry.text).textSelection(.enabled)
                        Text(entry.source).font(.caption).foregroundStyle(.secondary)
                        Text("Данные: \(entry.updated.formatted()) • \(entry.license)").font(.caption2).foregroundStyle(.secondary)
                    }
                }.onDelete { offsets in
                    for index in offsets { context.delete(entries[index]) }
                    do { try context.save() } catch { context.rollback(); status = error.localizedDescription }
                }
            }
        }.navigationTitle("Знания")
        .fileImporter(isPresented: $importer, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 2_000_000 else { throw DataValidationError.invalid("Пакет превышает 2 МБ") }
                candidate = try KnowledgePack.decode(Data(contentsOf: url)); status = nil
            } catch { status = error.localizedDescription }
        }.onDisappear { operation?.cancel() }
    }
    private func download() {
        guard operation == nil, let url = URL(string: urlText) else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do { candidate = try await KnowledgeUpdater().download(url); status = nil }
            catch is CancellationError { status = "Загрузка отменена" }
            catch { status = error.localizedDescription }
        }
    }
    private func install(_ pack: KnowledgePack) {
        for text in pack.entries where !entries.contains(where: { $0.patch == pack.patch && $0.source == pack.source && $0.text == text }) {
            let entry = KnowledgeEntry(patch: pack.patch, source: pack.source, text: text)
            entry.updated = pack.published; entry.license = pack.license; context.insert(entry)
        }
        do { try context.save(); candidate = nil; status = "Пакет сохранён локально" }
        catch { context.rollback(); status = error.localizedDescription }
    }
}

struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Query private var memories: [MemoryEntry]
    @State private var document = JSONBackupDocument(data: Data())
    @State private var exporting = false
    @State private var importing = false
    @State private var status: String?
    var body: some View {
        Form {
            Text("Экспортируются записи памяти с категориями, источниками и патчами. Чат, настройки и матчи в эту копию не входят.")
            Button("Экспорт памяти JSON") {
                do { document = JSONBackupDocument(data: try JSONEncoder().encode(MemoryBackup(entries: memories.map(\.snapshot)))); exporting = true }
                catch { status = error.localizedDescription }
            }
            Button("Восстановить память из JSON") { importing = true }
            Text("При восстановлении записи с существующими ID пропускаются. Текущая память сохраняется. Файл содержит личные заметки открытым текстом.").font(.caption).foregroundStyle(.secondary)
            if let status { Text(status) }
        }.navigationTitle("Резервная копия")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "MLBB-memory") { result in
            switch result { case .success: status = "Экспорт завершён"; case .failure(let error): status = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 20_000_000 else { throw DataValidationError.invalid("Копия превышает 20 МБ") }
                let backup = try MemoryBackup.decode(Data(contentsOf: url))
                let existing = Set(memories.map(\.id))
                var count = 0
                for item in backup.entries where !existing.contains(item.id) {
                    let entry = MemoryEntry(text: item.text, kind: item.kind, hero: item.hero, role: item.role, patch: item.patch, source: item.source)
                    entry.id = item.id; entry.enabled = item.enabled; context.insert(entry); count += 1
                }
                try context.save(); status = "Добавлено записей: \(count)"
            } catch { context.rollback(); status = error.localizedDescription }
        }
    }
}
