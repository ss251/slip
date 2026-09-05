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
    var crewID: String = PreviewContent.crew
    var body: some View {
        ArtField(crewID: crewID)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size == SlipSize.art ? SlipRadius.crest : size / SlipArt.cornerDivisor))
            .overlay(RoundedRectangle(cornerRadius: size == SlipSize.art ? SlipRadius.crest : size / SlipArt.cornerDivisor)
                .stroke(SlipColor.secondary.opacity(SlipOpacity.subtle), lineWidth: SlipStroke.hairline))
            .accessibilityHidden(true)
    }
}

struct ArtField: View {
    var crewID: String = PreviewContent.crew
    var body: some View {
        GeometryReader { geometry in
            let colors = SlipColor.artPalettes[SlipArt.paletteIndex(for: crewID)]
            ZStack {
                SlipColor.onSeal
                RadialGradient(colors: [colors[0], SlipColor.clear], center: .topLeading,
                               startRadius: SlipSpacing.zero, endRadius: geometry.size.width)
                RadialGradient(colors: [colors[1], SlipColor.clear], center: .topTrailing,
                               startRadius: SlipSpacing.zero, endRadius: geometry.size.width)
                RadialGradient(colors: [colors[2], SlipColor.clear], center: .bottom,
                               startRadius: SlipSpacing.zero, endRadius: geometry.size.height * SlipArt.radiusRatio)
            }
        }
    }
}

struct ArtBackdrop: View {
    var crewID: String = PreviewContent.crew
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack(alignment: .top) {
            SlipColor.background
            ArtField(crewID: crewID)
                .frame(height: SlipArt.backdropHeight)
                .opacity(colorScheme == .dark ? SlipOpacity.subtle : SlipOpacity.muted)
                .mask(LinearGradient(colors: [SlipColor.onSeal, SlipColor.clear], startPoint: .top, endPoint: .bottom))
        }.ignoresSafeArea()
    }
}

/// The shared who/what/when grammar keeps status attached to identity as text grows.
struct CrewIdentityLine<Status: View>: View {
    let crew: String
    var foreground: Color = SlipColor.secondary
    @ViewBuilder var status: Status
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SlipSpacing.tiny))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: SlipSpacing.small))
        layout {
            HStack(spacing: SlipSpacing.tiny) {
                CrewArt(size: SlipSize.artIdentity, crewID: crew)
                Text(crew).font(SlipFont.footnote).foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: SlipSpacing.tiny) }
            status
        }
    }
}

struct RowMetadata: View {
    let symbol: String
    let text: String
    var foreground: Color = SlipColor.secondary
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SlipSpacing.tiny) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(SlipFont.footnote).fontWeight(.regular)
        .foregroundStyle(foreground)
        .multilineTextAlignment(.leading)
    }
}

struct InitialAvatar: View {
    let name: String
    var size: CGFloat = SlipSize.avatarSmall
    var body: some View {
        Text(PreviewContent.initial(name)).font(SlipFont.avatarInitial)
            .foregroundStyle(SlipColor.ink)
            .frame(width: size, height: size)
            .background(SlipColor.fill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Status is a text annotation, never a control-shaped accessory.
struct SealStatusTag: View {
    var sealed = true
    var body: some View {
        Group {
            if sealed {
                Text("\(Image(systemName: "circle.fill")) Sealed")
                    .foregroundStyle(SlipColor.sealText)
            } else {
                Text("Waiting").foregroundStyle(SlipColor.secondary)
            }
        }
        .font(SlipFont.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(RowAccessibility.sealStatus(sealed: sealed))
    }
}

enum PillTone { case ink, secondary, seal, white }

struct PillButton: View {
    let title: String
    var tone: PillTone = .ink
    var icon: String? = nil
    var compact = false
    var fillsWidth = true
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
            .padding(.horizontal, fillsWidth ? SlipSpacing.screen : SlipSpacing.large)
            .padding(.vertical, SlipSpacing.medium)
            .frame(maxWidth: fillsWidth ? .infinity : nil,
                   minHeight: fillsWidth ? (compact ? SlipSize.compactButtonHeight : SlipSize.buttonHeight) : SlipSize.minimumTap)
            .background(background, in: Capsule())
            .overlay { if contrast == .increased || accessibility.increaseContrast { Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis) } }
            .contentShape(Capsule())
        }.buttonStyle(SlipPressStyle())
    }
}

struct RoundButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(SlipFont.chromeIcon)
                .frame(width: SlipSize.minimumTap, height: SlipSize.minimumTap)
                .foregroundStyle(SlipColor.ink).background(SlipColor.fill, in: Circle())
        }.buttonStyle(SlipPressStyle()).accessibilityLabel(label)
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
    var sealIndicator = false
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: SlipSpacing.medium) {
            Capsule().fill((light ? SlipColor.onSeal : SlipColor.secondary).opacity(SlipOpacity.muted))
                .frame(width: SlipSize.grabberWidth, height: SlipSize.grabberHeight)
            HStack(spacing: SlipSpacing.small) {
                if sealIndicator { Circle().fill(SlipColor.seal).frame(width: SlipSize.sealDot, height: SlipSize.sealDot).accessibilityHidden(true) }
                Text(title).font(SlipFont.headline).foregroundStyle(light ? SlipColor.onSeal : SlipColor.ink)
            }
        }.frame(maxWidth: .infinity).padding(.top, SlipSpacing.small)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: SlipSpacing.screen).onEnded { value in
                if value.translation.height > SlipSpacing.hero { model.back() }
            })
            .accessibilityAction(named: "Dismiss") { model.back() }
    }
}

/// Keeps a cancel control and centered form title separate as text grows.
struct FormHeading: View {
    let title: String
    var cancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SlipSpacing.small) {
                    cancelButton
                    heading.frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                ZStack {
                    heading
                    HStack { cancelButton; Spacer(minLength: SlipSpacing.zero) }
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private var heading: some View {
        Text(title).font(SlipFont.headline).foregroundStyle(SlipColor.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cancelButton: some View {
        Button("Cancel", action: cancel).font(SlipFont.body)
            .foregroundStyle(SlipColor.secondary).frame(minHeight: SlipSize.minimumTap)
    }
}

struct ContextRow: View {
    var detail = "3 of 5 sealed"
    var light = false
    var crewID: String = PreviewContent.crew
    var symbol = "person.2"
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
            CrewIdentityLine(crew: crewID, foreground: light ? SlipColor.onTicket : SlipColor.secondary) {
                EmptyView()
            }
            Text(model.sampleQuestion).font(SlipFont.headline).fixedSize(horizontal: false, vertical: true)
            RowMetadata(symbol: symbol, text: detail, foreground: light ? SlipColor.onTicket : SlipColor.secondary)
        }.foregroundStyle(light ? SlipColor.onSeal : SlipColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RowAccessibility.slip(question: model.sampleQuestion, crew: crewID, metadata: detail))
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
                Text(name).font(name == "You" ? SlipFont.headline : SlipFont.body).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(SlipFont.caption).foregroundStyle(SlipColor.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: SlipSpacing.small)
            if let value {
                Text(value).font(SlipFont.bodyBold).strikethrough(struck)
                    .foregroundStyle(struck ? SlipColor.secondary : SlipColor.ink)
            }
            if let sealed { SealStatusTag(sealed: sealed) }
            if let score {
                Text(score).font(SlipFont.bodyBold).foregroundStyle(winner ? SlipColor.win : SlipColor.secondary)
                    .frame(minWidth: SlipSize.minimumTap, alignment: .trailing)
            }
        }.foregroundStyle(SlipColor.ink)
            .padding(.horizontal, SlipSpacing.standard)
            .padding(.vertical, SlipSpacing.medium)
            .frame(minHeight: SlipSize.rosterRowHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RowAccessibility.member(name: name, detail: detail, value: value, score: score, sealed: sealed))
    }
}

struct InsetDivider: View {
    var inset: CGFloat = SlipSize.avatarSmall + SlipSpacing.standard + SlipSpacing.medium
    var body: some View { Rectangle().fill(SlipColor.separator).frame(height: SlipStroke.hairline).padding(.leading, inset) }
}

struct StatusChip: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility
    let text: String
    var symbol = "clock"
    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }.font(SlipFont.subheadlineBold)
            .foregroundStyle(SlipColor.ink).padding(.horizontal, SlipSpacing.standard)
            .padding(.vertical, SlipSpacing.medium).background(SlipColor.fill, in: Capsule())
            .overlay { if contrast == .increased || accessibility.increaseContrast {
                Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.standard)
            } }
    }
}

struct SlipPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.slipAccessibility) private var accessibility

    func makeBody(configuration: Configuration) -> some View {
        let motionReduced = reduceMotion || accessibility.reduceMotion
        configuration.label
            .scaleEffect(configuration.isPressed && !motionReduced ? SlipMotion.pressScale : SlipOpacity.opaque)
            .opacity(configuration.isPressed && motionReduced ? SlipOpacity.strong : SlipOpacity.opaque)
            .animation(.easeOut(duration: SlipMotion.pressDuration), value: configuration.isPressed)
    }
}

struct BottomActions<Content: View>: View {
    var background: Color = SlipColor.background
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: SlipSpacing.medium) { content }
            .padding(.horizontal, SlipSpacing.screen).padding(.top, SlipSpacing.standard)
            .padding(.bottom, SlipSpacing.standard)
            .background(background.ignoresSafeArea(edges: .bottom))
    }
}

enum SlipArt {
    // The current local UI has public crew names, not persisted crew IDs. Hash those
    // exact UTF-8 keys with wrapping arithmetic so identity survives every launch.
    static func identityHash(for crewID: String) -> UInt64 {
        crewID.utf8.reduce(UInt64(5381)) { hash, byte in
            (hash &* 33) &+ UInt64(byte)
        }
    }

    static func paletteIndex(for crewID: String) -> Int {
        Int(identityHash(for: crewID) % UInt64(SlipColor.artPalettes.count))
    }

    static let cornerDivisor: CGFloat = 4
    static let radiusRatio: CGFloat = 0.8
    static let backdropHeight: CGFloat = 360
}

enum SlipDateText {
    static func weekdayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "EEEE HH:mm"
        return formatter.string(from: date)
    }
}

/// A pressed wax seal — Slip's mark. A scalloped rim, a soft sheen and a debossed inner
/// ring read as physically sealed wax, never a flat disc (which, red-on-light, reads as a
/// national flag). Seal-red stays the one accent; this only changes the SHAPE of the mark.
struct Scallop: Shape {
    var lobes: Int = 16
    var amplitude: CGFloat = 0.04   // fraction of radius
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2 * (1 - amplitude)
        var path = Path()
        let steps = 240
        for i in 0...steps {
            let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let r = base * (1 + amplitude * cos(CGFloat(lobes) * a))
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

struct SealMark: View {
    var size: CGFloat
    var body: some View {
        Scallop()
            .fill(SlipColor.seal)
            .overlay(
                RadialGradient(colors: [SlipColor.onSeal.opacity(SlipOpacity.subtle), SlipColor.clear],
                               center: .init(x: 0.36, y: 0.30), startRadius: 0, endRadius: size * 0.7)
                    .clipShape(Scallop())
            )
            .overlay(   // debossed inner ring: dark groove + a light upper lip
                Circle().inset(by: size * 0.18)
                    .strokeBorder(SlipColor.sealDeep.opacity(SlipOpacity.strong), lineWidth: max(1, size * 0.045))
            )
            .overlay(
                Circle().inset(by: size * 0.18).offset(y: -max(0.5, size * 0.012))
                    .strokeBorder(SlipColor.onSeal.opacity(SlipOpacity.subtle), lineWidth: max(0.5, size * 0.02))
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
