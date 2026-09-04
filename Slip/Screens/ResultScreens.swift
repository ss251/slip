import SwiftUI

enum OpeningMode: Equatable, Sendable {
    case opening
    case awaiting
    case mismatch
}

struct SealedRoomScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: SlipSpacing.large) {
                HStack {
                    ResultIconButton(symbol: "chevron.left", label: "Back", action: model.back)
                    Spacer()
                }

                VStack(spacing: SlipSpacing.large) {
                    CrewArt(size: SlipSize.artLarge)

                    VStack(spacing: SlipSpacing.medium) {
                        Text(PreviewContent.question)
                            .font(SlipFont.title2)
                            .foregroundStyle(SlipColor.ink)
                            .multilineTextAlignment(.center)
                        Text("Saturday crew · 3 of 5 sealed")
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
                PillButton(title: "Nudge Maya & Tomás", tone: .secondary) {
                    model.inform("This preview did not send a nudge to Maya or Tomás.")
                }
                Text("Everyone opens together at Friday 21:00.")
                    .font(SlipFont.footnote)
                    .foregroundStyle(SlipColor.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var rows: [ResultRosterItem] {
        let ownPick = model.hasLocalSeal ? model.selectedSide : "Yes"
        return [
            ResultRosterItem(name: "You", value: ownPick, valueDetail: "only you can see this"),
            ResultRosterItem(name: "Ana", value: "Sealed", sealed: true, valueSecondary: true),
            ResultRosterItem(name: "Raj", value: "Sealed", sealed: true, valueSecondary: true),
            ResultRosterItem(name: "Maya", value: "Waiting", sealed: false, valueSecondary: true),
            ResultRosterItem(name: "Tomás", value: "Waiting", sealed: false, valueSecondary: true)
        ]
    }

    @ViewBuilder private var countdownChip: some View {
#if DEBUG
        StatusChip(text: "Opens in 14h 22m")
            .contextMenu {
                Button("Preview opening") { model.go(.opening) }
            }
            .accessibilityHint("Touch and hold to preview opening locally")
#else
        StatusChip(text: "Opens in 14h 22m")
#endif
    }
}

struct OpeningScreen: View {
    @Environment(AppModel.self) private var model
    let mode: OpeningMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                ScreenHeader(title: PreviewContent.question, subtitle: headerSubtitle)
                openingStatusChip

                ResultRosterCard(rows: rows)

                ResultVerification(
                    headline: verificationHeadline,
                    detail: verificationDetail,
                    emphasized: true
                )

                if mode == .awaiting {
                    stewardCard
                } else if mode == .mismatch {
                    mismatchCard
                    Text("Ana calls it once Saturday’s over.")
                        .font(SlipFont.footnote)
                        .foregroundStyle(SlipColor.secondary)
                        .padding(.horizontal, SlipSpacing.tiny)
                }
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .background { ArtBackdrop() }
        .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
            BottomActions {
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

    private var statusText: String {
        mode == .opening ? "4 of 5 opened" : "Everyone opened"
    }

    @ViewBuilder private var openingStatusChip: some View {
#if DEBUG
        StatusChip(text: statusText, symbol: "circle.fill")
            .contextMenu {
                if mode == .opening {
                    Button("Preview everyone opened") { model.go(.awaiting) }
                } else {
                    Button("Preview call sheet") { model.go(.settle) }
                }
            }
            .accessibilityHint("Touch and hold for the next local preview state")
#else
        StatusChip(text: statusText, symbol: "circle.fill")
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
    let satOut: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.screen) {
                verdictHeader
                VerdictBars(satOut: satOut)
                winnerCard
                ResultRosterCard(rows: resultRows)

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
            HStack(spacing: SlipSpacing.medium) {
                InitialAvatar(name: "You")
                VStack(alignment: .leading, spacing: SlipSpacing.micro) {
                    Text("You called it").font(SlipFont.headline)
                    Text("Sealed Yes on Tuesday")
                        .font(SlipFont.footnote)
                        .foregroundStyle(SlipColor.secondary)
                }
                Spacer(minLength: SlipSpacing.small)
                Text("+1")
                    .font(SlipFont.title2)
                    .foregroundStyle(SlipColor.win)
            }
            .foregroundStyle(SlipColor.ink)
            .accessibilityElement(children: .combine)
        }
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
            HStack(spacing: SlipSpacing.tiny) {
                Text("Called by Ana, Saturday 18:04 ·")
                    .foregroundStyle(SlipColor.secondary)
                challengeButton
            }
            VStack(alignment: .leading, spacing: SlipSpacing.small) {
                Text("Called by Ana, Saturday 18:04")
                    .foregroundStyle(SlipColor.secondary)
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
    @State private var period: StandingsPeriod = .week

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.screen) {
                ScreenHeader(title: "Standings", subtitle: "SATURDAY CREW")
                periodPicker
                standingsHero
                rankingCard
                Text("Season 1 · 6 slips · 30 proofs checked, 30 matched")
                    .font(SlipFont.footnote)
                    .foregroundStyle(SlipColor.secondary)
                    .padding(.horizontal, SlipSpacing.tiny)
            }
            .padding(.horizontal, SlipSpacing.screen)
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
        .padding(SlipSpacing.tiny)
        .background(SlipColor.fill, in: Capsule())
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
                        .frame(height: SlipSize.heroBannerHeight)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: SlipRadius.card,
                            bottomLeadingRadius: SlipSpacing.zero,
                            bottomTrailingRadius: SlipSpacing.zero,
                            topTrailingRadius: SlipRadius.card
                        ))

                    Label(period == .week ? "Week 4 leader" : "Season leader", systemImage: "crown")
                        .font(SlipFont.subheadlineBold)
                        .foregroundStyle(SlipColor.ink)
                        .padding(.horizontal, SlipSpacing.standard)
                        .frame(minHeight: SlipSize.minimumTap)
                        .background(SlipColor.card, in: Capsule())
                        .padding(SlipSpacing.medium)
                }

                HStack(spacing: SlipSpacing.standard) {
                    InitialAvatar(name: "Ana", size: SlipSize.avatarLarge)
                        .offset(y: ResultLayout.leaderAvatarLift)
                    VStack(alignment: .leading, spacing: SlipSpacing.micro) {
                        Text(period == .week ? "Ana takes the week" : "Ana leads the season")
                            .font(SlipFont.headline)
                        Text(period == .week ? "4 of 4 called · first to seal" : "18 of 28 called")
                            .font(SlipFont.footnote)
                            .foregroundStyle(SlipColor.secondary)
                    }
                    Spacer(minLength: SlipSpacing.small)
                    Text(period == .week ? "12" : "64")
                        .font(SlipFont.large)
                }
                .foregroundStyle(SlipColor.ink)
                .padding(.horizontal, SlipSpacing.screen)
                .padding(.bottom, SlipSpacing.standard)
            }
            .accessibilityElement(children: .combine)
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                SheetHeading(title: "Call it")
                ContextRow(detail: "Saturday crew · 5 of 5 opened · your call")
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
                PillButton(title: outcome.actionTitle) { model.go(.verdict) }
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
}

struct ChallengeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var reason = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                SheetHeading(title: "Challenge")

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
                PillButton(title: "Challenge and void the round") { model.go(.voided) }
                Button("Keep Ana’s call", action: model.back)
                    .font(SlipFont.headline)
                    .foregroundStyle(SlipColor.secondary)
                    .frame(maxWidth: .infinity, minHeight: SlipSize.minimumTap)
                    .buttonStyle(.plain)
            }
        }
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

    private let rows = [
        ResultRosterItem(name: "You", value: "Yes", score: "—"),
        ResultRosterItem(name: "Ana", value: "Yes", score: "—"),
        ResultRosterItem(name: "Maya", value: "Yes", score: "—"),
        ResultRosterItem(name: "Raj", value: "No", score: "—"),
        ResultRosterItem(name: "Tomás", value: "No", score: "—")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.screen) {
                ScreenHeader(title: "No result.", subtitle: "SATURDAY CREW · VOIDED")
                challengeSummary
                ResultRosterCard(rows: rows)
                ResultVerification(
                    headline: "5 of 5 opened, every reveal matched its seal.",
                    detail: "A challenge voids the round. Nobody scores. The next slip starts clean."
                )
                ResultCommentRow(name: "Ana", text: "Ana: it was raining, Raj.") {
                    model.inform("Replies are preview-only right now.")
                }
            }
            .padding(.horizontal, SlipSpacing.screen)
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SlipSpacing.standard) {
                    ChallengerAvatars()
                    challengeSummaryCopy
                }
                VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                    ChallengerAvatars()
                    challengeSummaryCopy
                }
            }
        }
    }

    private var challengeSummaryCopy: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
            Text("Raj challenged Ana’s call").font(SlipFont.headline)
            Text("Ana said it rained · Raj: “a drizzle is not rain” · Sunday 09:12")
                .font(SlipFont.footnote)
                .foregroundStyle(SlipColor.secondary)
        }
        .foregroundStyle(SlipColor.ink)
    }
}

// MARK: - Result components

private enum ResultLayout {
    static let segmentWidth: CGFloat = 208
    static let leaderAvatarLift = -SlipSpacing.large
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

    var body: some View {
        SlipCard(padding: SlipSpacing.zero) {
            VStack(spacing: SlipSpacing.zero) {
                ForEach(rows.indices, id: \.self) { index in
                    ResultRosterRow(item: rows[index])
                    if index != rows.indices.last { InsetDivider() }
                }
            }
        }
    }
}

private struct ResultRosterRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: ResultRosterItem

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: SlipSpacing.medium) {
                    InitialAvatar(name: item.name)
                    VStack(alignment: .leading, spacing: SlipSpacing.small) {
                        identity
                        trailing(isTrailing: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: SlipSpacing.medium) {
                    InitialAvatar(name: item.name)
                    identity
                    Spacer(minLength: SlipSpacing.small)
                    trailing(isTrailing: true)
                }
            }
        }
        .foregroundStyle(SlipColor.ink)
        .padding(.horizontal, SlipSpacing.standard)
        .padding(.vertical, SlipSpacing.medium)
        .frame(minHeight: SlipSize.rosterRowHeight)
        .accessibilityElement(children: .combine)
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
            if let value = item.value {
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
            if let sealed = item.sealed { SealGlyph(sealed: sealed) }
            if let score = item.score {
                Text(score)
                    .font(SlipFont.bodyBold)
                    .foregroundStyle(item.winner ? SlipColor.win : SlipColor.secondary)
                    .frame(minWidth: SlipSize.minimumTap, alignment: .trailing)
            }
        }
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
                    .font(emphasized ? SlipFont.headline : SlipFont.footnote)
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

private struct VerdictBars: View {
    let satOut: Bool

    var body: some View {
        SlipCard {
            VStack(spacing: SlipSpacing.standard) {
                VStack(spacing: SlipSpacing.small) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Yes").font(SlipFont.headline)
                        Text("3 picks").font(SlipFont.body).foregroundStyle(SlipColor.secondary)
                        Spacer()
                        Text("called it").font(SlipFont.subheadlineBold).foregroundStyle(SlipColor.win)
                    }
                    ResultBar(value: satOut ? ResultLayout.satOutYesShare : ResultLayout.normalYesShare, color: SlipColor.win)
                        .accessibilityLabel("Yes")
                        .accessibilityValue("3 picks, called it")
                }

                VStack(spacing: SlipSpacing.small) {
                    HStack(alignment: .firstTextBaseline, spacing: SlipSpacing.small) {
                        Text("No").font(SlipFont.headline)
                        Text(satOut ? "1 pick · 1 sat out" : "2 picks")
                            .font(SlipFont.body)
                            .foregroundStyle(SlipColor.secondary)
                        Spacer()
                    }
                    ResultBar(value: satOut ? ResultLayout.satOutNoShare : ResultLayout.normalNoShare, color: SlipColor.secondary)
                        .accessibilityLabel("No")
                        .accessibilityValue(satOut ? "1 pick, 1 sat out" : "2 picks")
                }
            }
            .foregroundStyle(SlipColor.ink)
        }
    }
}

private struct ResultBar: View {
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
    }
}

private struct ResultCommentRow: View {
    let name: String
    let text: String
    let reply: () -> Void

    var body: some View {
        HStack(spacing: SlipSpacing.medium) {
            InitialAvatar(name: name, size: SlipSize.avatarSmall)
            Text(text).font(SlipFont.body).foregroundStyle(SlipColor.ink)
            Spacer(minLength: SlipSpacing.small)
            Button("Reply", action: reply)
                .font(SlipFont.subheadlineBold)
                .foregroundStyle(SlipColor.secondary)
                .frame(minHeight: SlipSize.minimumTap)
                .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
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
    let item: RankingItem

    var body: some View {
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
        .foregroundStyle(SlipColor.ink)
        .padding(.horizontal, SlipSpacing.screen)
        .padding(.vertical, SlipSpacing.medium)
        .frame(minHeight: SlipSize.rosterRowHeight)
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
            .contentShape(RoundedRectangle(cornerRadius: SlipRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ChallengeReasonField: View {
    @Binding var text: String

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
