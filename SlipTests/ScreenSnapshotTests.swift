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

    @Test("Every screen matches its reviewed light, dark, XL and accessibility snapshots")
    func allScreens() async throws {
        let record = ProcessInfo.processInfo.environment["SLIP_RECORD_SNAPSHOTS"] == "1"
        let selected = Set((ProcessInfo.processInfo.environment["SLIP_SNAPSHOT_SCREENS"] ?? "")
            .split(separator: ",").map(String.init))
        if record {
            try #require(!selected.isEmpty, "Recording requires an explicit SLIP_SNAPSHOT_SCREENS allowlist")
            try #require(selected.isSubset(of: Set(SlipScreen.allCases.map(\.rawValue))), "Unknown snapshot screen")
        }
        for screen in SlipScreen.allCases {
            if record && !selected.contains(screen.rawValue) { continue }
            for variant in SnapshotVariant.allCases {
                let name = "\(screen.rawValue)-\(variant.rawValue)"
                let image = try await drawHierarchyInKeyWindow(screen: screen, variant: variant)
                let url = Self.directory.appendingPathComponent(name).appendingPathExtension("png")
                if record && selected.contains(screen.rawValue) {
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

    @Test("Machine receipts use the bundled JetBrains Mono face")
    func machineFontIsRegistered() throws {
        #expect(UIFont(name: "JetBrainsMono-Regular", size: 12) != nil)
    }

    @Test("Small white seal copy keeps AAA over every rendered crew-art palette")
    func sealCanvasContrast() async throws {
        try #require(!UIAccessibility.isReduceTransparencyEnabled,
                     "Disable Reduce Transparency in the simulator to verify the real crew-art canvas")
        // Exercise the actual non-Reduce-Transparency view, including blur and overlays.
        // Choose a public synthetic crew key for every palette, without reaching model data.
        var keysByPalette: [Int: String] = [:]
        for candidate in 0..<10000 {
            let key = "ambient-crew-\(candidate)"
            keysByPalette[SlipArt.paletteIndex(for: key)] = key
            if keysByPalette.count == SlipColor.artPalettes.count { break }
        }
        try #require(keysByPalette.count == SlipColor.artPalettes.count)
        let size = CGSize(width: 393, height: 852)
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            for palette in SlipColor.artPalettes.indices {
                let key = try #require(keysByPalette[palette])
                let root = AmbientBackground(crewID: key)
                    .environment(\.colorScheme, appearance == .dark ? .dark : .light)
                    .environment(\.slipAccessibility, AccessibilityOverrides())
                let image = try await drawHierarchyInKeyWindow(root: root, size: size, appearance: appearance)
                let range = try canvasLuminanceRange(image)
                let foreground = luminance([242.0 / 255, 242.0 / 255, 247.0 / 255])
                let ratio = (foreground + 0.05) / (range.upperBound + 0.05)
                #expect(ratio >= 7, "Rendered ambient palette \(palette), \(appearance): \(ratio):1")
                #expect(range.upperBound - range.lowerBound > 0.003,
                        "Crew art disappeared into a flat ambient surface: palette \(palette)")
                print("Rendered ambient palette \(palette), \(appearance): minimum \(ratio):1")
            }
            // The brief preserves the documented flat accessibility ground. It is AA,
            // not AAA, for the dimmer onTicket token; do not mislabel that baseline.
            let flat = AmbientBackground()
                .environment(\.colorScheme, appearance == .dark ? .dark : .light)
                .environment(\.slipAccessibility, AccessibilityOverrides(reduceTransparency: true))
            let flatImage = try await drawHierarchyInKeyWindow(root: flat, size: size, appearance: appearance)
            let flatRange = try canvasLuminanceRange(flatImage)
            let foreground = luminance([242.0 / 255, 242.0 / 255, 247.0 / 255])
            #expect((foreground + 0.05) / (flatRange.upperBound + 0.05) >= 4.5)
            #expect(flatRange.upperBound - flatRange.lowerBound < 0.001,
                    "Reduce Transparency must remove the decorative art")
        }
    }

    private func luminance(_ components: [Double]) -> Double {
        let linear = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }

    private func canvasLuminanceRange(_ image: UIImage) throws -> ClosedRange<Double> {
        let cg = try #require(image.cgImage)
        let rgba = try pixels(image)
        var minimum = Double.infinity
        var maximum = -Double.infinity
        // Measure every rendered pixel. A lookup table keeps the whole-canvas bound
        // cheap enough to check every identity in both appearances.
        let linear = (0...255).map { component -> Double in
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        for offset in stride(from: 0, to: cg.width * cg.height * 4, by: 4) {
            let value = linear[Int(rgba[offset])] * 0.2126
                + linear[Int(rgba[offset + 1])] * 0.7152
                + linear[Int(rgba[offset + 2])] * 0.0722
            minimum = min(minimum, value)
            maximum = max(maximum, value)
        }
        return minimum...maximum
    }

    private func drawHierarchyInKeyWindow(screen: SlipScreen, variant: SnapshotVariant) async throws -> UIImage {
        let isAccessibility = variant == .accessibility || variant == .accessibilityMax
        let size = CGSize(width: 393, height: isAccessibility ? 1100 : 852)
        let isAmbientScreen = [SlipScreen.seal, .sealing, .proofFailed, .alreadySealed].contains(screen)
        let reduceTransparency = isAccessibility || !isAmbientScreen
        let root = SlipRootView(model: .preview(screen), flow: SealFlowModel())
            .environment(\.colorScheme, variant == .dark ? .dark : .light)
            .environment(\.dynamicTypeSize, variant == .xl ? .xLarge : variant == .accessibility ? .accessibility1 : variant == .accessibilityMax ? .accessibility5 : .large)
            .environment(\.slipAccessibility, AccessibilityOverrides(reduceMotion: true,
                reduceTransparency: reduceTransparency, increaseContrast: isAccessibility))
        return try await drawHierarchyInKeyWindow(root: root, size: size,
                                                  appearance: variant == .dark ? .dark : .light)
    }

    private func drawHierarchyInKeyWindow<Content: View>(root: Content, size: CGSize,
                                                       appearance: UIUserInterfaceStyle) async throws -> UIImage {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = appearance
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
        let cg = try #require(image.cgImage)
        #expect(image.scale == 1)
        #expect(image.size == size)
        #expect(cg.width == Int(size.width))
        #expect(cg.height == Int(size.height))
        #expect(cg.bitsPerComponent == 8)
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
    case light, dark, xl, accessibility, accessibilityMax
    static let allCases: [SnapshotVariant] = [.light, .dark, .xl, .accessibility, .accessibilityMax]
}
