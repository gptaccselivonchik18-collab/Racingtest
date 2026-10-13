import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import CoreGraphics
import UIKit
import Observation

struct IconExample: Codable, Identifiable, Sendable {
    let id: UUID
    let sourceHash: String
    let group: String
    let label: IconLabel
    let validation: Bool
    let features: [Double]
}
struct IconSlot: Codable, Sendable {
    let region: HUDRegion
    let side: String
}
// The exact same 16x16 RGB preprocessing is used for annotations and live inference.
final class IconInference: @unchecked Sendable {
    static let shared = IconInference()
    private let lock = NSLock()
    private var model: IconNetworkVersion?
    private var slots: [IconSlot] = []
    private var previous: [Int: RecognizedIcon] = [:]
    private var confirmed: [RecognizedIcon] = []
    private var last = -1000.0
    private var aspect = 0.0
    private init() { reload() }
    func reload() {
        lock.lock(); defer { lock.unlock() }
        model = (try? Data(contentsOf: IconLearningStore.root.appendingPathComponent("active.json"))).flatMap { try? JSONDecoder().decode(IconNetworkVersion.self, from: $0) }
        if model?.valid != true { model = nil }
        slots = (UserDefaults.standard.data(forKey: "iconSlots")).flatMap { try? JSONDecoder().decode([IconSlot].self, from: $0) } ?? []
        aspect = UserDefaults.standard.double(forKey: "iconAspect")
        previous = [:]; confirmed = []; last = -1000
    }
    func resetEvidence() { lock.lock(); previous = [:]; confirmed = []; last = -1000; lock.unlock() }
    func recognize(_ image: CGImage, at now: Double) -> [RecognizedIcon] {
        lock.lock(); defer { lock.unlock() }
        guard now - last >= 3 else { return confirmed.filter { now - $0.observedAt <= 6 } }; last = now
        guard let model, image.width > image.height, aspect > 1, abs(Double(image.width)/Double(image.height)-aspect)/aspect < 0.03 else { previous = [:]; return [] }
        var result: [RecognizedIcon] = [], next: [Int: RecognizedIcon] = [:]
        for (index, slot) in slots.prefix(12).enumerated() {
            guard let x = IconPixels.features(image, region: slot.region), let p = model.network.probabilities(x), let k = p.indices.max(by: { p[$0] < p[$1] }), p[k] >= 0.85 else { continue }
            let reading = RecognizedIcon(slot: slot.side, code: model.labels[k].code, score: p[k], observedAt: now)
            next[index] = reading
            if let old = previous[index], old.code == reading.code, now > old.observedAt, now - old.observedAt <= 7 { result.append(reading) }
        }
        previous = next; confirmed = result; return result
    }
}
actor IconLearningStore {
    static let shared = IconLearningStore()
    nonisolated static var root: URL { URL.applicationSupportDirectory.appendingPathComponent("IconLearning", isDirectory: true) }
    private func read<T: Decodable>(_ name: String, _ type: T.Type) throws -> T? {
        let path = Self.root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path); guard data.count < 30_000_000 else { throw NeuralError.invalidData }
        return try JSONDecoder().decode(type, from: data)
    }
    private func write<T: Encodable>(_ value: T, _ name: String) throws {
        try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: Self.root.appendingPathComponent(name), options: .atomic)
    }
    func examples() throws -> [IconExample] { try read("examples.json", [IconExample].self) ?? [] }
    func current() throws -> IconNetworkVersion? { try read("active.json", IconNetworkVersion.self) }
    func add(imageData: Data, region: HUDRegion, label: IconLabel, group: String, validation: Bool) throws {
        guard label.valid, !group.isEmpty, group.count <= 80, imageData.count <= 25_000_000,
              let image = UIImage(data: imageData)?.cgImage, let features = IconPixels.features(image, region: region) else { throw NeuralError.invalidData }
        var all = try examples(); guard all.count < 500 else { throw CoachError.unavailable("Лимит 500 примеров; удалите старые") }
        let hash = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        guard !all.contains(where: { ($0.sourceHash == hash || $0.group == group) && $0.validation != validation }) else { throw NeuralError.invalidSplit }
        guard !all.contains(where: { $0.features == features }) else { throw CoachError.unavailable("Такая область уже размечена") }
        let sample = IconExample(id: UUID(), sourceHash: hash, group: group, label: label, validation: validation, features: features)
        let crop = image.cropping(to: CGRect(x: region.x * Double(image.width), y: region.y * Double(image.height), width: region.width * Double(image.width), height: region.height * Double(image.height)).integral)
        guard let crop, let png = UIImage(cgImage: crop).pngData() else { throw NeuralError.invalidData }
        try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        let path = Self.root.appendingPathComponent(sample.id.uuidString + ".png")
        try png.write(to: path, options: .atomic)
        all.append(sample)
        do { try write(all, "examples.json") } catch { try? FileManager.default.removeItem(at: path); throw error }
    }
    func remove(_ id: UUID) throws {
        let all = try examples().filter { $0.id != id }; try write(all, "examples.json")
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(id.uuidString + ".png"))
    }
    func train() throws -> IconNetworkVersion {
        let all = try examples()
        let labels = Array(Set(all.map(\.label))).sorted { $0.code < $1.code }
        guard labels.count >= 2, labels.count <= 32, Set(labels.map(\.code)).count == labels.count else { throw NeuralError.invalidData }
        func vectors(_ test: Bool) -> [LabeledVector] { all.filter { $0.validation == test }.map { LabeledVector(group: $0.group, features: $0.features, label: labels.firstIndex(of: $0.label)!) } }
        let train = vectors(false), test = vectors(true)
        try TrainableNetwork.validateSplit(train: train, test: test, classes: labels.count)
        let previous = try current()
        var network = previous?.labels == labels ? previous!.network : TrainableNetwork(inputs: 768, outputs: labels.count)
        let original = network
        guard let before = network.metrics(test) else { throw NeuralError.invalidData }
        try network.train(train)
        guard let after = network.metrics(test) else { throw NeuralError.invalidData }
        let version = IconNetworkVersion(labels: labels, network: network, before: before, after: after, parametersChanged: original.w1 != network.w1 || original.w2 != network.w2)
        try write(version, "candidate.json")
        // Dataset changes never silently replace an incumbent with unrelated labels.
        let incumbentMetric = previous.flatMap { $0.labels == labels ? $0.network.metrics(test) : nil }
        if version.parametersChanged, TrainableNetwork.shouldPromote(before: incumbentMetric ?? before, after: after), previous == nil || previous?.labels == labels {
            if let previous { try write(previous, "previous.json") }
            try write(version, "active.json"); IconInference.shared.reload()
        }
        return version
    }
    func rollback() throws {
        guard let previous = try read("previous.json", IconNetworkVersion.self), previous.valid else { throw CoachError.unavailable("Нет предыдущей версии") }
        let active = try current(); try write(previous, "active.json")
        if let active { try write(active, "previous.json") }
        IconInference.shared.reload()
    }
}

struct IconLearningView: View {
    @State private var data: Data?
    @State private var importing = false
    @State private var code = ""
    @State private var russian = ""
    @State private var group = ""
    @State private var validation = false
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var width = 1.0
    @State private var height = 1.0
    @State private var examples: [IconExample] = []
    @State private var status = ""
    @State private var busy = false
    @State private var training: Task<Void, Never>?
    @State private var side = "unknown"
    private var roi: HUDRegion { HUDRegion(x: x, y: y, width: min(width, 1-x), height: min(height, 1-y)) }
    var body: some View {
        Form {
            Section("Разметка настоящих иконок") {
                Button("Открыть скриншот MLBB") { importing = true }
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).overlay {
                        GeometryReader { g in Rectangle().stroke(.mint).frame(width: g.size.width * roi.width, height: g.size.height * roi.height).offset(x: g.size.width * roi.x, y: g.size.height * roi.y) }
                    }
                    Slider(value: $x, in: 0...0.95); Slider(value: $y, in: 0...0.95)
                    Slider(value: $width, in: 0.02...1); Slider(value: $height, in: 0.02...1)
                }
                TextField("Код героя латиницей: layla", text: $code).textInputAutocapitalization(.never)
                TextField("Название по-русски", text: $russian)
                TextField("Группа исходного матча", text: $group)
                Toggle("Отложенная проверка • не обучение", isOn: $validation)
                Button("Сохранить правильный пример") { run { try await IconLearningStore.shared.add(imageData: data ?? Data(), region: roi, label: IconLabel(code: code, russian: russian), group: group, validation: validation); status = "Пример сохранён" } }.disabled(data == nil || busy)
                Text("Выделяйте одну иконку без рамки. Для каждого класса нужны минимум 3 обучающих и 2 проверочных изображения из других матчей. Группы задайте честно: соседние кадры одного матча — одна группа. Softmax score не является проверенной вероятностью.").font(.caption)
            }
            Section("Реальные параметры нейросети") {
                Button("Обучить и сравнить на отложенных данных") {
                    training = Task { @MainActor in
                        busy = true; LiveTrainingGuard.training = true; defer { busy = false; LiveTrainingGuard.training = false; training = nil }
                        do {
                            let process = ProcessInfo.processInfo
                            guard process.thermalState == .nominal || process.thermalState == .fair, !LiveTrainingGuard.active else { throw CoachError.unavailable("Обучение допускается вне захвата и без сильного нагрева") }
                            let v = try await IconLearningStore.shared.train()
                            let active = try await IconLearningStore.shared.current()
                            status = "Веса изменены: \(v.parametersChanged ? "да" : "нет"). Проверка: \(v.after.count) изображений. Точность \(Int(v.before.accuracy*100)) → \(Int(v.after.accuracy*100))%. Loss \(String(format: "%.3f", v.before.loss)) → \(String(format: "%.3f", v.after.loss)). \(active?.id == v.id ? "Версия активирована" : "Кандидат сохранён, активная модель не заменена")"
                        } catch { status = error.localizedDescription }
                    }
                }.disabled(busy)
                if busy { ProgressView(); Button("Отменить") { training?.cancel() } }
                Button("Вернуть предыдущие веса") { run { try await IconLearningStore.shared.rollback(); status = "Веса предыдущей версии восстановлены" } }.disabled(busy)
                Text(status).textSelection(.enabled)
                Button("Показать активную версию") { run { let v = try await IconLearningStore.shared.current(); status = v.map { "Версия \($0.id), проверка \($0.after.count), точность \(Int($0.after.accuracy*100))%. Это качество вашей выборки, не всей MLBB." } ?? "Обученной активной модели нет" } }
            }
            Section("Область для живого распознавания") {
                Picker("Сторона иконки • задана вами", selection: $side) { Text("Союзник").tag("ally"); Text("Противник").tag("enemy"); Text("Неизвестно").tag("unknown") }
                Button("Добавить выделенную область в живой анализ") {
                    guard let data, let image = UIImage(data: data)?.cgImage, image.width > image.height else { status = "Нужен горизонтальный скриншот"; return }
                    var slots = UserDefaults.standard.data(forKey: "iconSlots").flatMap { try? JSONDecoder().decode([IconSlot].self, from: $0) } ?? []
                    guard slots.count < 12 else { status = "Лимит 12 областей"; return }
                    slots.append(IconSlot(region: roi, side: side))
                    UserDefaults.standard.set(try? JSONEncoder().encode(slots), forKey: "iconSlots")
                    UserDefaults.standard.set(Double(image.width)/Double(image.height), forKey: "iconAspect"); IconInference.shared.reload(); status = "Область добавлена; сторона задана пользователем, не распознана моделью"
                }
                Button("Очистить области") { UserDefaults.standard.removeObject(forKey: "iconSlots"); IconInference.shared.reload() }
            }
            Section("Размеченные примеры: \(examples.count)") {
                ForEach(examples) { e in
                    HStack { Text("\(e.label.russian) • \(e.group) • \(e.validation ? "проверка" : "обучение")"); Spacer(); Button("Удалить", role: .destructive) { run { try await IconLearningStore.shared.remove(e.id) } } }
                }
            }
        }.navigationTitle("Обучение иконок").task { await refresh() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard bytes > 0, bytes <= 25_000_000 else { throw NeuralError.invalidData }
                data = try Data(contentsOf: url)
            } catch { status = error.localizedDescription }
        }
    }
    private func refresh() async { do { examples = try await IconLearningStore.shared.examples() } catch { status = error.localizedDescription } }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) { Task { do { try await operation(); await refresh() } catch { status = error.localizedDescription } } }
}
@MainActor enum LiveTrainingGuard { static var active = false; static var training = false }
