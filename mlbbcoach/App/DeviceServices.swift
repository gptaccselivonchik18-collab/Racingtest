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
    private let synth = AVSpeechSynthesizer()
    private var lastSpoken: [String: Date] = [:]
    private var lastTime = Date.distantPast
    var error: String?
    override init() { super.init(); synth.delegate = self }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.releaseAudioIfIdle() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.releaseAudioIfIdle() }
    }
    private func releaseAudioIfIdle() {
        if !synth.isSpeaking { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    func speak(_ text: String, key: String, priority: Int = 5) {
        let settings = UserDefaults.standard
        guard settings.object(forKey: "voiceEnabled") == nil || settings.bool(forKey: "voiceEnabled") else { return }
        let interval = max(5, settings.double(forKey: "voiceInterval"))
        guard Date.now.timeIntervalSince(lastSpoken[key] ?? .distantPast) >= 45,
              priority == 1 || Date.now.timeIntervalSince(lastTime) >= interval else { return }
        guard let voice = AVSpeechSynthesisVoice(language: "ru-RU") else {
            error = "Русский голос недоступен. Установите его в настройках iOS."; return
        }
        guard !synth.isSpeaking || priority == 1 else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if priority == 1 { synth.stopSpeaking(at: .immediate) }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance); lastSpoken[key] = .now; lastTime = .now
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
