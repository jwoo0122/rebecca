import CoreGraphics
import Foundation

@main
struct CaptureSupportTests {
    static func main() throws {
        var pixel = [UInt8](arrayLiteral: 32, 64, 96, 255)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            fatalError("failed to create test image")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rebecca-capture-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("frame.png").path

        try writePNGWithoutOverwriting(image, to: output)
        let firstBytes = try Data(contentsOf: URL(fileURLWithPath: output))
        precondition(firstBytes.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))

        do {
            try writePNGWithoutOverwriting(image, to: output)
            fatalError("existing output was overwritten")
        } catch CaptureSupportError.outputExists {
            // Expected no-overwrite behavior.
        }
        let afterBytes = try Data(contentsOf: URL(fileURLWithPath: output))
        precondition(afterBytes == firstBytes)
        print("CaptureSupportTests passed")
    }
}
