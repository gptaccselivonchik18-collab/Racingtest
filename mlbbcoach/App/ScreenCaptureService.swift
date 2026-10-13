#if canImport(ScreenCaptureKit)
import SwiftUI
import ScreenCaptureKit
import CoreMedia
import CoreImage
import Observation
import UIKit
import AVFoundation

struct LiveEvidence: @unchecked Sendable {
    let generation: Int
    let image: CGImage
    let text: String
    let health: HealthObservation?
    let advice: [TacticalAdvice]
    let processingMS: Double
    let receivedAt: Double
    let detectedAt: Double
    let background: Bool
    let counts: LiveFrameCounts
}

struct LiveFrameCounts: Codable, Sendable {
    var received = 0
    var backgroundReceived = 0
    var processed = 0
    var backgroundProcessed = 0
    var dropped = 0
    var invalid = 0
    var errors = 0
    var maximumGapSeconds = 0.0
}

@available(iOS 27.0, *)
final class LiveFrameProcessor: @unchecked Sendable {
    private let lock = NSLock()
    // Software rendering avoids implicit Metal work while MLBB owns the foreground GPU.
    private let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
    private let inferenceQueue = DispatchQueue(label: "org.mlbbcoach.inference", qos: .utility)
    private var busy = false
    private var enabled = false
    private var epoch = 0
    private var calibration: LiveCalibration?
    private var streamID: ObjectIdentifier?
    private var background = false
    private var counts = LiveFrameCounts()
    private var lastReceived: Double?
    private var previousProcessing = 0.0
    private var lastScene = -1000.0
    private var lastFrame = -1000.0
    private var tracker = GameStateTracker()
    private var handler: (@Sendable (LiveEvidence) -> Void)?
    func configure(enabled: Bool, calibration: LiveCalibration?, generation: Int, streamID: ObjectIdentifier?, resetCounts: Bool = false, handler: @Sendable @escaping (LiveEvidence) -> Void) {
        lock.lock(); defer { lock.unlock() }
        epoch = generation; self.enabled = enabled; self.calibration = calibration; self.handler = handler; tracker = GameStateTracker()
        self.streamID = streamID
        lastFrame = -1000; lastScene = -1000
        if resetCounts { counts = LiveFrameCounts(); lastReceived = nil; previousProcessing = 0 }
    }
    func disable() { lock.lock(); epoch += 1; enabled = false; tracker = GameStateTracker(); lock.unlock() }
    func setBackground(_ value: Bool) { lock.lock(); background = value; tracker = GameStateTracker(); lock.unlock() }
    func snapshot() -> LiveFrameCounts { lock.lock(); defer { lock.unlock() }; return counts }
    func process(_ sample: CMSampleBuffer, streamID: ObjectIdentifier) {
        let started = ProcessInfo.processInfo.systemUptime
        let process = ProcessInfo.processInfo
        lock.lock()
        guard enabled, self.streamID == streamID else { lock.unlock(); return }
        counts.received += 1
        if background { counts.backgroundReceived += 1 }
        if let previous = lastReceived { counts.maximumGapSeconds = max(counts.maximumGapSeconds, started - previous) }
        lastReceived = started
        let minimumInterval = LiveTiming.interval(lowPower: process.isLowPowerModeEnabled, seriousHeat: process.thermalState == .serious,
                                                  previousProcessing: previousProcessing, confirmedHP: tracker.health?.fraction)
        guard !busy, started - lastFrame >= minimumInterval, process.thermalState != .critical else { counts.dropped += 1; lock.unlock(); return }
        lastFrame = started; busy = true
        let savedCalibration = calibration, callback = handler, token = epoch, isBackground = background
        // Uncalibrated preview uses scene OCR at a low frequency. Gameplay uses only the HP ROI.
        let includeScene = savedCalibration == nil && started - lastScene >= 5
        if includeScene { lastScene = started }
        lock.unlock()
        inferenceQueue.async { [self] in
        defer { lock.lock(); busy = false; lock.unlock() }
        guard CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample), let buffer = CMSampleBufferGetImageBuffer(sample) else {
            lock.lock(); if enabled && epoch == token { counts.invalid += 1; tracker = GameStateTracker() }; lock.unlock(); return
        }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let metadata = attachments.first, let rawStatus = metadata[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else {
            lock.lock(); if enabled && epoch == token { counts.invalid += 1; tracker = GameStateTracker() }; lock.unlock(); return
        }
        autoreleasepool {
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let canvas = context.createCGImage(ci, from: ci.extent) else { return }
            // Crop letterboxing before applying normalized HUD coordinates. Missing/invalid metadata disables HP.
            let rect = (metadata[.contentRect] as? [String: Any]).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            let bounds = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
            let validRect = rect.flatMap { value -> CGRect? in
                guard !value.isEmpty, !value.isInfinite, !value.isNull, bounds.contains(value) else { return nil }
                return value.integral.intersection(bounds)
            }
            let image = validRect.flatMap { canvas.cropping(to: $0) } ?? canvas
            do {
                let region = savedCalibration.flatMap { validRect != nil && $0.matches(width: image.width, height: image.height) ? $0.region : nil }
                let evidence: (text: String, health: HealthObservation?)
                if let tint = savedCalibration?.barTint, let region {
                    let hp = VisionEngine.barPixels(image, region: region).flatMap { HealthBarSensor.observe(rgba: $0, width: 200, height: 5, tint: tint, time: started) }
                    evidence = (hp.map { "Полоса HP: \(Int($0.fraction * 100))%; эвристический score, не вероятность" } ?? "Полоса HP не распознана", hp)
                } else {
                    evidence = try VisionEngine.recognize(image, at: started, hpRegion: region, useCPUOnly: true, includeScene: includeScene)
                }
                let detected = ProcessInfo.processInfo.systemUptime
                var tips: [TacticalAdvice] = []
                var confirmed: HealthObservation?
                lock.lock()
                let stillEnabled = enabled && epoch == token
                if stillEnabled {
                    confirmed = tracker.observe(evidence.health, at: detected, maxAge: 6)
                    if let hp = confirmed, LiveTiming.isFresh(frame: started, now: detected) { tips = TacticalDecisionEngine.evaluate(health: hp, at: detected, maxAge: 3) }
                    counts.processed += 1; if isBackground { counts.backgroundProcessed += 1 }
                    previousProcessing = detected - started
                }
                let statistics = counts
                lock.unlock()
                let text = savedCalibration != nil && region == nil ? "Область HP не подходит к ориентации/пропорциям кадра: требуется калибровка" : evidence.text
                if stillEnabled { callback?(LiveEvidence(generation: token, image: image, text: text, health: confirmed, advice: tips, processingMS: (detected - started) * 1000, receivedAt: started, detectedAt: detected, background: isBackground, counts: statistics)) }
            } catch {
                let detected = ProcessInfo.processInfo.systemUptime
                lock.lock(); let stillEnabled = enabled && epoch == token
                if stillEnabled { tracker = GameStateTracker(); counts.errors += 1; previousProcessing = detected - started }
                let statistics = counts; lock.unlock()
                if stillEnabled { callback?(LiveEvidence(generation: token, image: image, text: "Ошибка Vision: \(error.localizedDescription)", health: nil, advice: [], processingMS: (detected - started) * 1000, receivedAt: started, detectedAt: detected, background: isBackground, counts: statistics)) }
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
    private(set) var counts = LiveFrameCounts()
    private(set) var latestHealth: HealthObservation?
    private(set) var detectionToSpeechMS: Double?
    private(set) var frameToSpeechMS: Double?
    private(set) var speechStarts = 0
    private(set) var diagnosticError: String?
    private(set) var events: [LiveDiagnosticRow] = []
    private(set) var calibration: LiveCalibration?
    var armed = false {
        didSet {
            if !armed { voice?.stop() }
            record("armed", armed ? "Пользователь включил советы для MLBB" : "Советы выключены")
        }
    }
    var healthRegion: HUDRegion?
    var useHealthBar = true
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var evidenceGeneration = 0
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private let diagnosticQueue = DispatchQueue(label: "org.mlbbcoach.live-diagnostics", qos: .utility)
    @ObservationIgnored private var voice: VoiceCoach?
    @ObservationIgnored private let queue = DispatchQueue(label: "org.mlbbcoach.live-vision", qos: .utility)
    nonisolated private let processor = LiveFrameProcessor()

    var diagnosticURL: URL { URL.documentsDirectory.appendingPathComponent("LiveDiagnostics.json") }
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "liveCalibration"), let value = try? JSONDecoder().decode(LiveCalibration.self, from: data), value.region.isValid {
            calibration = value; healthRegion = value.region; useHealthBar = value.barTint != nil
        }
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let background = notification.name == UIApplication.didEnterBackgroundNotification
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.processor.setBackground(background)
                    if !background { self.voice?.stop() }
                    if self.active { self.configureProcessor(); self.record("lifecycle", background ? "background" : "foreground") }
                }
            })
        }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let detail = "\(notification.name.rawValue) \(notification.userInfo?.description ?? "")"
                Task { @MainActor [weak self] in
                    guard let self, self.active else { return }
                    self.record("audio", detail)
                }
            })
        }
    }
    private func record(_ kind: String, _ detail: String, eventID: UUID? = nil, detection: Double? = nil, frame: Double? = nil) {
        events.append(LiveDiagnosticRow(kind: kind, detail: String(detail.prefix(600)), background: UIApplication.shared.applicationState == .background,
                                        uptime: ProcessInfo.processInfo.systemUptime, eventID: eventID, detectionToSpeechMS: detection, frameToSpeechMS: frame))
        if events.count > 600 { events.removeFirst(events.count - 600) }
        // Per-frame suppressed advice must not trigger repeated full-journal writes.
        // Heartbeats flush these rows; speech starts and lifecycle changes flush immediately.
        if kind != "event" && kind != "speech-suppressed" { persistDiagnostics() }
    }
    private struct Report: Codable {
        let schemaVersion: Int
        let sessionID: UUID
        let updated: Date
        let system: String
        let counts: LiveFrameCounts
        let speechStarts: Int
        let calibration: LiveCalibration?
        let events: [LiveDiagnosticRow]
        let limits: String
    }
    private func persistDiagnostics() {
        let report = Report(schemaVersion: 1, sessionID: sessionID, updated: .now, system: UIDevice.current.systemVersion,
                            counts: counts, speechStarts: speechStarts, calibration: calibration, events: events,
                            limits: "No MLBB app identity verification. No pixels or OCR transcript stored. didStart is a synthesis callback, not measured acoustic output. frameToSpeech begins at the SCStream callback, not game-event onset. Physical-device acceptance required.")
        let url = diagnosticURL
        diagnosticQueue.async { [weak self] in
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(report).write(to: url, options: .atomic)
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in self?.diagnosticError = message }
            }
        }
    }
    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                self.counts = self.processor.snapshot()
                let age = self.lastUpdate.map { Date.now.timeIntervalSince($0) }
                self.record("heartbeat", "processedAgeSeconds=\(age.map { String(format: "%.1f", $0) } ?? "unknown"); thermal=\(ProcessInfo.processInfo.thermalState.rawValue); lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
            }
        }
    }

    func presentPicker(voice: VoiceCoach) {
        guard !starting else { return }
        self.voice = voice
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        picker.defaultConfiguration = configuration
        picker.remove(self); picker.add(self); picker.isActive = true
        status = "Выберите весь экран в системном окне"
        picker.present()
    }
    func applyCalibration() {
        if let region = healthRegion, !region.isValid { status = "Некорректная область HP"; return }
        if let region = healthRegion, let image = latestImage {
            guard image.width > image.height else { status = "Для HP нужен горизонтальный кадр MLBB"; return }
            var tint: [Double]?
            if useHealthBar {
                tint = VisionEngine.barPixels(image, region: region).flatMap { HealthBarSensor.learnTint(rgba: $0, width: 200, height: 5) }
                guard tint != nil else { status = "Не удалось выделить заполненную полосу. Нужен кадр с полным HP и область без рамки/иконок."; return }
            }
            calibration = LiveCalibration(region: region, aspectRatio: Double(image.width) / Double(image.height), barTint: tint)
        } else if healthRegion == nil { calibration = nil }
        if let calibration { UserDefaults.standard.set(try? JSONEncoder().encode(calibration), forKey: "liveCalibration") }
        else { UserDefaults.standard.removeObject(forKey: "liveCalibration") }
        configureProcessor()
        voice?.stop()
        record("calibration", calibration == nil ? "Не задана" : "Область собственного числового HP задана пользователем")
    }
    private func configureProcessor(resetCounts: Bool = false) {
        evidenceGeneration += 1
        latestHealth = nil
        processor.configure(enabled: active, calibration: calibration, generation: evidenceGeneration, streamID: stream.map { ObjectIdentifier($0) }, resetCounts: resetCounts) { [weak self] evidence in
            Task { @MainActor [weak self] in self?.receive(evidence) }
        }
    }
    private func receive(_ evidence: LiveEvidence) {
        guard active, evidence.generation == evidenceGeneration else { return }
        let previousText = latestText
        latestText = evidence.text; processingMS = evidence.processingMS; lastUpdate = .now
        // Keep the last landscape background frame available when the user returns for calibration.
        if evidence.background && evidence.image.width > evidence.image.height { latestImage = evidence.image }
        counts = evidence.counts; latestHealth = evidence.health
        if evidence.text.hasPrefix("Ошибка") && evidence.text != previousText { record("vision-error", evidence.text) }
        guard evidence.background, armed, UIApplication.shared.applicationState == .background,
              LiveTiming.isFresh(frame: evidence.receivedAt, now: ProcessInfo.processInfo.systemUptime),
              let tip = evidence.advice.min(by: { $0.priority < $1.priority }) else { return }
        let id = UUID(), token = evidenceGeneration
        record("event", "\(tip.key); hp=\(evidence.health?.fraction ?? -1); inferenceMS=\(Int(evidence.processingMS)); own-HP ROI asserted by user", eventID: id)
        let spokenText = calibration?.barTint == nil ? tip.text : tip.text.replacingOccurrences(of: "По OCR", with: "По выделенной полосе")
        voice?.speak(spokenText, key: tip.key, priority: tip.priority, deadline: evidence.receivedAt + 3, valid: { [weak self] in
            guard let self, self.active, self.armed, self.evidenceGeneration == token,
                  UIApplication.shared.applicationState == .background,
                  let hp = self.latestHealth, LiveTiming.isFresh(frame: hp.time, now: ProcessInfo.processInfo.systemUptime) else { return false }
            return !TacticalDecisionEngine.evaluate(health: hp, at: ProcessInfo.processInfo.systemUptime, maxAge: 3).isEmpty
        }, report: { [weak self] delivery in
            guard let self, self.evidenceGeneration == token else { return }
            switch delivery {
            case .started(let time):
                self.detectionToSpeechMS = LiveTiming.milliseconds(from: evidence.detectedAt, to: time)
                self.frameToSpeechMS = LiveTiming.milliseconds(from: evidence.receivedAt, to: time)
                self.speechStarts += 1
                self.record("speech-start", tip.key, eventID: id, detection: self.detectionToSpeechMS, frame: self.frameToSpeechMS)
            case .suppressed(let reason): self.record("speech-suppressed", reason, eventID: id)
            }
        })
    }
    private func start(filter: SCContentFilter) async {
        generation += 1
        let token = generation
        starting = true
        defer { starting = false }
        processor.disable()
        active = false; voice?.stop(); heartbeat?.invalidate(); heartbeat = nil; latestHealth = nil
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
            active = true; status = "Захват активен • адаптивный анализ живых кадров"
            sessionID = UUID(); events = []; speechStarts = 0; detectionToSpeechMS = nil; frameToSpeechMS = nil
            latestText = ""; latestImage = nil; lastUpdate = nil
            processor.setBackground(UIApplication.shared.applicationState == .background)
            configureProcessor(resetCounts: true); counts = processor.snapshot()
            record("capture-start", "Full-display picker; CPU Vision; software Core Image; microphone disabled")
            startHeartbeat()
        } catch { stream = nil; active = false; status = error.localizedDescription; record("capture-error", status) }
    }
    func stop() async {
        generation += 1
        evidenceGeneration += 1
        active = false; processor.disable(); heartbeat?.invalidate(); heartbeat = nil
        counts = processor.snapshot(); latestHealth = nil
        let old = stream; stream = nil
        if let old { try? await old.stopCapture() }
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        voice?.stop(); status = "Захват остановлен"; record("capture-stop", status)
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
            self.evidenceGeneration += 1; self.processor.disable(); self.active = false; self.latestHealth = nil
            self.heartbeat?.invalidate(); self.heartbeat = nil; self.voice?.stop()
            self.counts = self.processor.snapshot(); self.stream = nil; self.status = error.localizedDescription
            self.record("capture-error", self.status)
        }
    }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen { processor.process(sampleBuffer, streamID: ObjectIdentifier(stream)) }
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
            Section("Живой матч • проверка на iPhone") {
                Text(capture.status)
                if let updated = capture.lastUpdate { Text("Последнее наблюдение: \(updated.formatted(date: .omitted, time: .standard))").font(.caption) }
                Button("Выбрать экран для захвата") { capture.presentPicker(voice: voice) }
                Button("Остановить захват") { Task { await capture.stop() } }.disabled(!capture.active)
                Toggle("Я открыл MLBB • разрешить советы", isOn: Binding(get: { capture.armed }, set: { capture.armed = $0 }))
                Text("1. Выберите весь экран. 2. Откройте тренировочный матч MLBB. 3. Вернитесь и выделите собственное число HP. 4. Включите советы и вернитесь в MLBB. Область сохраняется между запусками. Приложение не определяет название открытой игры; выключайте советы при выходе из MLBB.").font(.caption).foregroundStyle(.secondary)
                Text("Первый сигнал — HP по двум согласованным наблюдениям. Выберите неподвижную полосу своего HP или число текущее/максимальное. Это калиброванный датчик, не полноценное понимание матча. Герои и миникарта пока не распознаются.").font(.caption).foregroundStyle(.orange)
                if let error = voice.error { Text(error).foregroundStyle(.orange) }
            }
            Section("Диагностика настоящего потока") {
                TimelineView(.periodic(from: .now, by: 1)) { clock in
                    Text(capture.lastUpdate.map { "Возраст обработанного кадра: \(Int(max(0, clock.date.timeIntervalSince($0)))) с" } ?? "Обработанные кадры ещё не поступали")
                }
                LabeledContent("Входящих кадров", value: "\(capture.counts.received)")
                LabeledContent("Входящих в фоне", value: "\(capture.counts.backgroundReceived)")
                LabeledContent("Обработанных в фоне", value: "\(capture.counts.backgroundProcessed)")
                LabeledContent("Пропущено для снижения нагрузки", value: "\(capture.counts.dropped)")
                LabeledContent("Ошибок Vision / буферов", value: "\(capture.counts.errors) / \(capture.counts.invalid)")
                LabeledContent("Максимальная пауза кадров", value: String(format: "%.1f с", capture.counts.maximumGapSeconds))
                LabeledContent("Начало голосовых подсказок", value: "\(capture.speechStarts)")
                LabeledContent("Подтверждённое HP", value: capture.latestHealth.map { "\(Int($0.fraction * 100))%" } ?? "Неизвестно")
                LabeledContent("Обнаружение → начало речи", value: capture.detectionToSpeechMS.map { "\(Int($0)) мс" } ?? "Не измерено")
                LabeledContent("Приём кадра → начало речи", value: capture.frameToSpeechMS.map { "\(Int($0)) мс" } ?? "Не измерено")
                Text("Начало речи измеряется callback didStart синтезатора, а не микрофоном. Время до обнаружения включает интервал выборки; задержка от события внутри игры неизвестна. Счётчики фона не подтверждают, что на экране именно MLBB.").font(.caption).foregroundStyle(.secondary)
                ShareLink("Экспорт диагностики JSON", item: capture.diagnosticURL)
                if let error = capture.diagnosticError { Text(error).foregroundStyle(.orange) }
            }
            if let image = capture.latestImage {
                Section("Последний обработанный кадр") {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit).overlay {
                        GeometryReader { geometry in
                            if calibrated { Rectangle().stroke(.mint, lineWidth: 2).frame(width: geometry.size.width * roi.width, height: geometry.size.height * roi.height).offset(x: geometry.size.width * roi.x, y: geometry.size.height * roi.y) }
                        }
                    }
                    Toggle("Выделить собственное HP", isOn: $calibrated)
                    if calibrated {
                        Toggle("Полоса HP вместо числа", isOn: Binding(get: { capture.useHealthBar }, set: { capture.useHealthBar = $0 }))
                        Text(capture.useHealthBar ? "Калибруйте при полном HP. Выделите всю ширину неподвижной полосы без рамок и значков. Движущаяся полоса над героем не подходит. Смена цвета, размера HUD или раскладки требует новой калибровки." : "Выделите только число текущее/максимальное собственного HP.").font(.caption)
                        Slider(value: $x, in: 0...0.95) { Text("X") }
                        Slider(value: $y, in: 0...0.95) { Text("Y") }
                        Slider(value: $width, in: 0.02...1) { Text("Ширина") }
                        Slider(value: $height, in: 0.02...1) { Text("Высота") }
                    }
                    Button("Применить область HP") { capture.healthRegion = calibrated ? roi : nil; capture.applyCalibration() }
                    Text("Последний кадр обработан за \(Int(capture.processingMS)) мс. Это время распознавания, а не полная задержка подсказки.").font(.caption)
                }
            }
            Section("Непроверенный OCR") { Text(capture.latestText.isEmpty ? "Нет наблюдений" : capture.latestText).font(.caption).textSelection(.enabled) }
            Section("Последние события") {
                ForEach(Array(capture.events.suffix(10).enumerated()), id: \.offset) { _, event in
                    Text("\(event.date.formatted(date: .omitted, time: .standard)) • \(event.kind) • \(event.detail)").font(.caption)
                }
                Text("Журнал сохраняет последние 600 событий без изображений и текста экрана. Сохраняйте отчёт перед новым запуском захвата. Реальная работа в MLBB ещё требует проверки на iPhone.").font(.caption)
            }
        }.navigationTitle("Живой тренер")
        .onAppear {
            if let region = capture.healthRegion {
                calibrated = true; x = region.x; y = region.y; width = region.width; height = region.height
            }
        }
    }
}

#endif
