import SwiftUI

struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    let firstRun: Bool
    @State private var selection: HomeFeedSelection = .upcoming

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.section) {
                header

                if firstRun {
                    emptyState
                } else {
                    feed
                }
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, SlipSpacing.large)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier(firstRun ? "home-first-run" : "home")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: SlipSpacing.medium) {
            Text("Slips")
                .font(SlipFont.large)
                .foregroundStyle(SlipColor.ink)
            Spacer(minLength: SlipSpacing.standard)
            RoundButton(symbol: "plus", label: "New slip") {
                model.go(.newSlip)
            }
            Button {
                model.go(.you)
            } label: {
                Text("S")
                    .font(SlipFont.headline)
                    .foregroundStyle(SlipColor.ink)
                    .frame(width: SlipSize.minimumTap, height: SlipSize.minimumTap)
                    .background(SlipColor.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your profile")
        }
    }

    @ViewBuilder private var feed: some View {
        HomeFeedPicker(selection: $selection)

        if selection == .upcoming {
            HomeHeroCard {
                model.go(.seal)
            }

            VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                HomeDayHeading(day: "Today", state: "Wednesday")
                HomeCompactSlipRow(
                    question: "Does the demo survive the all-hands?",
                    detail: "Opens 17:00 · Office pool",
                    palette: HomeMetrics.officePalette,
                    state: .sealed
                ) {
                    model.go(.room)
                }
            }
        }

        VStack(alignment: .leading, spacing: SlipSpacing.medium) {
            HomeDayHeading(day: "Tuesday", state: "Settled")
            HomeCompactSlipRow(
                question: "Will Raj actually ship this week?",
                detail: "He didn’t · 4 of 5 called it",
                palette: HomeMetrics.settledPalette,
                state: .score("+1")
            ) {
                model.go(.verdict)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: SlipSpacing.large) {
            Spacer(minLength: typeSize.isAccessibilitySize ? SlipSpacing.large : SlipSpacing.stage)

            EmptyPickStack()
                .padding(.bottom, SlipSpacing.large)

            Text("No slips yet")
                .font(SlipFont.title2)
                .foregroundStyle(SlipColor.ink)

            Text("Ask your crew something. Everyone seals a pick, then you open together.")
                .font(SlipFont.body)
                .foregroundStyle(SlipColor.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: HomeMetrics.emptyCopyWidth)

            PillButton(title: "New slip") {
                model.go(.newSlip)
            }

            Button {
                model.go(.invite)
            } label: {
                Text("Have an invite link? Tap it and you’re in.")
                    .font(SlipFont.subheadline)
                    .foregroundStyle(SlipColor.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: SlipSize.minimumTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: SlipSpacing.stage)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum HomeFeedSelection: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming"
    case settled = "Settled"

    var id: String { rawValue }
}

private struct HomeFeedPicker: View {
    @Binding var selection: HomeFeedSelection
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: SlipSpacing.small) {
            ForEach(HomeFeedSelection.allCases) { item in
                Button {
                    selection = item
                } label: {
                    Text(item.rawValue)
                        .font(SlipFont.headline)
                        .foregroundStyle(selection == item ? selectedForeground : SlipColor.secondary)
                        .padding(.horizontal, SlipSpacing.screen)
                        .frame(minHeight: SlipSize.segmentHeight)
                        .background(selection == item ? selectedBackground : SlipColor.fill, in: Capsule())
                        .overlay {
                            if contrast == .increased {
                                Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.standard)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
    }

    private var selectedBackground: Color { SlipColor.ink }

    private var selectedForeground: Color { SlipColor.background }
}

private struct HomeHeroCard: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    var body: some View {
        SlipCard(padding: SlipSpacing.zero) {
            VStack(alignment: .leading, spacing: SlipSpacing.zero) {
                ArtField()
                    .frame(height: SlipSize.heroBannerHeight)
                    .overlay(alignment: .topLeading) {
                        Label("Seal by Fri 20:00", systemImage: "clock")
                            .font(SlipFont.subheadlineBold)
                            .foregroundStyle(SlipColor.ticket)
                            .padding(.horizontal, SlipSpacing.standard)
                            .padding(.vertical, SlipSpacing.medium)
                            .background(SlipColor.onSeal, in: Capsule())
                            .padding(SlipSpacing.medium)
                    }

                VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                    Text(model.sampleQuestion)
                        .font(SlipFont.title2)
                        .foregroundStyle(SlipColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("Saturday crew · Ana, Raj + 1 sealed", systemImage: "person.2")
                        .font(SlipFont.subheadline)
                        .foregroundStyle(SlipColor.secondary)

                    PillButton(title: "Seal your pick", tone: .seal, action: action)
                }
                .padding(SlipSpacing.standard)
            }
            .clipShape(RoundedRectangle(cornerRadius: SlipRadius.card))
        }
    }
}

private struct HomeDayHeading: View {
    let day: String
    let state: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SlipSpacing.small) {
            Text(day).font(SlipFont.title2).foregroundStyle(SlipColor.ink)
            Text(state).font(SlipFont.title3).foregroundStyle(SlipColor.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum HomeRowState {
    case sealed
    case score(String)
}

private struct HomeCompactSlipRow: View {
    let question: String
    let detail: String
    let palette: Int
    let state: HomeRowState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SlipCard {
                HStack(spacing: SlipSpacing.medium) {
                    CrewArt(size: SlipSize.art, palette: palette)
                    VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                        Text(question)
                            .font(SlipFont.headline)
                            .foregroundStyle(SlipColor.ink)
                            .multilineTextAlignment(.leading)
                        Text(detail)
                            .font(SlipFont.subheadline)
                            .foregroundStyle(SlipColor.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: SlipSpacing.small)
                    switch state {
                    case .sealed:
                        SealGlyph()
                    case .score(let score):
                        Text(score)
                            .font(SlipFont.title3Bold)
                            .foregroundStyle(SlipColor.win)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SlipRadius.card))
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyPickStack: View {
    var body: some View {
        ZStack {
            pickSheet
                .rotationEffect(.degrees(HomeMetrics.rearRotation))
                .offset(y: SlipSpacing.medium)
            pickSheet
                .rotationEffect(.degrees(HomeMetrics.middleRotation))
                .offset(y: SlipSpacing.small)
            VStack(spacing: SlipSpacing.medium) {
                Text("Your pick")
                    .font(SlipFont.subheadlineBold)
                    .foregroundStyle(SlipColor.secondary)
                Circle()
                    .fill(SlipColor.seal)
                    .frame(width: SlipSize.sealDisc, height: SlipSize.sealDisc)
            }
            .frame(width: HomeMetrics.emptyCardWidth, height: HomeMetrics.emptyCardHeight)
            .background(SlipColor.card, in: RoundedRectangle(cornerRadius: SlipRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: SlipRadius.card)
                    .stroke(SlipColor.separator, lineWidth: SlipStroke.hairline)
            }
        }
        .frame(height: HomeMetrics.emptyStackHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your private pick, ready to be sealed")
    }

    private var pickSheet: some View {
        RoundedRectangle(cornerRadius: SlipRadius.card)
            .fill(SlipColor.card)
            .frame(width: HomeMetrics.emptyCardWidth, height: HomeMetrics.emptyCardHeight)
            .overlay {
                RoundedRectangle(cornerRadius: SlipRadius.card)
                    .stroke(SlipColor.separator, lineWidth: SlipStroke.hairline)
            }
            .shadow(color: SlipShadow.cardColor, radius: SlipShadow.cardRadius, y: SlipShadow.cardY)
    }
}

struct HowItWorksScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                Button {
                    model.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(SlipFont.title3Bold)
                        .foregroundStyle(SlipColor.ink)
                        .frame(width: SlipSize.minimumTap, height: SlipSize.minimumTap)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: SlipSpacing.small) {
                    Text("How Slip works")
                        .font(SlipFont.large)
                        .foregroundStyle(SlipColor.ink)
                    Text("One question, a few friends, zero peeking.")
                        .font(SlipFont.body)
                        .foregroundStyle(SlipColor.secondary)
                }

                if typeSize.isAccessibilitySize {
                    VStack(spacing: SlipSpacing.standard) {
                        steps
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: SlipSpacing.medium) {
                            steps
                        }
                        .padding(.vertical, SlipSpacing.small)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, SlipSpacing.small)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("how-slip-works")
    }

    @ViewBuilder private var steps: some View {
        ForEach(HowStepContent.steps) { step in
            HowStepCard(step: step, fillWidth: typeSize.isAccessibilitySize)
        }
    }
}

private struct HowStepCard: View {
    let step: HowStepContent
    let fillWidth: Bool

    var body: some View {
        SlipCard {
            VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                Text(step.number)
                    .font(SlipFont.caption)
                    .foregroundStyle(SlipColor.secondary)
                HowStepMark(mark: step.mark)
                    .frame(height: SlipSize.sealDisc)
                Spacer(minLength: SlipSpacing.small)
                Text(step.title)
                    .font(SlipFont.headline)
                    .foregroundStyle(SlipColor.ink)
                Text(step.body)
                    .font(SlipFont.subheadline)
                    .foregroundStyle(SlipColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: HomeMetrics.stepCardHeight, alignment: .topLeading)
        }
        .frame(maxWidth: fillWidth ? .infinity : HomeMetrics.stepCardWidth)
    }
}

private struct HowStepMark: View {
    let mark: HowStepMarkKind

    var body: some View {
        switch mark {
        case .pick:
            Text("Yes").font(SlipFont.title2).foregroundStyle(SlipColor.ink)
        case .seal:
            Circle().fill(SlipColor.seal).frame(width: SlipSize.sealMark, height: SlipSize.sealMark)
        case .roster:
            HStack(spacing: SlipSpacing.tiny) {
                ForEach(HowStepContent.rosterStates.indices, id: \.self) { index in
                    SealGlyph(sealed: HowStepContent.rosterStates[index])
                        .scaleEffect(HomeMetrics.miniGlyphScale)
                        .frame(width: SlipSize.largeIcon, height: SlipSize.minimumTap)
                }
            }
        case .open:
            Text("Yes  Yes  No  Yes  No")
                .font(SlipFont.subheadlineBold)
                .foregroundStyle(SlipColor.ink)
                .lineLimit(HomeMetrics.singleLine)
                .minimumScaleFactor(HomeMetrics.markMinimumScale)
        case .score:
            Text("+1").font(SlipFont.title2).foregroundStyle(SlipColor.win)
        }
    }
}

private enum HowStepMarkKind: Sendable {
    case pick, seal, roster, open, score
}

private struct HowStepContent: Identifiable, Sendable {
    let number: String
    let mark: HowStepMarkKind
    let title: String
    let body: String

    var id: String { number }

    static let rosterStates = [true, true, true, false, false]
    static let steps = [
        HowStepContent(number: "1", mark: .pick, title: "Pick in private", body: "You choose on your own iPhone. The pick never uploads."),
        HowStepContent(number: "2", mark: .seal, title: "Seal it", body: "Your phone proves the pick without showing it. Only the proof leaves."),
        HowStepContent(number: "3", mark: .roster, title: "Wait together", body: "Everyone sees who has sealed, never what. Nudge the stragglers."),
        HowStepContent(number: "4", mark: .open, title: "Open together", body: "At the deadline every pick opens at once, each checked against its seal."),
        HowStepContent(number: "5", mark: .score, title: "Keep score", body: "The steward calls what happened. Winners take a point, losers take the banter.")
    ]
}

private enum HomeMetrics {
    static let officePalette = 1
    static let settledPalette = 0
    static let emptyCopyWidth: CGFloat = 320
    static let emptyCardWidth: CGFloat = 144
    static let emptyCardHeight: CGFloat = 112
    static let emptyStackHeight: CGFloat = 136
    static let rearRotation = 5.0
    static let middleRotation = -3.0
    static let stepCardWidth: CGFloat = 224
    static let stepCardHeight: CGFloat = 250
    static let miniGlyphScale: CGFloat = 0.58
    static let markMinimumScale: CGFloat = 0.72
    static let singleLine = 1
}
