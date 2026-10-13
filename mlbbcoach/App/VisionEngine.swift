import Foundation
import Vision
import CoreGraphics
import CoreML
#if SWIFT_PACKAGE
import CoachCore
#endif

public enum VisionEngine {
    public static func recognize(_ image: CGImage, at time: Double, hpRegion: HUDRegion?, model: VNCoreMLModel? = nil, useCPUOnly: Bool = false, includeScene: Bool = true) throws -> (text: String, health: HealthObservation?) {
        let full = VNRecognizeTextRequest()
        full.revision = VNRecognizeTextRequestRevision3
        full.recognitionLevel = .accurate; full.usesLanguageCorrection = false
        let supported: [String]
        do { supported = try full.supportedRecognitionLanguages() }
        catch { throw DataValidationError.invalid("Vision: список языков OCR недоступен: \(String(reflecting: error))") }
        full.recognitionLanguages = ["en-US", "ru-RU"].filter { supported.contains($0) }
        var requests: [VNRequest] = includeScene ? [full] : []
        var modelRequest: VNCoreMLRequest?
        if let model {
            let request = VNCoreMLRequest(model: model); request.imageCropAndScaleOption = .scaleFit
            modelRequest = request; requests.append(request)
        }
        var healthRequest: VNRecognizeTextRequest?
        if let roi = hpRegion {
            let request = VNRecognizeTextRequest()
            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.regionOfInterest = CGRect(x: roi.x, y: 1 - roi.y - roi.height, width: roi.width, height: roi.height)
            healthRequest = request; requests.append(request)
        }
        var forceCPU = useCPUOnly
        #if targetEnvironment(simulator)
        forceCPU = true
        #endif
        if forceCPU {
            for request in requests {
                let supported = try request.supportedComputeStageDevices
                for (stage, devices) in supported {
                    guard let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) else { throw DataValidationError.invalid("Vision: CPU недоступен для этапа \(stage)") }
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        for request in requests {
            do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
            catch { throw DataValidationError.invalid("Vision: \(type(of: request)) завершился ошибкой: \(String(reflecting: error))") }
        }
        var text = (full.results ?? []).compactMap { $0.topCandidates(1).first }.filter { $0.confidence >= 0.50 }.prefix(60)
            .map { "\($0.string) [\(Int($0.confidence * 100))%]" }.joined(separator: " | ")
        let health = (healthRequest?.results ?? []).compactMap { observation -> HealthObservation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return HealthParser.parse(candidate.string, confidence: Double(candidate.confidence), time: time)
        }
        let labels = (modelRequest?.results ?? []).prefix(30).compactMap { item -> String? in
            if let object = item as? VNRecognizedObjectObservation, let label = object.labels.first, label.confidence >= 0.5 {
                return "\(label.identifier) [\(Int(label.confidence * 100))%] bbox=\(object.boundingBox)"
            }
            if let label = item as? VNClassificationObservation, label.confidence >= 0.5 { return "\(label.identifier) [\(Int(label.confidence * 100))%]" }
            return nil
        }
        if !labels.isEmpty { text += " | Core ML (непроверенные метки): " + labels.joined(separator: " | ") }
        if !includeScene { text = (healthRequest?.results ?? []).compactMap { $0.topCandidates(1).first }.map { "HP OCR: \($0.string) [\(Int($0.confidence * 100))%]" }.joined(separator: " | ") }
        return (text, health.count == 1 ? health[0] : nil)
    }
}
