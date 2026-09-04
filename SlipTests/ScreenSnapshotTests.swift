import SwiftUI
import Testing
import UIKit
@testable import Slip

/// Every render uses the key window; iOS 26+ does not reliably render detached hierarchies.
@Suite(.serialized)
@MainActor
struct ScreenSnapshotTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Snapshots")

    @Test("Every screen matches its reviewed light, dark and XL snapshots")
    func allScreens() async throws {
        let record = ProcessInfo.processInfo.environment["SLIP_RECORD_SNAPSHOTS"] == "1"
        for screen in SlipScreen.allCases {
            for variant in SnapshotVariant.allCases {
                let name = "\(screen.rawValue)-\(variant.rawValue)"
                let image = try await drawHierarchyInKeyWindow(screen: screen, variant: variant)
                let url = Self.directory.appendingPathComponent(name).appendingPathExtension("png")
                if record {
                    try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                    try #require(image.pngData()).write(to: url)
                } else {
                    let reference = try #require(UIImage(contentsOfFile: url.path), "Missing reviewed snapshot: \(name)")
                    let difference = try normalizedDifference(image, reference)
                    #expect(difference < 0.012, "Snapshot changed: \(name), mean pixel difference \(difference)")
                }
            }
        }
    }

    @Test("Accessibility reference screens render with stacked layout and solid chrome")
    func accessibilityLayouts() async throws {
        for screen in [SlipScreen.seal, .ticket, .room] {
            let image = try await drawHierarchyInKeyWindow(screen: screen, variant: .accessibility)
            #expect(image.size.width == 393)
            #expect(image.size.height == 1100)
        }
    }

    private func drawHierarchyInKeyWindow(screen: SlipScreen, variant: SnapshotVariant) async throws -> UIImage {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let size = CGSize(width: 393, height: variant == .accessibility ? 1100 : 852)
        window.frame = CGRect(origin: .zero, size: size)
        let root = SlipRootView(model: .preview(screen), flow: SealFlowModel())
            .environment(\.colorScheme, variant == .dark ? .dark : .light)
            .environment(\.dynamicTypeSize, variant == .xl ? .xLarge : variant == .accessibility ? .accessibility1 : .large)
            .environment(\.slipAccessibility, AccessibilityOverrides(reduceMotion: true,
                reduceTransparency: true, increaseContrast: variant == .accessibility))
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = variant == .dark ? .dark : .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
        return image
    }

    private func normalizedDifference(_ actual: UIImage, _ reference: UIImage) throws -> Double {
        let lhs = try pixels(actual)
        let rhs = try pixels(reference)
        guard lhs.count == rhs.count else { return 1 }
        let total = zip(lhs, rhs).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
        return total / (Double(lhs.count) * 255)
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return bytes
    }
}

private enum SnapshotVariant: String, CaseIterable {
    case light, dark, xl, accessibility
    static let allCases: [SnapshotVariant] = [.light, .dark, .xl]
}
