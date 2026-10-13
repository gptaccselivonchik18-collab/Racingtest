import Foundation
import CoreML
import Vision
import CryptoKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct InstalledModel: Codable, Sendable {
    let name: String
    let sha256: String
    let source: String
    let license: String
    let installed: Date
    let bytes: Int
}
actor ModelManager {
    static let shared = ModelManager()
    private var root: URL { URL.applicationSupportDirectory.appendingPathComponent("CoachModels", isDirectory: true) }
    func current() throws -> InstalledModel? {
        let url = root.appendingPathComponent("active/manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(InstalledModel.self, from: Data(contentsOf: url))
    }
    func activeModelURL() -> URL? {
        let url = root.appendingPathComponent("active/model.mlmodelc")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func install(url: URL, expectedSHA: String, source: String, license: String) throws -> InstalledModel {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == "mlmodel", !license.isEmpty, URL(string: source)?.scheme == "https",
              expectedSHA.count == 64, expectedSHA.allSatisfy(\.isHexDigit) else {
            throw DataValidationError.invalid("Нужны .mlmodel, SHA-256 (64 hex-символа), HTTPS-источник и лицензия")
        }
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0, bytes <= 150_000_000 else { throw DataValidationError.invalid("Модель должна занимать до 150 МБ") }
        let hash = SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
        guard hash == expectedSHA.lowercased() else { throw DataValidationError.invalid("SHA-256 модели не совпадает с указанным") }
        try Task.checkCancellation()
        let compiled = try MLModel.compileModel(at: url)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: compiled, configuration: config)
        guard model.modelDescription.inputDescriptionsByName.values.contains(where: { $0.type == .image }) else { throw DataValidationError.invalid("Нужна модель с входом image для Vision") }
        let vision = try VNCoreMLModel(for: model)
        guard let canvas = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let image = canvas.makeImage() else { throw DataValidationError.invalid("Не удалось подготовить проверочный кадр") }
        let request = VNCoreMLRequest(model: vision); request.imageCropAndScaleOption = .scaleFit
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let results = request.results, results.allSatisfy({ $0 is VNRecognizedObjectObservation || $0 is VNClassificationObservation }) else { throw DataValidationError.invalid("Неподдерживаемый выход модели. Нужен классификатор или Vision-совместимый детектор объектов.") }
        let manifest = InstalledModel(name: url.lastPathComponent, sha256: hash, source: source, license: license, installed: .now, bytes: bytes)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: compiled, to: staging.appendingPathComponent("model.mlmodelc"))
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        try Task.checkCancellation()
        let active = root.appendingPathComponent("active")
        let previous = root.appendingPathComponent("previous")
        if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
        let hadActive = FileManager.default.fileExists(atPath: active.path)
        if hadActive { try FileManager.default.moveItem(at: active, to: previous) }
        do { try FileManager.default.moveItem(at: staging, to: active) }
        catch { if hadActive { try? FileManager.default.moveItem(at: previous, to: active) }; throw error }
        return manifest
    }
    func rollback() throws {
        let active = root.appendingPathComponent("active"), previous = root.appendingPathComponent("previous")
        guard FileManager.default.fileExists(atPath: previous.path) else { throw DataValidationError.invalid("Предыдущая модель отсутствует") }
        let temporary = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: active, to: temporary)
        do { try FileManager.default.moveItem(at: previous, to: active) }
        catch { try? FileManager.default.moveItem(at: temporary, to: active); throw error }
        try FileManager.default.moveItem(at: temporary, to: previous)
    }
}

struct CustomModelView: View {
    @AppStorage("useCustomModel") private var useModel = false
    @State private var source = ""
    @State private var license = ""
    @State private var sha = ""
    @State private var picker = false
    @State private var installed: InstalledModel?
    @State private var status: String?
    @State private var operation: Task<Void, Never>?
    var body: some View {
        Form {
            Section("Core ML • локальная модель зрения") {
                Toggle("Использовать при разборе видео", isOn: $useModel)
                if let installed {
                    Text(installed.name)
                    Text("Исходный файл: \(installed.bytes / 1_000_000) МБ").font(.caption)
                    Text(installed.source).font(.caption).textSelection(.enabled)
                    Text("Лицензия: \(installed.license)").font(.caption)
                    Text(installed.sha256).font(.caption2).textSelection(.enabled)
                    Button("Откатить предыдущую модель") { rollback() }.disabled(operation != nil)
                } else { Text("Дополнительная модель не установлена") }
                Text("Поддерживаются классификаторы и Vision-совместимые детекторы .mlmodel до 150 МБ. Метки модели сохраняются как непроверенные наблюдения и не превращаются автоматически в игровые факты.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Установка без пересборки IPA") {
                TextField("HTTPS-источник модели", text: $source).textInputAutocapitalization(.never)
                TextField("Лицензия / разрешение владельца", text: $license)
                TextField("Ожидаемый SHA-256 от источника", text: $sha).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Импорт .mlmodel из Файлов") { picker = true }.disabled(operation != nil)
                Text("Скачайте модель из доверенного источника в Файлы. Встроенного обученного детектора MLBB нет; совместимость модели проверяется перед активацией.").font(.caption).foregroundStyle(.secondary)
                if operation != nil { ProgressView("Компиляция и проверка модели…") }
                if let status { Text(status).foregroundStyle(.orange) }
            }
        }.navigationTitle("Core ML")
        .task { do { installed = try await ModelManager.shared.current() } catch { status = error.localizedDescription } }
        .fileImporter(isPresented: $picker, allowedContentTypes: [UTType(filenameExtension: "mlmodel") ?? .data]) { result in
            do {
                let url = try result.get()
                operation = Task { @MainActor in
                    defer { operation = nil }
                    do { installed = try await ModelManager.shared.install(url: url, expectedSHA: sha.trimmingCharacters(in: .whitespacesAndNewlines), source: source, license: license); status = "Модель установлена и прошла проверочный запуск" }
                    catch { status = error.localizedDescription }
                }
            } catch { status = error.localizedDescription }
        }.onDisappear { operation?.cancel() }
    }
    private func rollback() {
        operation = Task { @MainActor in
            defer { operation = nil }
            do { try await ModelManager.shared.rollback(); installed = try await ModelManager.shared.current(); status = "Модель восстановлена" }
            catch { status = error.localizedDescription }
        }
    }
}
