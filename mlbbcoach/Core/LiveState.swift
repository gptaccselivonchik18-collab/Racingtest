import Foundation

public struct LiveCalibration: Codable, Sendable {
    public let region: HUDRegion
    public let aspectRatio: Double
    public init(region: HUDRegion, aspectRatio: Double) { self.region = region; self.aspectRatio = aspectRatio }
    public func matches(width: Int, height: Int) -> Bool {
        guard region.isValid, aspectRatio.isFinite, aspectRatio > 1, width > height, height > 0 else { return false }
        return abs(Double(width) / Double(height) - aspectRatio) / aspectRatio < 0.03
    }
}

public enum LiveTiming {
    // These are local monotonic timestamps. Detection is not the moment an event happened in the game.
    public static func milliseconds(from start: Double, to end: Double) -> Double? {
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        return (end - start) * 1000
    }
    public static func isFresh(frame: Double, now: Double, maxAge: Double = 3) -> Bool {
        guard let elapsed = milliseconds(from: frame, to: now) else { return false }
        return elapsed <= maxAge * 1000
    }
    public static func interval(lowPower: Bool, seriousHeat: Bool, previousProcessing: Double, confirmedHP: Double?) -> Double {
        if lowPower || seriousHeat { return max(3, previousProcessing * 2) }
        let desired = (confirmedHP ?? 1) <= 0.35 ? 0.5 : 1.0
        return max(desired, min(5, previousProcessing * 2))
    }
}

public struct LiveDiagnosticRow: Codable, Sendable {
    public var date: Date = .now
    public var kind: String
    public var detail: String
    public var background: Bool
    public var uptime: Double
    public var eventID: UUID?
    public var detectionToSpeechMS: Double?
    public var frameToSpeechMS: Double?
    public init(kind: String, detail: String, background: Bool, uptime: Double,
                eventID: UUID? = nil, detectionToSpeechMS: Double? = nil, frameToSpeechMS: Double? = nil) {
        self.kind = kind; self.detail = detail; self.background = background; self.uptime = uptime
        self.eventID = eventID; self.detectionToSpeechMS = detectionToSpeechMS; self.frameToSpeechMS = frameToSpeechMS
    }
}
