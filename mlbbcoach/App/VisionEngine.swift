import Foundation
import Vision
import CoreGraphics
#if SWIFT_PACKAGE
import CoachCore
#endif

public enum VisionEngine {
    public static func recognize(_ image: CGImage, at time: Double, hpRegion: HUDRegion?, model: VNCoreMLModel? = nil) throws -> (text: String, health: HealthObservation?) {
        let full = VNRecognizeTextRequest()
        full.recognitionLevel = .accurate; full.usesLanguageCorrection = false
        let supported = try full.supportedRecognitionLanguages()
        full.recognitionLanguages = ["en-US", "ru-RU"].filter { supported.contains($0) }
        var requests: [VNRequest] = [full]
        var modelRequest: VNCoreMLRequest?
        if let model {
            let request = VNCoreMLRequest(model: model); request.imageCropAndScaleOption = .scaleFit
            modelRequest = request; requests.append(request)
        }
        var healthRequest: VNRecognizeTextRequest?
        if let roi = hpRegion {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.regionOfInterest = CGRect(x: roi.x, y: 1 - roi.y - roi.height, width: roi.width, height: roi.height)
            healthRequest = request; requests.append(request)
        }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform(requests)
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
        return (text, health.count == 1 ? health[0] : nil)
    }
}
