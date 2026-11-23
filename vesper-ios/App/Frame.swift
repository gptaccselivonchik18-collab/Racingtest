import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

struct Frame: Sendable {
    let width: Int
    let height: Int
    let pixels: Data

    var image: CGImage? {
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    func signatures(in board: CGRect) -> [[Int]]? {
        guard board.width >= 96, board.height >= 96,
              abs(board.width / board.height - 1) < 0.08,
              CGRect(x: 0, y: 0, width: width, height: height).contains(board) else { return nil }

        return pixels.withUnsafeBytes { raw -> [[Int]]? in
            let bytes = raw.bindMemory(to: UInt8.self)
            let w = board.width / 8
            let h = board.height / 8
            var result: [[Int]] = []
            var cornersByColor: [[Int]] = [[], []]
            for row in 0..<8 {
                for column in 0..<8 {
                    func pixel(_ u: CGFloat, _ v: CGFloat) -> Int {
                        let x = Int(board.minX + (CGFloat(column) + u) * w)
                        let y = Int(board.minY + (CGFloat(row) + v) * h)
                        let offset = 4 * (y * width + x)
                        return (Int(bytes[offset]) * 3 + Int(bytes[offset + 1]) * 6 + Int(bytes[offset + 2])) / 10
                    }
                    let corners = [pixel(0.12, 0.12), pixel(0.88, 0.12),
                                   pixel(0.12, 0.88), pixel(0.88, 0.88)].sorted()
                    let background = (corners[1] + corners[2]) / 2
                    cornersByColor[(row + column) % 2].append(background)
                    var signature: [Int] = []
                    for y in 0..<12 {
                        for x in 0..<12 {
                            let value = pixel(0.16 + CGFloat(x) * 0.68 / 11,
                                              0.16 + CGFloat(y) * 0.68 / 11)
                            signature.append(abs(value - background) < 20 ? 0 : (value < 120 ? 1 : 2))
                        }
                    }
                    result.append(signature)
                }
            }
            let background = cornersByColor.map { $0.sorted()[16] }
            guard abs(background[0] - background[1]) >= 14,
                  cornersByColor.enumerated().allSatisfy({ color, values in
                      values.filter { abs($0 - background[color]) > 25 }.count <= 4
                  }) else { return nil }
            return result
        }
    }
}

final class FrameConverter {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func convert(_ buffer: CVPixelBuffer) -> Frame? {
        let input = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 800 / max(input.extent.width, input.extent.height))
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = context.createCGImage(scaled, from: scaled.extent.integral) else { return nil }
        let width = image.width, height = image.height
        var pixels = Data(count: width * height * 4)
        let success = pixels.withUnsafeMutableBytes { buffer in
            guard let bitmap = CGContext(data: buffer.baseAddress, width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? Frame(width: width, height: height, pixels: pixels) : nil
    }
}
