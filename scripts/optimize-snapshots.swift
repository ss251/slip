import Foundation
import CoreGraphics
import ImageIO

// Lossless post-record compression. Compare decoded pixels before replacing a PNG.
// Run from the repo root with: swift scripts/optimize-snapshots.swift
enum CompressionError: Error { case tool, image, pixelsChanged(String), tooLarge(Int) }
let files = FileManager.default
let root = URL(fileURLWithPath: files.currentDirectoryPath)
let snapshots = root.appendingPathComponent("SlipTests/Snapshots")
let scratch = files.temporaryDirectory.appendingPathComponent("slip-png-\(UUID().uuidString)")
try files.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? files.removeItem(at: scratch) }

func run(_ executable: String, _ arguments: [String], capture: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = capture ? pipe : FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    let output = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CompressionError.tool }
    return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
let developer = try run("/usr/bin/xcode-select", ["-p"], capture: true)
let pngcrush = developer + "/Platforms/iPhoneOS.platform/Developer/usr/bin/pngcrush"

func pixels(_ url: URL) throws -> Data {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CompressionError.image }
    var data = Data(count: image.width * image.height * 4)
    try data.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CompressionError.image
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return data
}

var before = 0
var after = 0
let pngs = try files.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
for original in pngs {
    let compressed = scratch.appendingPathComponent(original.lastPathComponent)
    // Recompression invalidates Apple's IDAT-offset hint; preserve other metadata.
    _ = try run(pngcrush, ["-q", "-save", "-rem", "iDOT", "-m", "0", original.path, compressed.path])
    guard try pixels(original) == pixels(compressed) else {
        throw CompressionError.pixelsChanged(original.lastPathComponent)
    }
    let originalData = try Data(contentsOf: original)
    let compressedData = try Data(contentsOf: compressed)
    before += originalData.count
    if compressedData.count < originalData.count { try compressedData.write(to: original, options: .atomic) }
    after += min(originalData.count, compressedData.count)
}
print("snapshot compression: PASS (\(pngs.count) pixel-identical PNGs; \(before) -> \(after) bytes)")
guard after < 15_000_000 else { throw CompressionError.tooLarge(after) }
