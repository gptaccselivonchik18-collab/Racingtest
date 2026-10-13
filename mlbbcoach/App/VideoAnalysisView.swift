import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct VideoAnalysisView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("sampleInterval") private var interval = 3.0
    @State private var importer = false
    @State private var selected: URL?
    @State private var preview: UIImage?
    @State private var duration = 0.0
    @State private var previewTime = 0.0
    @State private var hpEnabled = false
    @State private var x = 0.35
    @State private var y = 0.80
    @State private var width = 0.30
    @State private var height = 0.10
    @State private var progress = 0.0
    @State private var status: String?
    @State private var operation: Task<Void, Never>?
    private let analyzer = VideoAnalyzer()
    private var roi: HUDRegion { HUDRegion(x: x, y: y, width: min(width, 1 - x), height: min(height, 1 - y)) }
    var body: some View {
        Form {
            Section("Запись матча") {
                Button("Выбрать видео из Файлов") { importer = true }.disabled(operation != nil)
                if let selected { Text(selected.lastPathComponent).font(.caption) }
                Text("Если видео в Фото, сначала сохраните его в Файлы. Обработка выполняется на устройстве; серверу запись не отправляется.").font(.caption).foregroundStyle(.secondary)
            }
            if let preview {
                Section("Калибровка числового HP • необязательно") {
                    Image(uiImage: preview).resizable().aspectRatio(contentMode: .fit).overlay {
                        GeometryReader { geometry in
                            if hpEnabled {
                                Rectangle().stroke(.mint, lineWidth: 2)
                                    .frame(width: geometry.size.width * roi.width, height: geometry.size.height * roi.height)
                                    .offset(x: geometry.size.width * roi.x, y: geometry.size.height * roi.y)
                            }
                        }
                    }
                    Slider(value: $previewTime, in: 0...max(1, duration - 0.1))
                    Button("Показать кадр: \(Int(previewTime)) с") { loadPreview() }.disabled(operation != nil)
                    Toggle("Я указал область собственного HP", isOn: $hpEnabled).disabled(operation != nil)
                    if hpEnabled {
                        Text("Выделите только число текущее/максимальное HP своего героя. Полоса без чисел не поддерживается. Убедитесь, что HUD не смещается во время записи.").font(.caption)
                        slider("X", value: $x, range: 0...0.95)
                        slider("Y", value: $y, range: 0...0.95)
                        slider("Ширина", value: $width, range: 0.02...1)
                        slider("Высота", value: $height, range: 0.02...1)
                    }
                }
                Section("Локальный анализ") {
                    if operation == nil {
                        Button("Анализировать запись") { analyze() }
                    } else {
                        ProgressView(value: progress)
                        Button("Отменить") { operation?.cancel() }
                    }
                    Text("Общий OCR показывает найденный текст с уверенностью модели. Герои, миникарта и способности автоматически не определяются.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let status { Section { Text(status).textSelection(.enabled) } }
        }.navigationTitle("Анализ видео")
        .fileImporter(isPresented: $importer, allowedContentTypes: [.movie]) { result in
            do { selected = try result.get(); preview = nil; hpEnabled = false; previewTime = 0; loadPreview() }
            catch { status = error.localizedDescription }
        }
        .onDisappear { operation?.cancel() }
    }
    private func slider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack { Text(name).frame(width: 70, alignment: .leading); Slider(value: value, in: range) }.disabled(operation != nil)
    }
    private func loadPreview() {
        guard let selected, operation == nil else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let result = try await analyzer.preview(url: selected, at: previewTime)
                try Task.checkCancellation()
                preview = UIImage(cgImage: result.0); duration = result.1; status = nil
            } catch is CancellationError { status = "Отменено" }
            catch { status = error.localizedDescription }
        }
    }
    private func analyze() {
        guard let selected, operation == nil else { return }
        let healthRegion = hpEnabled ? roi : nil
        progress = 0; status = nil
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let result = try await analyzer.analyze(url: selected, interval: interval, hpRegion: healthRegion) { value in
                    await MainActor.run { progress = value }
                }
                try Task.checkCancellation()
                let report = MatchRecord(title: selected.lastPathComponent, duration: result.duration, frameCount: result.frames, processingSeconds: result.processingSeconds, transcript: result.transcript)
                report.summary = result.advice
                context.insert(report); try context.save()
                status = "Сохранено в Матчи. Обработано \(result.frames) кадров за \(Int(result.processingSeconds)) с.\n\(result.advice)"
            } catch is CancellationError { status = "Анализ отменён. Неполный отчёт не сохранён." }
            catch { context.rollback(); status = error.localizedDescription }
        }
    }
}
