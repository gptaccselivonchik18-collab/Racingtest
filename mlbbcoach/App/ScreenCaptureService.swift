#if canImport(ScreenCaptureKit)
import SwiftUI
import ScreenCaptureKit
import CoreMedia
import CoreImage
import Observation
import UIKit

struct LiveEvidence: @unchecked Sendable {
    let image: CGImage
    let text: String
    let advice: [TacticalAdvice]
    let processingMS: Double
}

final class LiveFrameProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let inferenceQueue = DispatchQueue(label: "org.mlbbcoach.inference", qos: .utility)
    private var busy = false
    private var enabled = false
    private var epoch = 0
    private var roi: HUDRegion?
    private var lastFrame = -1000.0
    private var tracker = GameStateTracker()
    private var handler: (@Sendable (LiveEvidence) -> Void)?
    func configure(enabled: Bool, roi: HUDRegion?, handler: @Sendable @escaping (LiveEvidence) -> Void) {
        lock.lock(); defer { lock.unlock() }
        epoch += 1; self.enabled = enabled; self.roi = roi; self.handler = handler; tracker = GameStateTracker()
    }
    func disable() { lock.lock(); epoch += 1; enabled = false; tracker = GameStateTracker(); lock.unlock() }
    func process(_ sample: CMSampleBuffer) {
        let started = ProcessInfo.processInfo.systemUptime
        let process = ProcessInfo.processInfo
        lock.lock()
        let minimumInterval = process.isLowPowerModeEnabled || process.thermalState == .serious ? 5.0 : 2.0
        guard enabled, !busy, started - lastFrame >= minimumInterval, process.thermalState != .critical else { lock.unlock(); return }
        lastFrame = started; busy = true
        let region = roi, callback = handler, token = epoch
        lock.unlock()
        inferenceQueue.async { [self] in
        defer { lock.lock(); busy = false; lock.unlock() }
        guard CMSampleBufferIsValid(sample), let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        autoreleasepool {
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let image = context.createCGImage(ci, from: ci.extent) else { return }
            do {
                let evidence = try VisionEngine.recognize(image, at: started, hpRegion: region)
                var tips: [TacticalAdvice] = []
                lock.lock()
                let stillEnabled = enabled && epoch == token
                if stillEnabled, let hp = tracker.observe(evidence.health, at: ProcessInfo.processInfo.systemUptime) {
                    tips = TacticalDecisionEngine.evaluate(health: hp, at: ProcessInfo.processInfo.systemUptime)
                }
                lock.unlock()
                if stillEnabled { callback?(LiveEvidence(image: image, text: evidence.text, advice: tips, processingMS: (ProcessInfo.processInfo.systemUptime - started) * 1000)) }
            } catch {
                lock.lock(); let stillEnabled = enabled && epoch == token; if stillEnabled { tracker = GameStateTracker() }; lock.unlock()
                if stillEnabled { callback?(LiveEvidence(image: image, text: "Ошибка Vision: \(error.localizedDescription)", advice: [], processingMS: (ProcessInfo.processInfo.systemUptime - started) * 1000)) }
            }
        }
        }
    }
}

@available(iOS 27.0, *)
@MainActor @Observable final class ScreenCaptureService: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    private(set) var active = false
    private(set) var status = "Захват не запущен"
    private(set) var latestText = ""
    private(set) var latestImage: CGImage?
    private(set) var processingMS = 0.0
    private(set) var lastUpdate: Date?
    var healthRegion: HUDRegion?
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var voice: VoiceCoach?
    @ObservationIgnored private let queue = DispatchQueue(label: "org.mlbbcoach.live-vision", qos: .utility)
    nonisolated private let processor = LiveFrameProcessor()

    func presentPicker(voice: VoiceCoach) {
        guard !starting else { return }
        self.voice = voice
        let picker = SCContentSharingPicker.shared
        picker.remove(self); picker.add(self); picker.isActive = true
        status = "Выберите весь экран в системном окне"
        picker.present()
    }
    func applyCalibration() {
        if let region = healthRegion, !region.isValid { status = "Некорректная область HP"; return }
        processor.configure(enabled: active, roi: healthRegion) { [weak self] evidence in
            Task { @MainActor [weak self] in self?.receive(evidence) }
        }
    }
    private func receive(_ evidence: LiveEvidence) {
        guard active else { return }
        latestText = evidence.text; latestImage = evidence.image; processingMS = evidence.processingMS; lastUpdate = .now
        guard UIApplication.shared.applicationState == .background else { return }
        for tip in evidence.advice.sorted(by: { $0.priority < $1.priority }) {
            voice?.speak(tip.text, key: tip.key, priority: tip.priority)
        }
    }
    private func start(filter: SCContentFilter) async {
        generation += 1
        let token = generation
        starting = true
        defer { starting = false }
        processor.disable()
        if let previous = stream { try? await previous.stopCapture() }
        guard token == generation else { return }
        let config = SCStreamConfiguration()
        config.width = 1920; config.height = 1080
        config.capturesAudio = false
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            stream = newStream
            try await newStream.startCapture()
            guard token == generation else { try? await newStream.stopCapture(); return }
            active = true; status = "Захват активен • OCR не чаще одного раза в 2 с"
            applyCalibration()
        } catch { stream = nil; active = false; status = error.localizedDescription }
    }
    func stop() async {
        generation += 1
        active = false; processor.disable()
        let old = stream; stream = nil
        if let old { try? await old.stopCapture() }
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        voice?.stop(); status = "Захват остановлен"
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in await self?.start(filter: filter) }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in if self?.active == false { self?.status = "Выбор отменён" } }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor [weak self] in self?.status = error.localizedDescription }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.processor.disable(); self.active = false; self.status = error.localizedDescription
        }
    }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen { processor.process(sampleBuffer) }
    }
}

@available(iOS 27.0, *)
struct LiveCaptureView: View {
    @Environment(ScreenCaptureService.self) private var capture
    @Environment(VoiceCoach.self) private var voice
    @State private var calibrated = false
    @State private var x = 0.35
    @State private var y = 0.80
    @State private var width = 0.30
    @State private var height = 0.10
    private var roi: HUDRegion { HUDRegion(x: x, y: y, width: min(width, 1 - x), height: min(height, 1 - y)) }
    var body: some View {
        Form {
            Section("Экспериментальный режим • iOS 27") {
                Text(capture.status)
                if let updated = capture.lastUpdate { Text("Последнее наблюдение: \(updated.formatted(date: .omitted, time: .standard))").font(.caption) }
                Button("Выбрать экран для захвата") { capture.presentPicker(voice: voice) }
                Button("Остановить захват") { Task { await capture.stop() } }.disabled(!capture.active)
                Text("После системного разрешения откройте MLBB. Затем вернитесь сюда для проверки кадра и калибровки. Длительная фоновая работа, расход батареи и совместимость с бесплатной подписью пока не проверены на iPhone.").font(.caption).foregroundStyle(.secondary)
            }
            if let image = capture.latestImage {
                Section("Последний обработанный кадр") {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit).overlay {
                        GeometryReader { geometry in
                            if calibrated { Rectangle().stroke(.mint, lineWidth: 2).frame(width: geometry.size.width * roi.width, height: geometry.size.height * roi.height).offset(x: geometry.size.width * roi.x, y: geometry.size.height * roi.y) }
                        }
                    }
                    Toggle("Выделить число собственного HP", isOn: $calibrated)
                    if calibrated {
                        Text("Только число текущее/максимальное HP. Выделение полосы или чужого HP даст неверный результат.").font(.caption)
                        Slider(value: $x, in: 0...0.95) { Text("X") }
                        Slider(value: $y, in: 0...0.95) { Text("Y") }
                        Slider(value: $width, in: 0.02...1) { Text("Ширина") }
                        Slider(value: $height, in: 0.02...1) { Text("Высота") }
                    }
                    Button("Применить область HP") { capture.healthRegion = calibrated ? roi : nil; capture.applyCalibration() }
                    Text("Последний кадр обработан за \(Int(capture.processingMS)) мс. Это время OCR, а не полная задержка подсказки.").font(.caption)
                }
            }
            Section("Непроверенный OCR") { Text(capture.latestText.isEmpty ? "Нет наблюдений" : capture.latestText).font(.caption).textSelection(.enabled) }
        }.navigationTitle("Захват экрана")
    }
}

#endif
