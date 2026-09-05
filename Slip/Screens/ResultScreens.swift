import SwiftUI
import UIKit

enum OpeningMode: Equatable, Sendable {
    case opening
    case awaiting
    case mismatch
}

struct RevealVisualState: Equatable, Sendable {
    let opacity: Double
    let rotationDegrees: Double
}

enum RevealMotionPlan {
    static let maximumStaggeredRows = 5
    static let noBounce: Double = 0
    static let hiddenOpacity: Double = 0
    static let restingAngle: Double = 0
    static let hiddenAngle: Double = -90
    static let axisX: CGFloat = 1
    static let axisY: CGFloat = 0
    static let axisZ: CGFloat = 0
    static let perspective: CGFloat = 0.72

    static func delay(forRowAt index: Int) -> TimeInterval {
        let nonnegativeIndex = max(index, 0)
        let cappedIndex = min(nonnegativeIndex, maximumStaggeredRows - 1)
        return TimeInterval(cappedIndex) * SlipMotion.revealStagger
    }

    static func visualState(isRevealed: Bool, reduceMotion: Bool) -> RevealVisualState {
        RevealVisualState(
            opacity: isRevealed ? SlipOpacity.opaque : hiddenOpacity,
            rotationDegrees: isRevealed || reduceMotion ? restingAngle : hiddenAngle
        )
    }

    static func completedRows(
        afterCancelling revealedRows: Set<Int>,
        participatingIndices: [Int]
    ) -> Set<Int> {
        revealedRows.union(participatingIndices)
    }
}

struct SealedRoomScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(SealFlowModel.self) private var flow

    var body: some View {
        if model.isPreview {
            previewBody
        } else {
            LocalResultScreen(destination: .room)
        }
    }

    private var previewBody: some View {
        ScrollView {
            VStack(spacing: SlipSpacing.large) {
                HStack {
                    ResultIconButton(symbol: "chevron.left", label: "Back", action: model.back)
                    Spacer()
                }

                VStack(spacing: SlipSpacing.large) {
                    CrewArt(size: SlipSize.artLarge)

                    VStack(spacing: SlipSpacing.medium) {
                        Text(displayedQuestion)
                            .font(SlipFont.title2)
                            .foregroundStyle(SlipColor.ink)
                            .multilineTextAlignment(.center)
                        Text(roomStatus)
                            .font(SlipFont.body)
                            .foregroundStyle(SlipColor.secondary)
                    }

                    countdownChip
                }
                .frame(maxWidth: .infinity)

                ResultRosterCard(rows: rows)
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .background { ArtBackdrop() }
        .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
            BottomActions {
                if model.isPreview {
                    PillButton(title: "Nudge Maya & Tomás", tone: .secondary) {
                        model.inform("This preview did not send a nudge to Maya or Tomás.")
                    }
                    Text("Everyone opens together at Friday 21:00.")
                        .font(SlipFont.footnote)
                        .foregroundStyle(SlipColor.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    PillButton(title: "Shared nudges unavailable", tone: .secondary) {
                        model.inform("No nudge was sent. This local build has no connected crew.")
                    }
                    Text("Opening schedule is unavailable in this local build.")
                        .font(SlipFont.footnote)
                        .foregroundStyle(SlipColor.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var currentSealedDisplay: LocalSealedDisplay? {
        guard
            let display = flow.sealedDisplay,
            let receipt = flow.receipt,
            display.roundID == model.localRound.id,
            receipt.roundID == model.localRound.id
        else { return nil }
        return display
    }

    private var displayedQuestion: String {
        model.isPreview ? PreviewContent.question : model.localRound.question
    }

    private var roomStatus: String {
        model.isPreview ? "Saturday crew · 3 of 5 sealed" : "\(model.localRound.crewName) · local-only roster"
    }

    private var rows: [ResultRosterItem] {
        if model.isPreview {
            return [
                ResultRosterItem(name: "You", value: "Yes", valueDetail: "only you can see this"),
                ResultRosterItem(name: "Ana", value: "Sealed", sealed: true, valueSecondary: true),
                ResultRosterItem(name: "Raj", value: "Sealed", sealed: true, valueSecondary: true),
                ResultRosterItem(name: "Maya", value: "Waiting", sealed: false, valueSecondary: true),
                ResultRosterItem(name: "Tomás", value: "Waiting", sealed: false, valueSecondary: true)
            ]
        }

        let ownRow = currentSealedDisplay.map {
            ResultRosterItem(name: "You", value: $0.selectedSide, valueDetail: "only you can see this")
        } ?? ResultRosterItem(name: "You", detail: "No completed proof for this slip")

        return [
            ownRow,
            ResultRosterItem(name: "Crew", detail: "Not connected in this local build")
        ]
    }

    private var countdownText: String {
        model.isPreview ? "Opens in 14h 22m" : "Opening schedule unavailable"
    }

    @ViewBuilder private var countdownChip: some View {
#if DEBUG
        ResultStatusChip(text: countdownText)
            .contextMenu {
                Button("Preview opening") { model.go(.opening) }
            }
            .accessibilityHint("Touch and hold to preview opening locally")
#else
        ResultStatusChip(text: countdownText)
#endif
    }
}

struct OpeningScreen: View {
    @Environment(AppModel.self) private var model
    let mode: OpeningMode

    var body: some View {
        if model.isPreview {
            previewBody
        } else {
            LocalResultScreen(destination: mode == .mismatch ? .mismatch : .opening)
        }
    }

    private var previewBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                openingHeader
                if !model.isPreview { FixtureDisclosure() }
                openingStatusChip

                ResultRosterCard(
                    rows: rows,
                    usesCompactRows: mode != .opening,
                    revealsOnAppear: mode == .opening
                )

                ResultVerification(
                    headline: verificationHeadline,
                    detail: verificationDetail,
                    emphasized: true
                )

                if mode == .awaiting {
                    stewardCard
                } else if mode == .mismatch {
                    mismatchCard
                }
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, ResultLayout.shellTopPadding)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .background { ArtBackdrop() }
        .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
            BottomActions {
                if mode == .mismatch {
                    Text("Ana calls it once Saturday’s over.")
                        .font(SlipFont.footnote)
                        .foregroundStyle(SlipColor.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SlipSpacing.tiny)
                }
                PillButton(title: actionTitle, tone: .secondary) {
                    model.inform(actionNotice)
                }
                if mode == .opening {
                    Text("If Raj doesn’t open in time, his pick stays sealed and scores nothing.")
                        .font(SlipFont.footnote)
                        .foregroundStyle(SlipColor.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var headerSubtitle: String {
        mode == .opening ? "SATURDAY CREW · OPENING" : "SATURDAY CREW · OPENED"
    }

    private var openingHeader: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.small) {
            Text(headerSubtitle)
                .font(SlipFont.footnoteBold)
                .foregroundStyle(SlipColor.secondary)
            Text(PreviewContent.question)
                .font(SlipFont.title2)
                .foregroundStyle(SlipColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        mode == .opening ? "4 of 5 opened" : "Everyone opened"
    }

    @ViewBuilder private var openingStatusChip: some View {
#if DEBUG
        ResultStatusChip(text: statusText, symbol: "circle.fill")
            .contextMenu {
                if mode == .opening {
                    Button("Preview everyone opened") { model.go(.awaiting) }
                } else {
                    Button("Preview call sheet") { model.go(.settle) }
                }
            }
            .accessibilityHint("Touch and hold for the next local preview state")
#else
        ResultStatusChip(text: statusText, symbol: "circle.fill")
#endif
    }

    private var rows: [ResultRosterItem] {
        switch mode {
        case .opening:
            return [
                ResultRosterItem(name: "You", value: "Yes"),
                ResultRosterItem(name: "Ana", value: "Yes"),
                ResultRosterItem(name: "Maya", value: "Yes"),
                ResultRosterItem(name: "Tomás", value: "No"),
                ResultRosterItem(name: "Raj", detail: "Hasn’t opened · 1h 40m left", sealed: true)
            ]
        case .awaiting:
            return [
                ResultRosterItem(name: "You", value: "Yes"),
                ResultRosterItem(name: "Ana", value: "Yes"),
                ResultRosterItem(name: "Maya", value: "Yes"),
                ResultRosterItem(name: "Raj", value: "No"),
                ResultRosterItem(name: "Tomás", value: "No")
            ]
        case .mismatch:
            return [
                ResultRosterItem(name: "You", value: "Yes"),
                ResultRosterItem(name: "Ana", value: "Yes"),
                ResultRosterItem(name: "Maya", value: "Yes"),
                ResultRosterItem(name: "Raj", detail: "Reveal didn’t match the seal", score: "—"),
                ResultRosterItem(name: "Tomás", value: "No")
            ]
        }
    }

    private var verificationHeadline: String {
        switch mode {
        case .opening: "4 of 5 opened. Every one matched its seal."
        case .awaiting: "5 of 5 opened. Every one matched its seal."
        case .mismatch: "4 of 5 matched their seals."
        }
    }

    private var verificationDetail: String? {
        mode == .opening ? "Ana calls it once Saturday’s over." : nil
    }

    private var actionTitle: String {
        mode == .opening ? "Remind Raj" : "Nudge Ana"
    }

    private var actionNotice: String {
        mode == .opening
            ? "This preview did not send Raj a reminder."
            : "This preview did not send Ana a nudge."
    }

    private var stewardCard: some View {
        SlipCard {
            HStack(alignment: .top, spacing: SlipSpacing.medium) {
                InitialAvatar(name: "Ana")
                VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                    Text("Ana calls it").font(SlipFont.headline)
                    Text("Once Saturday’s over. Nobody scores until she does.")
                        .font(SlipFont.footnote)
                        .foregroundStyle(SlipColor.secondary)
                }
            }
            .foregroundStyle(SlipColor.ink)
            .accessibilityElement(children: .combine)
        }
    }

    private var mismatchCard: some View {
        SlipCard {
            VStack(alignment: .leading, spacing: SlipSpacing.small) {
                Text("About Raj’s pick").font(SlipFont.headline)
                Text("A pick only counts if what’s opened is exactly what was sealed. Raj’s wasn’t, so his pick sits this round out. Nobody else is affected, and nothing about anyone’s pick was ever visible early.")
                    .font(SlipFont.body)
                    .foregroundStyle(SlipColor.secondary)
            }
            .foregroundStyle(SlipColor.ink)
        }
    }
}

struct VerdictScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let satOut: Bool

    var body: some View {
        if model.isPreview {
            previewBody
        } else {
            LocalResultScreen(destination: .verdict)
        }
    }

    private var previewBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ResultLayout.compactSectionSpacing) {
                verdictHeader.padding(.bottom, SlipSpacing.medium)
                if !model.isPreview { FixtureDisclosure() }
                VerdictBars(satOut: satOut)
                winnerCard
                ResultRosterCard(rows: resultRows, usesCompactRows: true, showsVerdict: true)

                if satOut {
                    ResultVerification(
                        headline: "4 of 4 opened, every reveal matched its seal.",
                        detail: "Tomás didn’t seal before the lock, so he’s not in this one."
                    )
                } else {
                    ResultVerification(headline: "5 of 5 opened, every reveal matched its seal.")
                    provenance
                    ResultCommentRow(name: "Raj", text: "Raj: a drizzle is not rain.") {
                        model.inform("Replies are preview-only right now.")
                    }
                }
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, ResultLayout.shellTopPadding)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .background { ArtBackdrop() }
        .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
            BottomActions {
                PillButton(title: "Share the reveal", tone: .secondary) {
                    model.inform("Sharing is not connected in this preview.")
                }
            }
        }
    }

    @ViewBuilder private var verdictHeader: some View {
#if DEBUG
        ScreenHeader(title: "It rained.", subtitle: "SATURDAY CREW · ANA CALLED IT")
            .contextMenu {
                Button("Preview standings") { model.go(.standings) }
            }
            .accessibilityHint("Touch and hold to preview standings locally")
#else
        ScreenHeader(title: "It rained.", subtitle: "SATURDAY CREW · ANA CALLED IT")
#endif
    }

    private var winnerCard: some View {
        SlipCard {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: SlipSpacing.medium) {
                        InitialAvatar(name: "You")
                        VStack(alignment: .leading, spacing: SlipSpacing.small) {
                            winnerCopy
                            winnerScore
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(spacing: SlipSpacing.medium) {
                        InitialAvatar(name: "You")
                        winnerCopy
                        Spacer(minLength: SlipSpacing.small)
                        winnerScore
                    }
                }
            }
            .foregroundStyle(SlipColor.ink)
            .accessibilityElement(children: .combine)
        }
    }

    private var winnerCopy: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.micro) {
            Text("You called it").font(SlipFont.headline)
            RowMetadata(symbol: "clock", text: "Sealed Yes on Tuesday")
        }
    }

    private var winnerScore: some View {
        Text("+1")
            .font(SlipFont.title2)
            .foregroundStyle(SlipColor.win)
    }

    private var resultRows: [ResultRosterItem] {
        if satOut {
            return [
                ResultRosterItem(name: "Ana", value: "Yes", score: "+1", winner: true),
                ResultRosterItem(name: "Maya", value: "Yes", score: "+1", winner: true),
                ResultRosterItem(name: "Raj", value: "No", score: "0", struck: true),
                ResultRosterItem(name: "Tomás", detail: "Sat this one out", value: "—", score: "—")
            ]
        }
        return [
            ResultRosterItem(name: "Ana", value: "Yes", score: "+1", winner: true),
            ResultRosterItem(name: "Maya", value: "Yes", score: "+1", winner: true),
            ResultRosterItem(name: "Raj", value: "No", score: "0", struck: true),
            ResultRosterItem(name: "Tomás", value: "No", score: "0", struck: true)
        ]
    }

    private var provenance: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SlipSpacing.small) {
                RowMetadata(symbol: "person", text: "Called by Ana")
                RowMetadata(symbol: "clock", text: "Saturday 18:04")
                challengeButton
            }
            VStack(alignment: .leading, spacing: SlipSpacing.small) {
                RowMetadata(symbol: "person", text: "Called by Ana")
                RowMetadata(symbol: "clock", text: "Saturday 18:04")
                challengeButton
            }
        }
        .font(SlipFont.footnote)
    }

    private var challengeButton: some View {
        Button("Challenge") { model.go(.challenge) }
            .font(SlipFont.footnoteBold)
            .foregroundStyle(SlipColor.ink)
            .frame(minHeight: SlipSize.minimumTap)
            .buttonStyle(.plain)
    }
}

struct StandingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility
    @State private var period: StandingsPeriod = .week

    var body: some View {
        if model.isPreview {
            previewBody
        } else {
            LocalResultScreen(destination: .standings)
        }
    }

    private var previewBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ResultLayout.compactSectionSpacing) {
                ScreenHeader(title: "Standings", subtitle: "SATURDAY CREW")
                    .padding(.bottom, SlipSpacing.small)
                if !model.isPreview { FixtureDisclosure() }
                periodPicker
                standingsHero
                rankingCard
                Text("Season 1 · 6 slips · 30 proofs checked, 30 matched")
                    .font(SlipFont.footnote)
                    .foregroundStyle(SlipColor.secondary)
                    .padding(.horizontal, SlipSpacing.tiny)
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, ResultLayout.shellTopPadding)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
            BottomActions {
                PillButton(title: "New slip") { model.go(.newSlip) }
            }
        }
    }

    private var periodPicker: some View {
        HStack(spacing: SlipSpacing.tiny) {
            periodButton(.week, title: "This week")
            periodButton(.season, title: "Season")
        }
        .padding(.horizontal, SlipSpacing.tiny)
        .background(SlipColor.fill, in: Capsule())
        .overlay {
            if contrast == .increased || accessibility.increaseContrast {
                Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.standard)
            }
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : ResultLayout.segmentWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Standings period")
    }

    private func periodButton(_ value: StandingsPeriod, title: String) -> some View {
        Button {
            period = value
        } label: {
            Text(title)
                .font(SlipFont.headline)
                .foregroundStyle(period == value ? SlipColor.background : SlipColor.secondary)
                .frame(maxWidth: .infinity, minHeight: SlipSize.segmentHeight)
                .background(period == value ? SlipColor.ink : SlipColor.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(period == value ? .isSelected : [])
    }

    private var standingsHero: some View {
        SlipCard(padding: SlipSpacing.zero) {
            VStack(spacing: SlipSpacing.zero) {
                ZStack(alignment: .topTrailing) {
                    ArtField()
                        .frame(height: ResultLayout.leaderArtHeight)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: SlipRadius.card,
                            bottomLeadingRadius: SlipSpacing.zero,
                            bottomTrailingRadius: SlipSpacing.zero,
                            topTrailingRadius: SlipRadius.card
                        ))

                    ResultBadge(
                        title: period == .week ? "Week 4 leader" : "Season leader",
                        symbol: "crown"
                    )
                        .padding(SlipSpacing.medium)
                }

                leaderSummary
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var leaderSummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                InitialAvatar(name: "Ana", size: SlipSize.avatarLarge)
                leaderCopy
                Text(period == .week ? "12" : "64").font(SlipFont.large)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SlipSpacing.screen)
        } else {
            HStack(spacing: SlipSpacing.standard) {
                InitialAvatar(name: "Ana", size: SlipSize.avatarLarge)
                    .offset(y: ResultLayout.leaderAvatarLift)
                leaderCopy
                Spacer(minLength: SlipSpacing.small)
                Text(period == .week ? "12" : "64").font(SlipFont.large)
            }
            .padding(.horizontal, SlipSpacing.screen)
        }
    }

    private var leaderCopy: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.micro) {
            Text(period == .week ? "Ana takes the week" : "Ana leads the season")
                .font(SlipFont.headline)
            Text(period == .week ? "4 of 4 called · first to seal" : "18 of 28 called")
                .font(SlipFont.footnote)
                .foregroundStyle(SlipColor.secondary)
        }
        .foregroundStyle(SlipColor.ink)
    }

    private var rankingCard: some View {
        let rankings = [
            RankingItem(rank: "2", name: "You", score: "10"),
            RankingItem(rank: "3", name: "Raj", score: "7"),
            RankingItem(rank: "4", name: "Maya", score: "6"),
            RankingItem(rank: "5", name: "Tomás", score: "4")
        ]
        return SlipCard(padding: SlipSpacing.zero) {
            VStack(spacing: SlipSpacing.zero) {
                ForEach(rankings.indices, id: \.self) { index in
                    RankingRow(item: rankings[index])
                    if index != rankings.indices.last { InsetDivider() }
                }
            }
        }
    }
}

struct SettleScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var outcome: CallOutcome = .rained

    var body: some View {
        if model.isPreview {
            previewBody
        } else {
            LocalResultScreen(destination: .settle)
        }
    }

    private var previewBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                SheetHeading(title: "Call it")
                if !model.isPreview { FixtureDisclosure() }
                ContextRow(detail: "5 of 5 opened · your call")
                Text("What happened?")
                    .font(SlipFont.large)
                    .foregroundStyle(SlipColor.ink)

                outcomeChoices

                Text(outcome.summary)
                    .font(SlipFont.body)
                    .foregroundStyle(SlipColor.secondary)
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
            BottomActions {
                PillButton(title: outcome.actionTitle, action: showPreviewVerdict)
                Text("Anyone who sealed can challenge within 24 hours. A challenge voids the round.")
                    .font(SlipFont.footnote)
                    .foregroundStyle(SlipColor.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder private var outcomeChoices: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: SlipSpacing.medium) { choiceButtons }
        } else {
            HStack(spacing: SlipSpacing.medium) { choiceButtons }
        }
    }

    @ViewBuilder private var choiceButtons: some View {
        CallChoiceButton(outcome: .rained, selection: $outcome)
        CallChoiceButton(outcome: .dry, selection: $outcome)
    }

    private func showPreviewVerdict() {
        model.go(.verdict)
        model.inform("Preview only. No call was submitted; the result shown is a sample, not a shared round.")
    }
}

struct ChallengeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var reason = ""

    var body: some View {
        if model.isPreview {
            previewBody
        } else {
            LocalResultScreen(destination: .challenge)
        }
    }

    private var previewBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                SheetHeading(title: "Challenge")
                if !model.isPreview { FixtureDisclosure() }

                VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                    Text("Challenge Ana’s call?")
                        .font(SlipFont.large)
                        .foregroundStyle(SlipColor.ink)
                    Text("Ana called it: it rained. If you challenge, the round is voided for everyone. Nobody scores.")
                        .font(SlipFont.body)
                        .foregroundStyle(SlipColor.secondary)
                }

                challengeIdentityCard
                ChallengeReasonField(text: $reason)
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
            BottomActions {
                PillButton(title: "Challenge and void the round", action: showPreviewVoided)
                Button("Keep Ana’s call", action: model.back)
                    .font(SlipFont.headline)
                    .foregroundStyle(SlipColor.secondary)
                    .frame(maxWidth: .infinity, minHeight: SlipSize.minimumTap)
                    .buttonStyle(.plain)
            }
        }
    }

    private func showPreviewVoided() {
        model.go(.voided)
        model.inform("Preview only. No challenge was submitted and no shared round was voided.")
    }

    private var challengeIdentityCard: some View {
        SlipCard {
            VStack(spacing: SlipSpacing.standard) {
                HStack(alignment: .top, spacing: SlipSpacing.medium) {
                    InitialAvatar(name: "You")
                    VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                        Text("Challenged by you").font(SlipFont.headline)
                        Text("Your name stays on this for the whole crew to see.")
                            .font(SlipFont.footnote)
                            .foregroundStyle(SlipColor.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(SlipColor.separator).frame(height: SlipStroke.hairline)

                HStack {
                    Text("Until").foregroundStyle(SlipColor.secondary)
                    Spacer()
                    Text("Sunday 18:04").font(SlipFont.headline)
                }
                .font(SlipFont.body)
            }
            .foregroundStyle(SlipColor.ink)
        }
    }
}

struct VoidedScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let rows = [
        ResultRosterItem(name: "You", value: "Yes", score: "—"),
        ResultRosterItem(name: "Ana", value: "Yes", score: "—"),
        ResultRosterItem(name: "Maya", value: "Yes", score: "—"),
        ResultRosterItem(name: "Raj", value: "No", score: "—"),
        ResultRosterItem(name: "Tomás", value: "No", score: "—")
    ]

    var body: some View {
        if model.isPreview {
            previewBody
        } else {
            LocalResultScreen(destination: .voided)
        }
    }

    private var previewBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.screen) {
                ScreenHeader(title: "No result.", subtitle: "SATURDAY CREW · VOIDED")
                if !model.isPreview { FixtureDisclosure() }
                challengeSummary
                ResultRosterCard(rows: rows, usesCompactRows: true)
                ResultVerification(
                    headline: "5 of 5 opened, every reveal matched its seal.",
                    detail: "A challenge voids the round. Nobody scores. The next slip starts clean."
                )
                ResultCommentRow(name: "Ana", text: "Ana: it was raining, Raj.") {
                    model.inform("Replies are preview-only right now.")
                }
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, ResultLayout.shellTopPadding)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .background { ArtBackdrop() }
        .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
            BottomActions {
                PillButton(title: "New slip") { model.go(.newSlip) }
            }
        }
    }

    private var challengeSummary: some View {
        SlipCard {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                        ChallengerAvatars()
                        challengeSummaryCopy
                    }
                } else {
                HStack(alignment: .top, spacing: SlipSpacing.standard) {
                    ChallengerAvatars()
                    challengeSummaryCopy
                }
                }
            }
        }
    }

    private var challengeSummaryCopy: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
            Text("Raj challenged Ana’s call").font(SlipFont.headline)
            Text("Ana said it rained · Raj: “a drizzle is not rain”")
                .font(SlipFont.footnote)
                .foregroundStyle(SlipColor.secondary)
            RowMetadata(symbol: "clock", text: "Sunday 09:12")
        }
        .foregroundStyle(SlipColor.ink)
    }
}

// MARK: - Proved local results

private enum LocalResultDestination: Equatable {
    case room, opening, mismatch, verdict, standings, settle, challenge, voided
}

/// Only the current round's accepted public result drives this presentation. The
/// opening action takes an identity, never a freshly selected private pick.
private struct LocalResultScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(SealFlowModel.self) private var flow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let destination: LocalResultDestination
    @State private var selectedOutcome: UInt8 = 1
    @State private var pendingStage: LocalRoundStage?
    @State private var pendingRoundID: UUID?

    private var result: LocalRoundResult? {
        guard let result = flow.roundResult, result.roundID == model.localRound.id else { return nil }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                HStack {
                    ResultIconButton(symbol: "chevron.left", label: "Back", action: model.back)
                    Spacer()
                }
                ScreenHeader(title: title, subtitle: model.localRound.crewName.uppercased())
                ResultStatusChip(text: "On-device sample · no shared round", symbol: "iphone")

                if let result {
                    localContent(result)
                    if let failure = flow.roundFailure, destination != .mismatch {
                        failureCard(failure)
                    }
                    if flow.isRoundBusy {
                        HStack(spacing: SlipSpacing.medium) {
                            ProgressView().tint(SlipColor.ink)
                            Text("Making this step’s proof…")
                                .font(SlipFont.body)
                                .foregroundStyle(SlipColor.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    LocalProofTimings(steps: result.steps)
                } else {
                    unavailableCard
                }
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, ResultLayout.shellTopPadding)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .background { ArtBackdrop(crewID: model.localRound.crewName) }
        .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
            BottomActions {
                actions
            }
        }
        .onChange(of: flow.roundResult) { _, accepted in
            guard
                let accepted,
                let pendingRoundID,
                pendingRoundID == model.localRound.id,
                accepted.roundID == pendingRoundID,
                accepted.stage == pendingStage
            else { return }
            pendingStage = nil
            self.pendingRoundID = nil
            switch accepted.stage {
            case .sealed: break
            case .revealed: model.go(.opening)
            case .settled: model.go(.verdict)
            case .disputed: model.go(.voided)
            }
        }
        .onChange(of: flow.roundFailure) { _, failure in
            guard failure != nil, pendingRoundID == model.localRound.id else { return }
            pendingStage = nil
            pendingRoundID = nil
            if failure == .revealMismatch { model.go(.mismatch) }
        }
        .onDisappear {
            flow.depart(roundID: pendingRoundID ?? model.localRound.id)
            pendingStage = nil
            pendingRoundID = nil
        }
    }

    private var title: String {
        switch destination {
        case .room: model.localRound.question
        case .opening:
            if let result, result.revealedChoice != nil { "Your pick opened." } else { "Ready to open?" }
        case .mismatch:
            flow.roundFailure == .revealMismatch ? "That reveal didn’t match." : "Opening check"
        case .verdict:
            result?.stage == .settled ? "The call is in." : "No result."
        case .standings: "Local standings"
        case .settle: "What happened?"
        case .challenge: "Challenge the call?"
        case .voided: "No result."
        }
    }

    @ViewBuilder private func localContent(_ result: LocalRoundResult) -> some View {
        if destination != .room {
            Text(result.round.question)
                .font(SlipFont.title2)
                .foregroundStyle(SlipColor.ink)
        }

        switch destination {
        case .room:
            ResultRosterCard(rows: roomRows(result))
            explanation(
                title: "Sealed on this device",
                detail: "This sample has one player. The crew is not connected and no proof has been sent."
            )
            if result.stage == .sealed { openingClockDisclosure }
        case .opening:
            if result.stage == .sealed {
                ResultRosterCard(rows: [ResultRosterItem(name: "You", value: "Sealed", sealed: true)])
                openingClockDisclosure
            } else {
                openedRoster(result)
                ResultVerification(
                    headline: "Your opened pick matched its seal.",
                    detail: "The opening proof was generated here. No shared round was updated.",
                    emphasized: true
                )
                if result.stage == .revealed {
                    explanation(
                        title: "You call this sample",
                        detail: "Opening a pick is not an outcome. Nobody scores until the call is proved."
                    )
                }
            }
        case .mismatch:
            if flow.roundFailure == .revealMismatch {
                ResultRosterCard(rows: [ResultRosterItem(name: "You", detail: "Reveal didn’t match the seal", score: "—")])
                explanation(
                    title: "The opening was rejected",
                    detail: "The pick supplied for opening did not match the sealed pick. No opening proof or score was accepted."
                )
            } else {
                explanation(
                    title: "No rejected reveal in this session",
                    detail: "This screen only reports a mismatch after the proof preparation rejects an opening."
                )
            }
        case .verdict, .standings:
            if result.stage == .settled {
                localVerdictBars(result)
                scoreCard(result)
                explanation(
                    title: destination == .standings ? "One local round" : "Called by you",
                    detail: "The score comes from your opened pick and the proved outcome. No season history or shared standings are connected."
                )
            } else if result.stage == .disputed {
                voidedContent(result)
            } else {
                openedRoster(result)
                explanation(title: "No score yet", detail: "Open the pick and prove the call to finish this local round.")
            }
        case .settle:
            if result.stage == .revealed {
                outcomeChoices(result.round)
                explanation(
                    title: "Your call, recorded locally",
                    detail: "This advances the sample clock past its opening window, then proves the selected outcome. It does not change the device clock or submit a transaction."
                )
            } else {
                explanation(title: "The call is not available", detail: "A local pick must be opened before this sample can be called. A completed call cannot be replaced.")
            }
        case .challenge:
            if result.stage == .settled {
                explanation(
                    title: "You called it: \(outcomeLabel(result))",
                    detail: "A proved challenge voids this local round. Nobody scores. This is not a vote and there is no connected crew."
                )
                explanation(
                    title: "Challenged by you",
                    detail: "Your local player identity will be recorded in the sample’s public result. This uses the sample clock inside the challenge window."
                )
            } else {
                explanation(title: "No call to challenge", detail: "Only a completed, undisputed local call can be challenged here.")
            }
        case .voided:
            if result.stage == .disputed {
                voidedContent(result)
            } else {
                explanation(title: "This round is not voided", detail: "No proved challenge has been accepted for this local round.")
            }
        }
    }

    private func roomRows(_ result: LocalRoundResult) -> [ResultRosterItem] {
        if result.stage != .sealed {
            return [ResultRosterItem(name: "You", value: openedLabel(result))]
        }
        if let display = flow.sealedDisplay, display.roundID == result.roundID {
            return [ResultRosterItem(name: "You", value: display.selectedSide, valueDetail: "only you can see this")]
        }
        return [ResultRosterItem(name: "You", value: "Sealed", sealed: true)]
    }

    private func openedRoster(_ result: LocalRoundResult) -> some View {
        ResultRosterCard(
            rows: [ResultRosterItem(name: "You", value: openedLabel(result))],
            revealsOnAppear: result.stage == .revealed && destination == .opening,
            hapticOnOwnReveal: true
        )
    }

    private func openedLabel(_ result: LocalRoundResult) -> String {
        result.revealedChoice.flatMap { result.round.sideLabel(for: $0) } ?? "Not opened"
    }

    private func outcomeLabel(_ result: LocalRoundResult) -> String {
        result.outcome.flatMap { result.round.sideLabel(for: $0) } ?? "No result"
    }

    private func didWin(_ result: LocalRoundResult) -> Bool {
        guard result.stage == .settled, let pick = result.revealedChoice, let outcome = result.outcome else { return false }
        return pick == outcome
    }

    private func localVerdictBars(_ result: LocalRoundResult) -> some View {
        SlipCard {
            VStack(spacing: SlipSpacing.standard) {
                ForEach([UInt8(1), UInt8(0)], id: \.self) { choice in
                    let tally = choice == 1 ? result.tallyYes : result.tallyNo
                    let total = result.tallyYes + result.tallyNo
                    let won = result.outcome == choice
                    VStack(spacing: SlipSpacing.small) {
                        VerdictBarHeading(
                            side: result.round.sideLabel(for: choice) ?? "Unknown side",
                            detail: "\(tally) \(tally == 1 ? "pick" : "picks")",
                            calledIt: won
                        )
                        ResultBar(
                            value: total > 0 ? CGFloat(tally) / CGFloat(total) : .zero,
                            color: won ? SlipColor.win : SlipColor.secondary
                        )
                    }
                }
            }
        }
    }

    private func scoreCard(_ result: LocalRoundResult) -> some View {
        ResultRosterCard(
            rows: [ResultRosterItem(
                name: "You",
                detail: didWin(result) ? "You called it" : "Next one’s yours",
                value: openedLabel(result),
                score: didWin(result) ? "+1" : "0",
                winner: didWin(result),
                struck: !didWin(result)
            )],
            showsVerdict: true
        )
    }

    @ViewBuilder private func voidedContent(_ result: LocalRoundResult) -> some View {
        explanation(
            title: "You challenged the call",
            detail: "The challenge proof was generated on this device. This local round is voided and its score is zero."
        )
        ResultRosterCard(rows: [ResultRosterItem(name: "You", value: openedLabel(result), score: "—")])
        if result.revealedChoice != nil {
            ResultVerification(headline: "Your opened pick still matched its seal.", detail: "A challenge changes the result, not the pick.")
        }
    }

    @ViewBuilder private func outcomeChoices(_ round: LocalRound) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: SlipSpacing.medium) { localChoiceButtons(round) }
        } else {
            HStack(spacing: SlipSpacing.medium) { localChoiceButtons(round) }
        }
    }

    private func localChoiceButtons(_ round: LocalRound) -> some View {
        ForEach([UInt8(1), UInt8(0)], id: \.self) { choice in
            LocalOutcomeChoiceButton(
                title: round.sideLabel(for: choice) ?? "Unknown side",
                isSelected: selectedOutcome == choice
            ) {
                selectedOutcome = choice
            }
            .disabled(flow.isRoundBusy)
        }
    }

    private var openingClockDisclosure: some View {
        explanation(
            title: "Open this local sample",
            detail: "This advances the sample clock to its opening window and proves the original sealed pick. It does not change the device clock or open a shared round."
        )
    }

    private var unavailableCard: some View {
        explanation(
            title: "No completed local round",
            detail: "Seal a pick first. This build keeps its local round only for the current app session; it cannot recover a pick after the app is closed."
        )
    }

    private func failureCard(_ failure: AppSealError) -> some View {
        explanation(title: failure.displayName, detail: "This step did not complete. The last accepted local result is unchanged.")
    }

    private func explanation(title: String, detail: String) -> some View {
        SlipCard {
            VStack(alignment: .leading, spacing: SlipSpacing.small) {
                Text(title).font(SlipFont.headline).foregroundStyle(SlipColor.ink)
                Text(detail).font(SlipFont.body).foregroundStyle(SlipColor.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var actions: some View {
        if let result {
            switch destination {
            case .room, .opening, .mismatch:
                switch result.stage {
                case .sealed:
                    PillButton(title: "Open this local sample") { beginReveal(result) }
                        .disabled(flow.isRoundBusy)
                case .revealed:
                    PillButton(title: "Call this local round") { model.go(.settle) }
                case .settled:
                    PillButton(title: "See the verdict") { model.go(.verdict) }
                case .disputed:
                    PillButton(title: "See the voided round") { model.go(.voided) }
                }
            case .settle:
                if result.stage == .revealed {
                    PillButton(title: "Call it: \(result.round.sideLabel(for: selectedOutcome) ?? "selected side")") {
                        pendingRoundID = result.roundID
                        pendingStage = .settled
                        flow.beginSettle(roundID: result.roundID, outcome: selectedOutcome)
                    }
                    .disabled(flow.isRoundBusy)
                } else {
                    PillButton(title: "Back to the round", tone: .secondary) { model.go(.opening) }
                }
            case .challenge:
                if result.stage == .settled {
                    PillButton(title: "Challenge and void this local round") {
                        pendingRoundID = result.roundID
                        pendingStage = .disputed
                        flow.beginDispute(roundID: result.roundID)
                    }
                    .disabled(flow.isRoundBusy)
                    PillButton(title: "Keep the call", tone: .secondary, action: model.back)
                } else {
                    PillButton(title: "Back to the round", tone: .secondary, action: model.back)
                }
            case .verdict:
                PillButton(title: "See local standings") { model.go(.standings) }
                if result.stage == .settled {
                    PillButton(title: "Challenge the call", tone: .secondary) { model.go(.challenge) }
                }
            case .standings, .voided:
                PillButton(title: "New slip") { model.go(.newSlip) }
            }
        } else {
            PillButton(title: "Seal a local pick") { model.go(.seal) }
        }
    }

    private func beginReveal(_ result: LocalRoundResult) {
        pendingRoundID = result.roundID
        pendingStage = .revealed
        flow.beginReveal(roundID: result.roundID)
    }
}

private struct LocalOutcomeChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility

    var body: some View {
        Button(action: action) {
            VStack(spacing: SlipSpacing.medium) {
                Image(systemName: isSelected ? "checkmark.circle" : "circle").font(SlipFont.title2)
                Text(title).font(SlipFont.title3Bold).multilineTextAlignment(.center)
            }
            .foregroundStyle(isSelected ? SlipColor.background : SlipColor.secondary)
            .padding(SlipSpacing.standard)
            .frame(maxWidth: .infinity, minHeight: SlipSpacing.stage)
            .background(isSelected ? SlipColor.ink : SlipColor.fill, in: RoundedRectangle(cornerRadius: SlipRadius.card))
            .overlay {
                if contrast == .increased || accessibility.increaseContrast {
                    RoundedRectangle(cornerRadius: SlipRadius.card)
                        .stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SlipRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LocalProofTimings: View {
    let steps: [LocalStepReceipt]

    var body: some View {
        SlipCard {
            VStack(alignment: .leading, spacing: SlipSpacing.standard) {
                Text("Proved on this device").font(SlipFont.headline).foregroundStyle(SlipColor.ink)
                ForEach(steps.indices, id: \.self) { index in
                    let receipt = steps[index]
                    VStack(alignment: .leading, spacing: SlipSpacing.small) {
                        Text(stepTitle(receipt.step))
                            .font(SlipFont.subheadlineBold)
                            .foregroundStyle(SlipColor.ink)
                        Text("Prepare \(milliseconds(receipt.executeDuration)) · Key \(milliseconds(receipt.keyLoadDuration))")
                            .font(SlipFont.machine)
                            .foregroundStyle(SlipColor.secondary)
                        Text("Proof \(milliseconds(receipt.proveDuration)) · \(receipt.proofBytes) bytes")
                            .font(SlipFont.machine)
                            .foregroundStyle(SlipColor.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    if index != steps.indices.last { InsetDivider(inset: SlipSpacing.zero) }
                }
                Text("Measured locally. These proofs have not been submitted to a network.")
                    .font(SlipFont.footnote)
                    .foregroundStyle(SlipColor.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func milliseconds(_ duration: Duration) -> String {
        let parts = duration.components
        let value = Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
        return String(format: "%.1f ms", value)
    }

    private func stepTitle(_ step: LocalProofStep) -> String {
        switch step {
        case .enrollMember: "Add the local player"
        case .createSlip: "Create the round"
        case .sealPick: "Seal the pick"
        case .reveal: "Open the pick"
        case .settle: "Call the outcome"
        case .dispute: "Challenge the call"
        }
    }
}

// MARK: - Result components

private enum ResultLayout {
    static let segmentWidth: CGFloat = 208
    static let leaderAvatarLift = -SlipSpacing.large
    static let shellTopPadding = SlipSpacing.large
    static let compactSectionSpacing = SlipSpacing.medium
    static let leaderArtHeight = SlipSpacing.stage
    static let compactAvatar = SlipSize.avatarSmall - SlipSpacing.tiny
    static let compactRosterRowHeight = SlipSize.avatarSmall + SlipSpacing.medium + SlipSpacing.micro
    static let standardDividerInset = SlipSize.avatarSmall + SlipSpacing.standard + SlipSpacing.medium
    static let compactDividerInset = compactAvatar + SlipSpacing.standard + SlipSpacing.medium
    static let compactRankingRowHeight = SlipSize.avatarSmall + SlipSpacing.screen
    static let normalYesShare: CGFloat = 0.6
    static let normalNoShare: CGFloat = 0.4
    static let satOutYesShare: CGFloat = 0.75
    static let satOutNoShare: CGFloat = 0.25
    static let avatarOverlap = -SlipSpacing.medium
}

private struct ResultRosterItem {
    let name: String
    var detail: String? = nil
    var value: String? = nil
    var valueDetail: String? = nil
    var score: String? = nil
    var sealed: Bool? = nil
    var winner = false
    var struck = false
    var valueSecondary = false
}

private struct ResultRosterCard: View {
    let rows: [ResultRosterItem]
    var usesCompactRows = false
    var revealsOnAppear = false
    var hapticOnOwnReveal = false
    var showsVerdict = false
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.slipAccessibility) private var accessibility
    @State private var revealedRows: Set<Int> = []
    @State private var revealTask: Task<Void, Never>?
    @State private var deliveredOwnRevealHaptic = false

    var body: some View {
        SlipCard(padding: SlipSpacing.zero) {
            VStack(spacing: SlipSpacing.zero) {
                ForEach(rows.indices, id: \.self) { index in
                    VStack(spacing: SlipSpacing.zero) {
                        ResultRosterRow(
                            item: rows[index],
                            usesCompactLayout: usesCompactRows,
                            showsVerdict: showsVerdict
                        )
                        if index != rows.indices.last {
                            InsetDivider(inset: usesCompactRows
                                ? ResultLayout.compactDividerInset
                                : ResultLayout.standardDividerInset)
                        }
                    }
                    .modifier(ResultRevealModifier(
                        isRevealed: isRowRevealed(at: index),
                        reduceMotion: shouldReduceMotion
                    ))
                }
            }
        }
        .onAppear {
            beginRevealIfNeeded()
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
            revealedRows = RevealMotionPlan.completedRows(
                afterCancelling: revealedRows,
                participatingIndices: rows.indices.filter { rowParticipatesInReveal(at: $0) }
            )
        }
    }

    private var shouldReduceMotion: Bool {
        reduceMotion || accessibility.reduceMotion
    }

    private func rowParticipatesInReveal(at index: Int) -> Bool {
        revealsOnAppear && rows[index].value != nil
    }

    private func isRowRevealed(at index: Int) -> Bool {
        !rowParticipatesInReveal(at: index) || model.isPreview || revealedRows.contains(index)
    }

    @MainActor private func beginRevealIfNeeded() {
        guard revealsOnAppear, !model.isPreview, revealTask == nil, revealedRows.isEmpty else { return }
        let animatedIndices = rows.indices.filter { rowParticipatesInReveal(at: $0) }
        let animation: Animation = shouldReduceMotion
            ? .easeOut(duration: SlipMotion.revealDuration)
            : .spring(duration: SlipMotion.revealDuration, bounce: RevealMotionPlan.noBounce)

        revealTask = Task { @MainActor in
            var previousDelay = TimeInterval.zero
            for index in animatedIndices {
                let scheduledDelay = RevealMotionPlan.delay(forRowAt: index)
                let incrementalDelay = scheduledDelay - previousDelay
                if incrementalDelay > .zero {
                    try? await Task.sleep(for: .seconds(incrementalDelay))
                }
                guard !Task.isCancelled else { return }

                withAnimation(animation) {
                    _ = revealedRows.insert(index)
                }

                if hapticOnOwnReveal, rows[index].name == "You", !deliveredOwnRevealHaptic {
                    deliveredOwnRevealHaptic = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                previousDelay = scheduledDelay
            }
            revealTask = nil
        }
    }
}

private struct ResultRosterRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: ResultRosterItem
    let usesCompactLayout: Bool
    let showsVerdict: Bool

    var body: some View {
        Group {
            if let sealed = item.sealed, let detail = item.detail {
                detailedSeal(sealed: sealed, detail: detail)
            } else if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: SlipSpacing.medium) {
                    InitialAvatar(name: item.name, size: avatarSize)
                    VStack(alignment: .leading, spacing: SlipSpacing.small) {
                        identity
                        trailing(isTrailing: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: SlipSpacing.medium) {
                    InitialAvatar(name: item.name, size: avatarSize)
                    identity
                    Spacer(minLength: SlipSpacing.small)
                    trailing(isTrailing: true)
                }
            }
        }
        .foregroundStyle(SlipColor.ink)
        .padding(.horizontal, SlipSpacing.standard)
        .padding(.vertical, rowVerticalPadding)
        .frame(minHeight: rowMinimumHeight)
        .accessibilityElement(children: .combine)
    }

    private func detailedSeal(sealed: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: SlipSpacing.medium) {
            InitialAvatar(name: item.name, size: avatarSize)
            VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: SlipSpacing.tiny))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: SlipSpacing.small))
                layout {
                    Text(item.name).font(item.name == "You" ? SlipFont.headline : SlipFont.body)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: SlipSpacing.tiny) }
                    SealStatusTag(sealed: sealed)
                }
                RowMetadata(symbol: "clock", text: detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var usesCompactMetrics: Bool {
        usesCompactLayout && !dynamicTypeSize.isAccessibilitySize
    }

    private var avatarSize: CGFloat {
        usesCompactMetrics ? ResultLayout.compactAvatar : SlipSize.avatarSmall
    }

    private var rowVerticalPadding: CGFloat {
        usesCompactMetrics ? SlipSpacing.small : SlipSpacing.medium
    }

    private var rowMinimumHeight: CGFloat {
        usesCompactMetrics ? ResultLayout.compactRosterRowHeight : SlipSize.rosterRowHeight
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.micro) {
            Text(item.name).font(item.name == "You" ? SlipFont.headline : SlipFont.body)
            if let detail = item.detail {
                Text(detail).font(SlipFont.caption).foregroundStyle(SlipColor.secondary)
            }
        }
    }

    @ViewBuilder private func trailing(isTrailing: Bool) -> some View {
        HStack(alignment: .center, spacing: SlipSpacing.medium) {
            if let sealed = item.sealed {
                SealStatusTag(sealed: sealed)
            } else if let value = item.value {
                VStack(alignment: isTrailing ? .trailing : .leading, spacing: SlipSpacing.micro) {
                    Text(value)
                        .font(SlipFont.bodyBold)
                        .strikethrough(item.struck)
                        .foregroundStyle(item.struck || item.valueSecondary ? SlipColor.secondary : SlipColor.ink)
                    if let valueDetail = item.valueDetail {
                        Text(dynamicTypeSize.isAccessibilitySize ? "only you" : valueDetail)
                            .font(SlipFont.caption)
                            .foregroundStyle(SlipColor.secondary)
                            .multilineTextAlignment(isTrailing ? .trailing : .leading)
                    }
                }
            }
            if let score = item.score {
                Text(score)
                    .font(SlipFont.bodyBold)
                    .foregroundStyle(showsVerdict && item.winner ? SlipColor.win : SlipColor.secondary)
                    .frame(minWidth: SlipSize.minimumTap, alignment: .trailing)
            }
        }
    }
}

private struct ResultRevealModifier: ViewModifier {
    let isRevealed: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let state = RevealMotionPlan.visualState(isRevealed: isRevealed, reduceMotion: reduceMotion)
        content
            .opacity(state.opacity)
            .accessibilityHidden(!isRevealed)
            .rotation3DEffect(
                .degrees(state.rotationDegrees),
                axis: (
                    x: RevealMotionPlan.axisX,
                    y: RevealMotionPlan.axisY,
                    z: RevealMotionPlan.axisZ
                ),
                perspective: RevealMotionPlan.perspective
            )
    }
}

private struct ResultVerification: View {
    let headline: String
    var detail: String? = nil
    var emphasized = false

    var body: some View {
        HStack(alignment: .top, spacing: SlipSpacing.medium) {
            Image(systemName: "checkmark.circle")
                .font(SlipFont.body)
                .foregroundStyle(emphasized ? SlipColor.ink : SlipColor.secondary)
                .frame(width: SlipSize.icon, height: SlipSize.icon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SlipSpacing.small) {
                Text(headline)
                    .font(emphasized ? SlipFont.subheadlineBold : SlipFont.footnote)
                    .foregroundStyle(emphasized ? SlipColor.ink : SlipColor.secondary)
                if let detail {
                    Text(detail).font(SlipFont.footnote).foregroundStyle(SlipColor.secondary)
                }
            }
        }
        .padding(.horizontal, SlipSpacing.tiny)
        .accessibilityElement(children: .combine)
    }
}

private struct ResultIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(SlipFont.title2)
                .foregroundStyle(SlipColor.ink)
                .frame(width: SlipSize.minimumTap, height: SlipSize.minimumTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ResultStatusChip: View {
    let text: String
    var symbol = "clock"

    var body: some View {
        StatusChip(text: text, symbol: symbol)
    }
}

private struct FixtureDisclosure: View {
    var body: some View {
        ResultStatusChip(text: "Preview only · no shared round", symbol: "eye")
            .accessibilityLabel("Preview only. No shared round.")
    }
}

private struct ResultBadge: View {
    let title: String
    let symbol: String
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility

    var body: some View {
        Label(title, systemImage: symbol)
            .font(SlipFont.subheadlineBold)
            .foregroundStyle(SlipColor.ink)
            .padding(.horizontal, SlipSpacing.standard)
            .padding(.vertical, SlipSpacing.tiny)
            .background(SlipColor.card, in: Capsule())
            .overlay {
                if contrast == .increased || accessibility.increaseContrast {
                    Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.standard)
                }
            }
    }
}

private struct VerdictBars: View {
    let satOut: Bool

    var body: some View {
        SlipCard {
            VStack(spacing: SlipSpacing.standard) {
                VStack(spacing: SlipSpacing.small) {
                    VerdictBarHeading(side: "Yes", detail: "3 picks", calledIt: true)
                    ResultBar(value: satOut ? ResultLayout.satOutYesShare : ResultLayout.normalYesShare, color: SlipColor.win)
                        .accessibilityLabel("Yes")
                        .accessibilityValue("3 picks, called it")
                }

                VStack(spacing: SlipSpacing.small) {
                    VerdictBarHeading(side: "No", detail: satOut ? "1 pick · 1 sat out" : "2 picks")
                    ResultBar(value: satOut ? ResultLayout.satOutNoShare : ResultLayout.normalNoShare, color: SlipColor.secondary)
                        .accessibilityLabel("No")
                        .accessibilityValue(satOut ? "1 pick, 1 sat out" : "2 picks")
                }
            }
            .padding(.vertical, SlipSpacing.small)
            .foregroundStyle(SlipColor.ink)
        }
    }
}

private struct VerdictBarHeading: View {
    let side: String
    let detail: String
    var calledIt = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: SlipSpacing.small) {
                labels
                Spacer(minLength: SlipSpacing.small)
                if calledIt { calledItLabel }
            }
            VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                labels
                if calledIt { calledItLabel }
            }
        }
    }

    private var labels: some View {
        HStack(alignment: .firstTextBaseline, spacing: SlipSpacing.small) {
            Text(side).font(SlipFont.headline)
            Text(detail).font(SlipFont.body).foregroundStyle(SlipColor.secondary)
        }
    }

    private var calledItLabel: some View {
        Text("called it").font(SlipFont.subheadlineBold).foregroundStyle(SlipColor.win)
    }
}

private struct ResultBar: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility
    let value: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SlipColor.fill)
                Capsule().fill(color).frame(width: proxy.size.width * value)
            }
        }
        .frame(height: SlipSize.progressHeight)
        .overlay {
            if contrast == .increased || accessibility.increaseContrast {
                Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.standard)
            }
        }
    }
}

private struct ResultCommentRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let name: String
    let text: String
    let reply: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SlipSpacing.small) {
                    HStack(alignment: .top, spacing: SlipSpacing.medium) {
                        InitialAvatar(name: name, size: SlipSize.avatarSmall)
                        Text(text).font(SlipFont.body).foregroundStyle(SlipColor.ink)
                    }
                    replyButton
                        .padding(.leading, SlipSize.avatarSmall + SlipSpacing.medium)
                }
            } else {
                HStack(spacing: SlipSpacing.medium) {
                    InitialAvatar(name: name, size: SlipSize.avatarSmall)
                    Text(text).font(SlipFont.body).foregroundStyle(SlipColor.ink)
                    Spacer(minLength: SlipSpacing.small)
                    replyButton
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var replyButton: some View {
        Button("Reply", action: reply)
            .font(SlipFont.subheadlineBold)
            .foregroundStyle(SlipColor.secondary)
            .frame(minHeight: SlipSize.minimumTap)
            .buttonStyle(.plain)
    }
}

private enum StandingsPeriod: Equatable, Sendable {
    case week
    case season
}

private struct RankingItem {
    let rank: String
    let name: String
    let score: String
}

private struct RankingRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: RankingItem

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: SlipSpacing.medium) {
                    InitialAvatar(name: item.name)
                    VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                        Text("Rank \(item.rank)").font(SlipFont.footnote).foregroundStyle(SlipColor.secondary)
                        Text(item.name).font(item.name == "You" ? SlipFont.headline : SlipFont.body)
                        Text("\(item.score) points").font(SlipFont.title3Bold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: SlipSpacing.medium) {
                    Text(item.rank)
                        .font(SlipFont.body)
                        .foregroundStyle(SlipColor.secondary)
                        .frame(width: SlipSize.icon, alignment: .leading)
                    InitialAvatar(name: item.name)
                    Text(item.name).font(item.name == "You" ? SlipFont.headline : SlipFont.body)
                    Spacer(minLength: SlipSpacing.small)
                    Text(item.score).font(SlipFont.title3Bold)
                }
            }
        }
        .foregroundStyle(SlipColor.ink)
        .padding(.horizontal, SlipSpacing.screen)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? SlipSpacing.medium : SlipSpacing.small)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize
            ? SlipSize.rosterRowHeight
            : ResultLayout.compactRankingRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(item.rank), \(item.name), \(item.score) points")
    }
}

private enum CallOutcome: Equatable, Sendable {
    case rained
    case dry

    var title: String { self == .rained ? "It rained" : "It didn’t" }
    var actionTitle: String { self == .rained ? "Call it: it rained" : "Call it: it didn’t" }
    var summary: String {
        self == .rained
            ? "Yes called it. Ana, Maya and you score +1. Raj and Tomás take the banter."
            : "No called it. Raj and Tomás score +1. Ana, Maya and you take the banter."
    }
}

private struct CallChoiceButton: View {
    let outcome: CallOutcome
    @Binding var selection: CallOutcome
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility

    private var isSelected: Bool { selection == outcome }

    var body: some View {
        Button {
            selection = outcome
        } label: {
            VStack(spacing: SlipSpacing.medium) {
                Image(systemName: isSelected ? "checkmark.circle" : "circle")
                    .font(SlipFont.title2)
                Text(outcome.title).font(SlipFont.title3Bold)
            }
            .foregroundStyle(isSelected ? SlipColor.background : SlipColor.secondary)
            .frame(maxWidth: .infinity, minHeight: SlipSpacing.stage)
            .background(isSelected ? SlipColor.ink : SlipColor.fill, in: RoundedRectangle(cornerRadius: SlipRadius.card))
            .overlay {
                if contrast == .increased || accessibility.increaseContrast {
                    RoundedRectangle(cornerRadius: SlipRadius.card)
                        .stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SlipRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ChallengeReasonField: View {
    @Binding var text: String
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Say why (optional) — the crew will see it")
                    .font(SlipFont.body)
                    .foregroundStyle(SlipColor.secondary)
                    .padding(SlipSpacing.standard)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .font(SlipFont.body)
                .foregroundStyle(SlipColor.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, SlipSpacing.small)
                .padding(.vertical, SlipSpacing.tiny)
                .accessibilityLabel("Reason for challenge, optional")
        }
        .frame(minHeight: SlipSize.noteFieldHeight)
        .background(SlipColor.fill, in: RoundedRectangle(cornerRadius: SlipRadius.control))
        .overlay {
            if contrast == .increased || accessibility.increaseContrast {
                RoundedRectangle(cornerRadius: SlipRadius.control)
                    .stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.standard)
            }
        }
    }
}

private struct ChallengerAvatars: View {
    var body: some View {
        HStack(spacing: ResultLayout.avatarOverlap) {
            InitialAvatar(name: "Raj")
            InitialAvatar(name: "Ana")
                .overlay(Circle().stroke(SlipColor.card, lineWidth: SlipSpacing.tiny))
        }
        .accessibilityHidden(true)
    }
}
