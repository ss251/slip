import SwiftUI

@main
struct SlipApp: App {
    @State private var model: AppModel
    @State private var flow = SealFlowModel()
    private let appearance: ColorScheme?
    private let typeSize: DynamicTypeSize?
    private let reduceMotion: Bool
    private let reduceTransparency: Bool
    private let increaseContrast: Bool

    init() {
        let appModel = AppModel()
        var selectedAppearance: ColorScheme?
        var selectedType: DynamicTypeSize?
        var motion = false, transparency = false, contrast = false
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let name = value("--screen"), let screen = SlipScreen(rawValue: name) {
            appModel.screen = screen
            appModel.isPreview = arguments.contains("--preview")
        }
        if let theme = value("--appearance") { selectedAppearance = theme == "dark" ? .dark : .light }
        if arguments.contains("--accessibility") { selectedType = .accessibility1 }
        if arguments.contains("--accessibility-max") { selectedType = .accessibility5 }
        if arguments.contains("--xl") { selectedType = .xLarge }
        motion = arguments.contains("--reduce-motion")
        transparency = arguments.contains("--reduce-transparency")
        contrast = arguments.contains("--contrast")
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
