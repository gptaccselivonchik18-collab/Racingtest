import Foundation

public struct LiveCalibration: Codable, Sendable {
    public let region: HUDRegion
    public let aspectRatio: Double
    public let barTint: [Double]?
    public init(region: HUDRegion, aspectRatio: Double, barTint: [Double]? = nil) { self.region = region; self.aspectRatio = aspectRatio; self.barTint = barTint }
    public func matches(width: Int, height: Int) -> Bool {
        guard region.isValid, aspectRatio.isFinite, aspectRatio > 1, width > height, height > 0 else { return false }
        return abs(Double(width) / Double(height) - aspectRatio) / aspectRatio < 0.03
    }
}

// Calibrated visual sensor, not a trained hero detector. RGBA pixels are sampled only inside the user-selected bar.
public enum HealthBarSensor {
    private static func color(_ pixels: [UInt8], _ index: Int) -> [Double]? {
        let rgb = (0..<3).map { Double(pixels[index + $0]) / 255 }
        let high = rgb.max() ?? 0, low = rgb.min() ?? 0
        guard high > 0.15, high - low > 0.15 else { return nil }
        let sum = rgb.reduce(0, +)
        return rgb.map { $0 / sum }
    }
    public static func learnTint(rgba: [UInt8], width: Int, height: Int) -> [Double]? {
        guard width >= 20, height >= 3, width <= 1024, height <= 128, rgba.count == width * height * 4 else { return nil }
        var colors: [[Double]] = []
        for y in 0..<height { for x in 0..<max(1, width / 5) { if let value = color(rgba, (y * width + x) * 4) { colors.append(value) } } }
        guard colors.count >= height * max(1, width / 5) * 7 / 10 else { return nil }
        let tint = (0..<3).map { channel in colors.map { $0[channel] }.reduce(0, +) / Double(colors.count) }
        guard observe(rgba: rgba, width: width, height: height, tint: tint, time: 0)?.fraction ?? 0 >= 0.9 else { return nil }
        return tint
    }
    public static func observe(rgba: [UInt8], width: Int, height: Int, tint: [Double], time: Double) -> HealthObservation? {
        guard width >= 20, height >= 3, width <= 1024, height <= 128, rgba.count == width * height * 4,
              tint.count == 3, tint.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }), abs(tint.reduce(0, +) - 1) < 0.02 else { return nil }
        let filled = (0..<width).map { x -> Bool in
            var matched = 0
            for y in 0..<height {
                guard let value = color(rgba, (y * width + x) * 4) else { continue }
                let distance = (0..<3).map { pow(value[$0] - tint[$0], 2) }.reduce(0, +)
                if distance < 0.018 { matched += 1 }
            }
            return Double(matched) / Double(height) >= 0.6
        }
        guard filled.prefix(3).filter({ $0 }).count >= 2 else { return nil }
        var edge = width, gap = 0
        for x in 0..<width {
            gap = filled[x] ? 0 : gap + 1
            if gap >= 3 { edge = x - 2; break }
        }
        guard edge >= 2 else { return nil }
        let fillPurity = Double(filled.prefix(edge).filter({ $0 }).count) / Double(edge)
        let trailing = filled.dropFirst(min(width, edge + 3)).filter({ $0 }).count
        guard fillPurity >= 0.9, trailing <= max(2, width / 50) else { return nil }
        return HealthObservation(fraction: Double(edge) / Double(width), confidence: 0.9, time: time)
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
