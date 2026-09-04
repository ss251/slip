import SwiftUI

struct SlipCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility
    var padding: CGFloat = SlipSpacing.standard
    @ViewBuilder var content: Content

    var body: some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SlipColor.card, in: RoundedRectangle(cornerRadius: SlipRadius.card))
            .clipShape(RoundedRectangle(cornerRadius: SlipRadius.card))
            .overlay {
                if contrast == .increased || accessibility.increaseContrast {
                    RoundedRectangle(cornerRadius: SlipRadius.card)
                        .stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.standard)
                }
            }
            .shadow(color: SlipShadow.cardColor, radius: SlipShadow.cardRadius, y: SlipShadow.cardY)
    }
}

struct CrewArt: View {
    var size: CGFloat = SlipSize.art
    var palette: Int = 0
    var body: some View {
        ArtField(palette: palette)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size / SlipArt.cornerDivisor))
            .overlay(RoundedRectangle(cornerRadius: size / SlipArt.cornerDivisor)
                .stroke(SlipColor.secondary.opacity(SlipOpacity.subtle), lineWidth: SlipStroke.hairline))
            .accessibilityHidden(true)
    }
}

struct ArtField: View {
    var palette: Int = 0
    var body: some View {
        GeometryReader { geometry in
            let colors = palette == 1 ? [SlipColor.artMint, SlipColor.artPeach, SlipColor.artYellow]
                : palette == 2 ? [SlipColor.artPurple, SlipColor.artPink, SlipColor.artGreen]
                : [SlipColor.artPink, SlipColor.artYellow, SlipColor.artBlue]
            ZStack {
                SlipColor.background
                RadialGradient(colors: [colors[0], SlipColor.clear], center: .topLeading,
                               startRadius: SlipSpacing.zero, endRadius: geometry.size.width)
                RadialGradient(colors: [colors[1], SlipColor.clear], center: .topTrailing,
                               startRadius: SlipSpacing.zero, endRadius: geometry.size.width)
                RadialGradient(colors: [colors[2], SlipColor.clear], center: .bottom,
                               startRadius: SlipSpacing.zero, endRadius: geometry.size.width * SlipArt.radiusRatio)
            }
        }
    }
}

struct ArtBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack(alignment: .top) {
            SlipColor.background
            ArtField()
                .frame(height: SlipArt.backdropHeight)
                .opacity(colorScheme == .dark ? SlipOpacity.subtle : SlipOpacity.muted)
                .mask(LinearGradient(colors: [SlipColor.onSeal, SlipColor.clear], startPoint: .top, endPoint: .bottom))
        }.ignoresSafeArea()
    }
}

struct InitialAvatar: View {
    let name: String
    var size: CGFloat = SlipSize.avatarSmall
    var body: some View {
        Text(PreviewContent.initial(name)).font(SlipFont.headline)
            .foregroundStyle(SlipColor.ink)
            .frame(width: size, height: size)
            .background(SlipColor.fill, in: Circle())
            .accessibilityHidden(true)
    }
}

struct SealGlyph: View {
    var sealed = true
    var body: some View {
        RoundedRectangle(cornerRadius: SlipRadius.crest)
            .stroke(SlipColor.separator, style: StrokeStyle(lineWidth: SlipStroke.standard,
                    dash: sealed ? [] : SlipStroke.dashed))
            .overlay {
                if sealed { Circle().fill(SlipColor.seal).frame(width: SlipSize.smallIcon, height: SlipSize.smallIcon) }
            }
            .frame(width: SlipSize.sealMark, height: SlipSize.sealMarkLarge)
            .accessibilityLabel(sealed ? "Sealed" : "Waiting")
    }
}

enum PillTone { case ink, secondary, seal, white }

struct PillButton: View {
    let title: String
    var tone: PillTone = .ink
    var icon: String? = nil
    var action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility
    private var foreground: Color { tone == .ink ? SlipColor.background : tone == .seal ? SlipColor.onSeal : SlipColor.ink }
    private var background: Color { switch tone {
        case .ink: SlipColor.ink
        case .secondary: SlipColor.fill
        case .seal: SlipColor.seal
        case .white: SlipColor.onSeal
    } }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SlipSpacing.small) {
                if let icon { Image(systemName: icon) }
                Text(title).multilineTextAlignment(.center)
            }
            .font(SlipFont.headline).foregroundStyle(foreground)
            .padding(.horizontal, SlipSpacing.screen).padding(.vertical, SlipSpacing.standard)
            .frame(maxWidth: .infinity, minHeight: SlipSize.buttonHeight)
            .background(background, in: Capsule())
            .overlay { if contrast == .increased || accessibility.increaseContrast { Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis) } }
            .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}

struct RoundButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(SlipFont.title2)
                .frame(width: SlipSize.minimumTap, height: SlipSize.minimumTap)
                .foregroundStyle(SlipColor.ink).background(SlipColor.fill, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.small) {
            if let subtitle { Text(subtitle).font(SlipFont.footnoteBold).foregroundStyle(SlipColor.secondary) }
            Text(title).font(SlipFont.large).foregroundStyle(SlipColor.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SheetHeading: View {
    let title: String
    var light = false
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: SlipSpacing.medium) {
            Capsule().fill((light ? SlipColor.onSeal : SlipColor.secondary).opacity(SlipOpacity.muted))
                .frame(width: SlipSize.grabberWidth, height: SlipSize.grabberHeight)
            Text(title).font(SlipFont.headline).foregroundStyle(light ? SlipColor.onSeal : SlipColor.ink)
        }.frame(maxWidth: .infinity).padding(.top, SlipSpacing.small)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: SlipSpacing.screen).onEnded { value in
                if value.translation.height > SlipSpacing.hero { model.back() }
            })
            .accessibilityAction(named: "Dismiss") { model.back() }
    }
}

struct ContextRow: View {
    var detail = "Saturday crew · 3 of 5 sealed"
    var light = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: SlipSpacing.medium) {
            if !typeSize.isAccessibilitySize { CrewArt(size: SlipSize.artSmall) }
            VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                Text(model.sampleQuestion).font(SlipFont.headline)
                Text(detail).font(SlipFont.footnote).foregroundStyle(light ? SlipColor.onTicket : SlipColor.secondary)
            }
        }.foregroundStyle(light ? SlipColor.onSeal : SlipColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MemberRow: View {
    let name: String
    var detail: String? = nil
    var value: String? = nil
    var score: String? = nil
    var sealed: Bool? = nil
    var winner = false
    var struck = false
    var body: some View {
        HStack(spacing: SlipSpacing.medium) {
            InitialAvatar(name: name)
            VStack(alignment: .leading, spacing: SlipSpacing.micro) {
                Text(name).font(name == "You" ? SlipFont.headline : SlipFont.body)
                if let detail { Text(detail).font(SlipFont.caption).foregroundStyle(SlipColor.secondary) }
            }
            Spacer(minLength: SlipSpacing.small)
            if let value {
                Text(value).font(SlipFont.bodyBold).strikethrough(struck)
                    .foregroundStyle(struck ? SlipColor.secondary : SlipColor.ink)
            }
            if let sealed { SealGlyph(sealed: sealed) }
            if let score {
                Text(score).font(SlipFont.bodyBold).foregroundStyle(winner ? SlipColor.win : SlipColor.secondary)
                    .frame(minWidth: SlipSize.minimumTap, alignment: .trailing)
            }
        }.foregroundStyle(SlipColor.ink)
            .padding(.horizontal, SlipSpacing.standard)
            .padding(.vertical, SlipSpacing.medium)
            .frame(minHeight: SlipSize.rosterRowHeight)
    }
}

struct InsetDivider: View {
    var inset: CGFloat = SlipSize.avatarSmall + SlipSpacing.standard + SlipSpacing.medium
    var body: some View { Rectangle().fill(SlipColor.separator).frame(height: SlipStroke.hairline).padding(.leading, inset) }
}

struct StatusChip: View {
    let text: String
    var symbol = "clock"
    var body: some View {
        Label(text, systemImage: symbol).font(SlipFont.subheadlineBold)
            .foregroundStyle(SlipColor.ink).padding(.horizontal, SlipSpacing.standard)
            .padding(.vertical, SlipSpacing.medium).background(SlipColor.fill, in: Capsule())
    }
}

struct BottomActions<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: SlipSpacing.medium) { content }
            .padding(.horizontal, SlipSpacing.screen).padding(.top, SlipSpacing.standard)
            .padding(.bottom, SlipSpacing.standard)
    }
}

enum SlipArt {
    static let cornerDivisor: CGFloat = 4
    static let radiusRatio: CGFloat = 0.8
    static let backdropHeight: CGFloat = 360
}
