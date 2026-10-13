import Testing
import CoreGraphics
import CoreText
import Foundation
import AVFoundation
import CoreVideo
import CoachCore
import CoachVision

private func makeHealthImage() throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 600, height: 220, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 600, height: 220))
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 70, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
    ]
    let text = NSAttributedString(string: "12/100", attributes: attributes)
    context.textPosition = CGPoint(x: 50, y: 80)
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
    return try #require(context.makeImage())
}

@Test func visionReadsSyntheticHealthImage() throws {
    let image = try makeHealthImage()
    let result: (text: String, health: HealthObservation?)
    do { result = try VisionEngine.recognize(image, at: 10, hpRegion: HUDRegion(x: 0, y: 0, width: 1, height: 1), useCPUOnly: true) }
    catch { let e = error as NSError; print("VISION FAILURE domain=\(e.domain) code=\(e.code) info=\(e.userInfo)"); throw error }
    #expect(result.text.replacingOccurrences(of: " ", with: "").contains("12/100"))
    let hp = try #require(result.health)
    #expect(abs(hp.fraction - 0.12) < 0.001)
    #expect(TacticalDecisionEngine.evaluate(health: hp, at: 10).first?.priority == 1)
}

@Test func liveCPURegionPathConfirmsTwoFramesWithoutSceneOCR() throws {
    let image = try makeHealthImage()
    var tracker = GameStateTracker()
    for time in [10.0, 11.0] {
        let result = try VisionEngine.recognize(image, at: time, hpRegion: HUDRegion(x: 0, y: 0, width: 1, height: 1), useCPUOnly: true, includeScene: false)
        let hp = try #require(result.health)
        let confirmed = tracker.observe(hp, at: time + 0.1)
        if time == 10 { #expect(confirmed == nil) }
        else { #expect(TacticalDecisionEngine.evaluate(health: confirmed, at: time + 0.1).first?.key == "critical-hp") }
    }
}

@Test func liveBarSensorReadsPixelsFromActualCGImage() throws {
    let context = try #require(CGContext(data: nil, width: 400, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.08, green: 0.82, blue: 0.12, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 400, height: 40))
    let region = HUDRegion(x: 0, y: 0, width: 1, height: 1)
    let full = try #require(context.makeImage())
    let fullPixels = try #require(VisionEngine.barPixels(full, region: region))
    let tint = try #require(HealthBarSensor.learnTint(rgba: fullPixels, width: 200, height: 5))
    context.setFillColor(CGColor(gray: 0.1, alpha: 1)); context.fill(CGRect(x: 80, y: 0, width: 320, height: 40))
    let low = try #require(context.makeImage())
    let pixels = try #require(VisionEngine.barPixels(low, region: region))
    let hp = try #require(HealthBarSensor.observe(rgba: pixels, width: 200, height: 5, tint: tint, time: 10))
    #expect(abs(hp.fraction - 0.2) < 0.02)
}

@Test func encodedMatchVideoDecodesIntoRecognizableFrame() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 600, AVVideoHeightKey: 220])
    let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 600, kCVPixelBufferHeightKey as String: 220, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
    writer.add(input)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    var pixel: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 600, 220, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixel) == kCVReturnSuccess)
    let buffer = try #require(pixel)
    CVPixelBufferLockBaseAddress(buffer, [])
    let canvas = try #require(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 600, height: 220, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))
    canvas.draw(try makeHealthImage(), in: CGRect(x: 0, y: 0, width: 600, height: 220))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    for time in 0..<3 {
        let deadline = Date.now.addingTimeInterval(5)
        while !input.isReadyForMoreMediaData {
            guard Date.now < deadline else { throw DataValidationError.invalid("Video writer timeout: \(String(describing: writer.error))") }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(adaptor.append(buffer, withPresentationTime: CMTime(seconds: Double(time), preferredTimescale: 600)))
    }
    input.markAsFinished(); await writer.finishWriting()
    #expect(writer.status == .completed)
    let asset = AVURLAsset(url: url)
    #expect(try await asset.load(.duration).seconds > 1)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
    let evidence = try VisionEngine.recognize(frame.image, at: frame.actualTime.seconds, hpRegion: HUDRegion(x: 0, y: 0, width: 1, height: 1), useCPUOnly: true)
    #expect(abs((try #require(evidence.health)).fraction - 0.12) < 0.001)
}
