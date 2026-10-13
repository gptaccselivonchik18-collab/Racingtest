import Foundation
import AVFoundation
import Vision
import CoreGraphics
import CoreML

struct VideoResult: Sendable {
    let duration: Double
    let frames: Int
    let processingSeconds: Double
    let transcript: String
    let advice: String
}

actor VideoAnalyzer {
    func preview(url: URL, at seconds: Double) async throws -> (CGImage, Double) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw CoachError.unavailable("Не удалось прочитать длительность видео") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let frame = try await generator.image(at: CMTime(seconds: min(max(0, seconds), max(0, duration - 0.1)), preferredTimescale: 600))
        return (frame.image, duration)
    }

    func analyze(url: URL, interval: Double, hpRegion: HUDRegion?, progress: @Sendable @escaping (Double) async -> Void) async throws -> VideoResult {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let started = Date.now
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 14400 else { throw CoachError.unavailable("Поддерживаются записи длительностью до 4 часов") }
        guard hpRegion == nil || hpRegion!.isValid else { throw CoachError.unavailable("Область HP выходит за пределы изображения") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        var customModel: VNCoreMLModel?
        if UserDefaults.standard.bool(forKey: "useCustomModel"), let url = await ModelManager.shared.activeModelURL() {
            let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
            customModel = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: config))
        }
        let baseInterval = max(1, min(10, interval.isFinite ? interval : 3))
        var time = 0.0
        var frames = 0
        var lines: [String] = []
        var advice: [String] = []
        var lastAdvice: [String: Double] = [:]
        var priorLowHP: HealthObservation?
        var lastText = ""
        while time < duration && frames < 2000 {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.thermalState == .critical { throw CoachError.unavailable("Анализ остановлен из-за критического нагрева. Повторите после охлаждения.") }
            let frame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            let observedTime = frame.actualTime.seconds
            let evidence = try autoreleasepool { try VisionEngine.recognize(frame.image, at: observedTime, hpRegion: hpRegion, model: customModel) }
            frames += 1
            if evidence.text != lastText && !evidence.text.isEmpty && lines.count < 500 {
                lines.append("[\(Int(observedTime)) с] OCR (непроверенный текст): \(evidence.text.prefix(1000))")
                lastText = evidence.text
            }
            if let hp = evidence.health, hp.fraction <= 0.30 {
                if let previous = priorLowHP, abs(hp.fraction - previous.fraction) < 0.12, hp.time - previous.time <= 30 {
                    for tip in TacticalDecisionEngine.evaluate(health: hp, at: observedTime) {
                        if observedTime - (lastAdvice[tip.key] ?? -1000) >= 45 {
                            advice.append("[\(Int(observedTime)) с] \(tip.text)"); lastAdvice[tip.key] = observedTime
                        }
                    }
                }
                priorLowHP = hp
            } else { priorLowHP = nil }
            await progress(min(1, time / duration))
            let heavy = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState == .serious
            time += max(baseInterval * (heavy ? 2 : 1), duration / 2000)
        }
        await progress(1)
        return VideoResult(duration: duration, frames: frames, processingSeconds: Date.now.timeIntervalSince(started), transcript: lines.joined(separator: "\n\n"), advice: advice.isEmpty ? "Подтверждённых тактических сигналов не получено. OCR без калибровки не определяет HP, героев и навыки." : advice.joined(separator: "\n\n"))
    }

}
