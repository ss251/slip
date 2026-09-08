import MidnightKit
import SwiftUI

@main
struct SlipApp: App {
    @State private var model: AppModel
    @State private var flow: SealFlowModel
    private let appearance: ColorScheme?
    private let typeSize: DynamicTypeSize?
    private let reduceMotion: Bool
    private let reduceTransparency: Bool
    private let increaseContrast: Bool
    #if DEBUG
    private let localFixture: LocalRoundPreviewFixture?
    private let exportPublicProof: Bool
    #endif

    init() {
        let appModel = AppModel()
        var selectedAppearance: ColorScheme?
        var selectedType: DynamicTypeSize?
        var motion = false, transparency = false, contrast = false
        #if DEBUG
        var selectedFixture: LocalRoundPreviewFixture?
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let name = value("--screen"), let screen = SlipScreen(rawValue: name) {
            appModel.screen = screen
            appModel.isPreview = arguments.contains("--preview")
        }
        /// DEBUG: `--slip-local-fixture <state>` seeds a labelled synthetic local
        /// result for simulator screenshots. `--screen` still selects its route;
        /// `--preview` takes precedence. No private value is accepted from flags.
        if !arguments.contains("--preview"),
           let name = value("--slip-local-fixture"),
           let fixture = LocalRoundPreviewFixture(rawValue: name) {
            selectedFixture = fixture
            fixture.configure(appModel)
            if value("--screen").flatMap(SlipScreen.init(rawValue:)) == nil {
                appModel.screen = fixture.defaultScreen
            }
        }
        if let theme = value("--appearance") { selectedAppearance = theme == "dark" ? .dark : .light }
        if arguments.contains("--accessibility") { selectedType = .accessibility1 }
        if arguments.contains("--accessibility-max") { selectedType = .accessibility5 }
        if arguments.contains("--xl") { selectedType = .xLarge }
        motion = arguments.contains("--reduce-motion")
        transparency = arguments.contains("--reduce-transparency")
        contrast = arguments.contains("--contrast")
        localFixture = selectedFixture
        exportPublicProof = arguments.contains("--export-public-proof")
        let setup = NetworkSetup.fromLaunchArguments(arguments) ?? NetworkSetup.load()
        let tracker = NetworkSealTracker(relayHost: setup?.relayURL.host ?? (arguments.contains("--network-preview") ? "steward.local" : nil))
        if arguments.contains("--network-preview") {
            // Synthetic, clearly-fake receipt so the network ticket is reachable via simctl.
            tracker.record(NetworkSealReceipt(commitment: Data(repeating: 0xe8, count: 32), txID: "0x" + String(repeating: "5f", count: 32), submitPending: false,
                                              executeDuration: .milliseconds(9), assembleDuration: .milliseconds(1641), transactionBytes: 5238),
                           for: appModel.localRound.id)
            tracker.record(.confirmed, for: appModel.localRound.id)
            tracker.memberIDHex = String(repeating: "9d2c", count: 16)
        }
        _networkTracker = State(initialValue: tracker)
        _flow = State(initialValue: selectedFixture?.makeFlow(round: appModel.localRound) ?? NetworkSealAdapter.makeFlow(setup: setup, tracker: tracker))
        if arguments.contains("--print-member-id") {
            // Headless enrolment aid: the PUBLIC member id only (memberIdOf(secret)), on stdout.
            Task { @MainActor in
                for _ in 0..<200 where tracker.memberIDHex == nil { try? await Task.sleep(for: .milliseconds(25)) }
                if let id = tracker.memberIDHex { print("SLIP_MEMBER_ID=\(id)") } else {
                    let secret = try? DeviceIdentity.secret()
                    if let secret, let rt = try? ContractRuntime() {
                        let id = try? rt.evaluate("(function(){ const C = __slipContract; const s = new Uint8Array([\(secret.map { String($0) }.joined(separator: ","))]); return Array.from(C.pureCircuits.memberIdOf(s)).map(b => b.toString(16).padStart(2,'0')).join(''); })()")
                        print("SLIP_MEMBER_ID=\(id ?? "unavailable")")
                    }
                }
            }
        }
        #else
        let setup = NetworkSetup.load()
        let tracker = NetworkSealTracker(relayHost: setup?.relayURL.host)
        _networkTracker = State(initialValue: tracker)
        _flow = State(initialValue: NetworkSealAdapter.makeFlow(setup: setup, tracker: tracker))
        #endif
        _model = State(initialValue: appModel)
        appearance = selectedAppearance
        typeSize = selectedType
        reduceMotion = motion
        reduceTransparency = transparency
        increaseContrast = contrast
    }

    @State private var networkTracker: NetworkSealTracker

    var body: some Scene {
        WindowGroup {
            SlipRootView(model: model, flow: flow)
                .environment(networkTracker)
                .onOpenURL { url in accept(inviteURL: url) }
                .preferredColorScheme(model.screen.usesDarkCanvas ? .dark : appearance)
                #if DEBUG
                .modifier(DebugLocalFixtureLaunch(fixture: localFixture, model: model, flow: flow))
                .modifier(DebugPublicProofExport(enabled: exportPublicProof, model: model, flow: flow))
                #endif
                .modifier(DebugAccessibility(typeSize: typeSize, reduceMotion: reduceMotion,
                                             reduceTransparency: reduceTransparency, increaseContrast: increaseContrast))
        }
    }
}


extension SlipApp {
    /// Handles `slip://join/<payload>`. Invites arrive from outside the app, so a bad
    /// one must produce a plain message rather than a broken half-joined state.
    @MainActor func accept(inviteURL url: URL) {
        do {
            let invite = try RoundInvite.decode(url: url)
            switch model.join(invite: invite) {
            case .joined, .joinedAndAdoptedNetwork:
                model.inform("Joined \(invite.crewName). Seal before the deadline.")
            case .joinedWithNetworkConflict:
                model.inform("Joined \(invite.crewName), but this iPhone is set up for a different crew contract. Check Steward relay setup before sealing.")
            }
        } catch RoundInvite.InviteError.expired {
            model.inform("That slip has already closed.")
        } catch RoundInvite.InviteError.unsupportedVersion {
            model.inform("That invite needs a newer version of Slip.")
        } catch {
            model.inform("That invite link isn't readable.")
        }
    }
}

private struct DebugAccessibility: ViewModifier {
    let typeSize: DynamicTypeSize?
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let increaseContrast: Bool
    @Environment(\.dynamicTypeSize) private var systemType

    func body(content: Content) -> some View {
        content.environment(\.dynamicTypeSize, typeSize ?? systemType)
            .environment(\.slipAccessibility, AccessibilityOverrides(reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency, increaseContrast: increaseContrast))
    }
}
