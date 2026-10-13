import Foundation
import Observation
import AVFoundation

@MainActor @Observable final class PerformanceMonitor {
    var thermal = "Не измерено"
    var lowPower = false
    let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    func refresh() {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Нормальный"
        case .fair: thermal = "Умеренный нагрев"
        case .serious: thermal = "Высокий нагрев"
        case .critical: thermal = "Критический нагрев"
        @unknown default: thermal = "Неизвестно"
        }
    }
}
@MainActor @Observable final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    enum Delivery { case started(Double), suppressed(String) }
    private struct Pending {
        let deadline: Double?
        let valid: (() -> Bool)?
        let report: ((Delivery) -> Void)?
    }
    private var pending: [ObjectIdentifier: Pending] = [:]
    private let synth = AVSpeechSynthesizer()
    private var lastSpoken: [String: Date] = [:]
    private var lastTime = Date.distantPast
    var error: String?
    override init() { super.init(); synth.delegate = self }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let started = ProcessInfo.processInfo.systemUptime
        Task { @MainActor [weak self] in
            guard let self, let request = self.pending.removeValue(forKey: ObjectIdentifier(utterance)) else { return }
            guard request.deadline.map({ started <= $0 }) ?? true, request.valid?() ?? true else {
                self.synth.stopSpeaking(at: .immediate)
                request.report?(.suppressed("Устаревшее событие или захват остановлен")); return
            }
            request.report?(.started(started))
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.releaseAudioIfIdle() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.pending.removeValue(forKey: ObjectIdentifier(utterance))?.report?(.suppressed("Речь отменена до начала"))
            self?.releaseAudioIfIdle()
        }
    }
    private func releaseAudioIfIdle() {
        // A cancelled utterance can finish before its replacement starts. Keep that replacement's audio session active.
        if !synth.isSpeaking && pending.isEmpty { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    func speak(_ text: String, key: String, priority: Int = 5, deadline: Double? = nil,
               valid: (() -> Bool)? = nil, report: ((Delivery) -> Void)? = nil) {
        let settings = UserDefaults.standard
        guard AdviceMode(rawValue: settings.string(forKey: "adviceMode") ?? "") != .textOnly else { report?(.suppressed("Режим только текста")); return }
        guard settings.object(forKey: "voiceEnabled") == nil || settings.bool(forKey: "voiceEnabled") else { report?(.suppressed("Голос выключен")); return }
        guard deadline.map({ ProcessInfo.processInfo.systemUptime <= $0 }) ?? true, valid?() ?? true else { report?(.suppressed("Событие устарело")); return }
        let interval = max(5, settings.object(forKey: "voiceInterval") == nil ? 15 : settings.double(forKey: "voiceInterval"))
        guard Date.now.timeIntervalSince(lastSpoken[key] ?? .distantPast) >= max(5, settings.object(forKey: "adviceRepeat") == nil ? 45 : settings.double(forKey: "adviceRepeat")),
              priority == 1 || Date.now.timeIntervalSince(lastTime) >= interval else { report?(.suppressed("Пауза или повтор")); return }
        guard let voice = AVSpeechSynthesisVoice(language: "ru-RU") else {
            error = "Русский голос недоступен. Установите его в настройках iOS."; report?(.suppressed(error!)); return
        }
        guard !synth.isSpeaking || priority == 1 else { report?(.suppressed("Голос занят")); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            error = nil
            if priority == 1 { synth.stopSpeaking(at: .immediate) }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            pending[ObjectIdentifier(utterance)] = Pending(deadline: deadline, valid: valid, report: report)
            synth.speak(utterance); lastSpoken[key] = .now; lastTime = .now
        } catch { self.error = error.localizedDescription; report?(.suppressed(error.localizedDescription)) }
    }
    func stop() {
        let cancelled = Array(pending.values); pending.removeAll()
        for request in cancelled { request.report?(.suppressed("Озвучивание остановлено")) }
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
