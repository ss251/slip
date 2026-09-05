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
        _flow = State(initialValue: selectedFixture?.makeFlow(round: appModel.localRound) ?? SealFlowModel())
        #else
        _flow = State(initialValue: SealFlowModel())
        #endif
        _model = State(initialValue: appModel)
        appearance = selectedAppearance
        typeSize = selectedType
        reduceMotion = motion
        reduceTransparency = transparency
        increaseContrast = contrast
    }

    var body: some Scene {
        WindowGroup {
            SlipRootView(model: model, flow: flow)
                .preferredColorScheme(model.screen.usesDarkCanvas ? .dark : appearance)
                #if DEBUG
                .modifier(DebugLocalFixtureLaunch(fixture: localFixture, model: model, flow: flow))
                #endif
                .modifier(DebugAccessibility(typeSize: typeSize, reduceMotion: reduceMotion,
                                             reduceTransparency: reduceTransparency, increaseContrast: increaseContrast))
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
