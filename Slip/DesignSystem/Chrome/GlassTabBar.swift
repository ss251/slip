import SwiftUI

struct GlassTabBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        chrome
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : SlipChrome.maximumWidth)
            .overlay { if contrast == .increased || accessibility.increaseContrast { Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis) } }
            .shadow(color: SlipShadow.cardColor, radius: SlipShadow.floatingRadius, y: SlipShadow.floatingY)
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.bottom, SlipChrome.bottomClearance)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var chrome: some View {
        if reduceTransparency || accessibility.reduceTransparency {
            tabs.background(SlipColor.card, in: Capsule())
        } else if #available(iOS 26.0, *) {
            tabs.glassEffect(.regular, in: Capsule())
        } else {
            tabs.background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var tabs: some View {
        HStack(spacing: SlipSpacing.zero) {
            tab(.home, title: "Slips", symbol: "house")
            tab(.crews, title: "Crews", symbol: "person.2")
            tab(.you, title: "You", symbol: "person")
        }.padding(.horizontal, SlipSpacing.small).padding(.vertical, SlipSpacing.small)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tab(_ screen: SlipScreen, title: String, symbol: String) -> some View {
        let selected = model.screen == screen || (screen == .home && model.screen == .firstRun)
        return Button { model.tab(screen) } label: {
            VStack(spacing: SlipSpacing.tiny) {
                Image(systemName: symbol).font(SlipFont.title3)
                Text(title).font(SlipFont.tab)
            }.frame(maxWidth: .infinity, minHeight: SlipSize.minimumTap)
                .foregroundStyle(selected ? SlipColor.ink : SlipColor.secondary)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
