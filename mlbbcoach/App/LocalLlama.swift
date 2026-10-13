import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

private final class LlamaCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    func cancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
enum LocalLlama {
    static var modelURL: URL { URL.applicationSupportDirectory.appendingPathComponent("LanguageModels/active.gguf") }
    static var modelExists: Bool { FileManager.default.fileExists(atPath: modelURL.path) }
    static func generate(system: String, prompt: String) async throws -> String {
        let token = LlamaCancellation(), path = modelURL.path
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                let pointer = Unmanaged.passRetained(token).toOpaque()
                defer { Unmanaged<LlamaCancellation>.fromOpaque(pointer).release() }
                var output = [CChar](repeating: 0, count: 24000)
                let capacity = Int32(output.count)
                let result = coach_llama_generate(path, system, prompt, &output, capacity, { raw in
                    guard let raw else { return true }
                    return Unmanaged<LlamaCancellation>.fromOpaque(raw).takeUnretainedValue().cancelled()
                }, pointer)
                if result == -2 { throw CancellationError() }
                guard result > 0 else { throw CoachError.unavailable("Локальная модель не ответила (код \(result)). Проверьте совместимость GGUF, размер контекста и память.") }
                return String(decoding: output.prefix(Int(result)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }.value
        } onCancel: { token.cancel() }
    }
}
actor LanguageModelInstaller {
    static let shared = LanguageModelInstaller()
    static let qwenURL = URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/9217f5db79a29953eb74d5343926648285ec7e67/qwen2.5-0.5b-instruct-q4_k_m.gguf")!
    static let qwenSHA = "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
    func install(_ source: URL, sha: String) throws {
        let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size >= 1000, size <= 1_500_000_000, sha.count == 64, sha.allSatisfy(\.isHexDigit) else { throw NeuralError.invalidData }
        let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
        var hash = SHA256(), first = true
        while let part = try handle.read(upToCount: 1_048_576), !part.isEmpty {
            try Task.checkCancellation()
            if first { guard part.starts(with: [71,71,85,70]) else { throw CoachError.unavailable("Это не файл GGUF") }; first = false }
            hash.update(data: part)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha.lowercased() else { throw CoachError.unavailable("SHA-256 модели не совпадает") }
        let target = LocalLlama.modelURL, folder = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appendingPathComponent(UUID().uuidString + ".gguf")
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: source, to: staged)
        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: staged, backupItemName: "previous.gguf", options: []) }
        else { try FileManager.default.moveItem(at: staged, to: target) }
        UserDefaults.standard.set(actual, forKey: "languageModelSHA")
    }
    func downloadQwen() async throws {
        let (url, response) = try await URLSession.shared.download(from: Self.qwenURL)
        defer { try? FileManager.default.removeItem(at: url) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CoachError.unavailable("Не удалось скачать модель") }
        try install(url, sha: Self.qwenSHA)
    }
}
struct LanguageModelsView: View {
    @AppStorage("languageProvider") private var provider = "apple"
    @State private var importing = false
    @State private var sha = ""
    @State private var status = ""
    @State private var operation: Task<Void, Never>?
    var body: some View {
        Form {
            Picker("Игровые решения", selection: $provider) { Text("Apple • английское ядро").tag("apple"); Text("Независимая GGUF-модель").tag("llama") }
            Text("Русский интерфейс и рекомендации сохраняются. Apple получает только структурированное состояние на английском. Русский свободный чат всегда использует независимую модель; смена промпта не добавляет Apple поддержку языка.").font(.caption)
            Section("Бесплатная локальная модель") {
                Text("Qwen2.5 0.5B Instruct Q4_K_M • Apache 2.0 • 491 МБ. Небольшая многоязычная модель для базового русского общения; качество сложной стратегии и скорость на iPhone ещё не подтверждены.")
                Button("Скачать Qwen на устройство") { operation = Task { do { try await LanguageModelInstaller.shared.downloadQwen(); status = "Модель проверена и сохранена" } catch { status = error.localizedDescription }; operation = nil } }.disabled(operation != nil || LiveTrainingGuard.active)
                TextField("SHA-256 своего GGUF", text: $sha).textInputAutocapitalization(.never)
                Button("Импортировать совместимый GGUF") { importing = true }.disabled(operation != nil || LiveTrainingGuard.active)
                Text(LocalLlama.modelExists ? "Локальная модель установлена" : "Локальная модель не установлена")
                if operation != nil { ProgressView("Загрузка / проверка модели…"); Button("Отменить") { operation?.cancel() } }
                Text(status).textSelection(.enabled)
                Link("Источник и лицензия Qwen", destination: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF")!)
            }
            Text("Вычисления llama.cpp выполняются на CPU, 2 потока, контекст 2048 токенов, до 400 выходных токенов. Файл хранится локально; после установки интернет не требуется. Языковые веса не обучаются этим экраном.").font(.caption)
        }.navigationTitle("Языковые модели")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do { let url = try result.get(); operation = Task { do { try await LanguageModelInstaller.shared.install(url, sha: sha); status = "GGUF проверен и сохранён" } catch { status = error.localizedDescription }; operation = nil } } catch { status = error.localizedDescription }
        }
    }
}
