import Testing
import CoreGraphics
import CoreText
import Foundation
import CoachCore
import CoachVision

@Test func visionReadsSyntheticHealthImage() throws {
    let context = try #require(CGContext(data: nil, width: 600, height: 220, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 600, height: 220))
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 70, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
    ]
    let text = NSAttributedString(string: "12/100", attributes: attributes)
    context.textPosition = CGPoint(x: 50, y: 80)
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
    let image = try #require(context.makeImage())
    let result: (text: String, health: HealthObservation?)
    do { result = try VisionEngine.recognize(image, at: 10, hpRegion: HUDRegion(x: 0, y: 0, width: 1, height: 1), useCPUOnly: true) }
    catch { let e = error as NSError; print("VISION FAILURE domain=\(e.domain) code=\(e.code) info=\(e.userInfo)"); throw error }
    #expect(result.text.replacingOccurrences(of: " ", with: "").contains("12/100"))
    let hp = try #require(result.health)
    #expect(abs(hp.fraction - 0.12) < 0.001)
    #expect(TacticalDecisionEngine.evaluate(health: hp, at: 10).first?.priority == 1)
}
