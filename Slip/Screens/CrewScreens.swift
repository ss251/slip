import SwiftUI

struct CrewsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                HStack {
                    Text("Crews")
                        .font(SlipFont.large)
                        .foregroundStyle(SlipColor.ink)
                    Spacer(minLength: SlipSpacing.standard)
                    RoundButton(symbol: "plus", label: "Create a crew") {
                        model.inform("Crew creation is not connected in this preview yet.")
                    }
                }

                SlipCard(padding: SlipSpacing.zero) {
                    VStack(spacing: SlipSpacing.zero) {
                        CrewSummaryRow(
                            name: "Saturday crew",
                            detail: "5 people · 6 slips",
                            palette: CrewMetrics.saturdayPalette,
                            status: "Seal by Fri",
                            sealState: false
                        ) {
                            model.go(.crewDetail)
                        }
                        InsetDivider(inset: CrewMetrics.summaryDividerInset)
                        CrewSummaryRow(
                            name: "Office pool",
                            detail: "9 people · 14 slips",
                            palette: CrewMetrics.officePalette,
                            status: "Opens 17:00",
                            sealState: true
                        ) {
                            model.inform("Only the Saturday crew is wired into this local preview.")
                        }
                        InsetDivider(inset: CrewMetrics.summaryDividerInset)
                        CrewSummaryRow(
                            name: "Book club",
                            detail: "4 people · 2 slips",
                            palette: CrewMetrics.bookPalette,
                            status: "Quiet",
                            sealState: nil
                        ) {
                            model.inform("Only the Saturday crew is wired into this local preview.")
                        }
                    }
                }

                Button {
                    model.go(.invite)
                } label: {
                    SlipCard {
                        HStack(spacing: SlipSpacing.medium) {
                            Image(systemName: "square.and.arrow.down")
                                .font(SlipFont.headline)
                            Text("Join a crew from a link")
                                .font(SlipFont.body)
                            Spacer(minLength: SlipSpacing.small)
                            Image(systemName: "chevron.right")
                                .font(SlipFont.footnoteBold)
                                .foregroundStyle(SlipColor.secondary)
                        }
                        .foregroundStyle(SlipColor.ink)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: SlipRadius.card))
                }
                .buttonStyle(.plain)

                Text("A crew is the people who can see who sealed. Picks stay sealed from everyone.")
                    .font(SlipFont.footnote)
                    .foregroundStyle(SlipColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SlipSpacing.tiny)

                Spacer(minLength: SlipSpacing.stage)
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, SlipSpacing.large)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("crews")
    }
}

private struct CrewSummaryRow: View {
    let name: String
    let detail: String
    let palette: Int
    let status: String
    let sealState: Bool?
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                        HStack(spacing: SlipSpacing.medium) {
                            CrewArt(size: SlipSize.art, palette: palette)
                            labels
                        }
                        HStack(spacing: SlipSpacing.medium) {
                            Text(status)
                                .font(sealState == false ? SlipFont.subheadlineBold : SlipFont.subheadline)
                                .foregroundStyle(sealState == false ? SlipColor.ink : SlipColor.secondary)
                            Spacer(minLength: SlipSpacing.small)
                            if let sealState {
                                SealGlyph(sealed: sealState)
                            }
                        }
                    }
                } else {
                    HStack(spacing: SlipSpacing.medium) {
                        CrewArt(size: SlipSize.art, palette: palette)
                        labels
                        Spacer(minLength: SlipSpacing.small)
                        Text(status)
                            .font(sealState == false ? SlipFont.subheadlineBold : SlipFont.subheadline)
                            .foregroundStyle(sealState == false ? SlipColor.ink : SlipColor.secondary)
                            .multilineTextAlignment(.trailing)
                        if let sealState {
                            SealGlyph(sealed: sealState)
                        }
                    }
                }
            }
            .padding(.horizontal, SlipSpacing.standard)
            .padding(.vertical, SlipSpacing.medium)
            .frame(minHeight: CrewMetrics.summaryRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
            Text(name)
                .font(SlipFont.headline)
                .foregroundStyle(SlipColor.ink)
            Text(detail)
                .font(SlipFont.subheadline)
                .foregroundStyle(SlipColor.secondary)
        }
    }
}

struct CrewDetailScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            ArtBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: SlipSpacing.large) {
                    toolbar
                    identity
                    openSlip
                    members
                }
                .padding(.horizontal, SlipSpacing.screen)
                .padding(.top, SlipSpacing.small)
                .padding(.bottom, SlipSpacing.section)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("crew-detail")
    }

    private var toolbar: some View {
        HStack {
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

            Spacer(minLength: SlipSpacing.standard)

            Button {
                model.inform("Sharing a crew link needs the system share sheet, which is not connected in this preview.")
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(SlipFont.title3)
                    .foregroundStyle(SlipColor.ink)
                    .frame(width: SlipSize.minimumTap, height: SlipSize.minimumTap)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share crew")
        }
    }

    private var identity: some View {
        VStack(spacing: SlipSpacing.medium) {
            CrewArt(size: SlipSize.artLarge)
                .padding(.bottom, SlipSpacing.small)
            Text("Saturday crew")
                .font(SlipFont.title2)
                .foregroundStyle(SlipColor.ink)
            Text("5 people · 6 slips · since June")
                .font(SlipFont.body)
                .foregroundStyle(SlipColor.secondary)
                .multilineTextAlignment(.center)
            Button {
                model.inform("Invites are not sent until the network flow is connected.")
            } label: {
                Label("Invite", systemImage: "square.and.arrow.up")
                    .font(SlipFont.headline)
                    .foregroundStyle(SlipColor.ink)
                    .padding(.horizontal, SlipSpacing.screen)
                    .frame(minHeight: SlipSize.minimumTap)
                    .background(SlipColor.fill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var openSlip: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.medium) {
            Text("Open")
                .font(SlipFont.subheadlineBold)
                .foregroundStyle(SlipColor.secondary)

            Button {
                model.go(.room)
            } label: {
                SlipCard {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                            HStack {
                                SealGlyph(sealed: false)
                                Spacer(minLength: SlipSpacing.standard)
                                Image(systemName: "chevron.right")
                                    .font(SlipFont.footnoteBold)
                                    .foregroundStyle(SlipColor.secondary)
                            }
                            openSlipLabels
                        }
                    } else {
                        HStack(spacing: SlipSpacing.medium) {
                            SealGlyph(sealed: false)
                            openSlipLabels
                            Spacer(minLength: SlipSpacing.small)
                            Image(systemName: "chevron.right")
                                .font(SlipFont.footnoteBold)
                                .foregroundStyle(SlipColor.secondary)
                        }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: SlipRadius.card))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, SlipSpacing.standard)
    }

    private var openSlipLabels: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
            Text(model.sampleQuestion)
                .font(SlipFont.headline)
                .foregroundStyle(SlipColor.ink)
                .multilineTextAlignment(.leading)
            Text("Seal by Fri 20:00 · 3 of 5 sealed")
                .font(SlipFont.subheadline)
                .foregroundStyle(SlipColor.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var members: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.medium) {
            Text("Members")
                .font(SlipFont.subheadlineBold)
                .foregroundStyle(SlipColor.secondary)

            SlipCard(padding: SlipSpacing.zero) {
                VStack(spacing: SlipSpacing.zero) {
                    ForEach(Array(CrewMember.preview.enumerated()), id: \.element.id) { index, member in
                        MemberRow(name: member.name, detail: member.detail, value: member.score)
                        if index < CrewMember.preview.count - CrewMetrics.lastItemOffset {
                            InsetDivider()
                        }
                    }
                }
            }
        }
    }
}

struct YouScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SlipSpacing.large) {
                profileHeader
                profileIdentity
                stats
                history
                settings
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, SlipSpacing.large)
            .padding(.bottom, SlipSpacing.section)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("you")
    }

    private var profileHeader: some View {
        HStack {
            Text("You")
                .font(SlipFont.large)
                .foregroundStyle(SlipColor.ink)
            Spacer(minLength: SlipSpacing.standard)
            Button("Edit") {
                model.inform("Profile editing is not available in this local preview.")
            }
            .font(SlipFont.headline)
            .foregroundStyle(SlipColor.ink)
            .padding(.horizontal, SlipSpacing.standard)
            .frame(minHeight: SlipSize.minimumTap)
            .background(SlipColor.fill, in: Capsule())
        }
    }

    private var profileIdentity: some View {
        HStack(spacing: SlipSpacing.standard) {
            InitialAvatar(name: "You", size: SlipSize.avatarLarge)
            VStack(alignment: .leading, spacing: SlipSpacing.small) {
                Text("Sailesh")
                    .font(SlipFont.title2)
                    .foregroundStyle(SlipColor.ink)
                Text("3 crews · sealing since June")
                    .font(SlipFont.body)
                    .foregroundStyle(SlipColor.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var stats: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: SlipSpacing.medium) {
                statCards
            }
        } else {
            HStack(spacing: SlipSpacing.small) {
                statCards
            }
        }
    }

    @ViewBuilder private var statCards: some View {
        ProfileStat(value: "18", label: "called")
        ProfileStat(value: "64%", label: "hit rate")
        ProfileStat(value: "28", label: "sealed")
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.medium) {
            Text("Sealed history")
                .font(SlipFont.subheadlineBold)
                .foregroundStyle(SlipColor.secondary)

            SlipCard(padding: SlipSpacing.zero) {
                VStack(spacing: SlipSpacing.zero) {
                    ProfileHistoryRow(
                        question: model.sampleQuestion,
                        detail: "Sealed · opens Fri 21:00",
                        palette: CrewMetrics.saturdayPalette,
                        accessory: .sealed
                    ) {
                        model.go(.room)
                    }
                    InsetDivider(inset: CrewMetrics.historyDividerInset)
                    ProfileHistoryRow(
                        question: "Does the demo survive the all-hands?",
                        detail: "Yes · opens today 17:00",
                        palette: CrewMetrics.officePalette,
                        accessory: .sealed
                    ) {
                        model.go(.room)
                    }
                    InsetDivider(inset: CrewMetrics.historyDividerInset)
                    ProfileHistoryRow(
                        question: "Will Raj actually ship this week?",
                        detail: "No · called it",
                        palette: CrewMetrics.saturdayPalette,
                        accessory: .score("+1")
                    ) {
                        model.go(.verdict)
                    }
                }
            }
        }
    }

    private var settings: some View {
        SlipCard(padding: SlipSpacing.zero) {
            VStack(spacing: SlipSpacing.zero) {
                ProfileSettingRow(title: "Notifications", detail: "Opens and nudges") {
                    model.inform("Notification settings open after app permissions are connected.")
                }
                InsetDivider(inset: SlipSpacing.standard)
                ProfileSettingRow(title: "Appearance", detail: "Match iPhone") {
                    model.inform("Slip currently follows your iPhone appearance.")
                }
                InsetDivider(inset: SlipSpacing.standard)
                ProfileSettingRow(title: "Your receipts", detail: "Every proof this iPhone made") {
                    model.inform("Receipt history is local-only and will appear after you seal a pick.")
                }
            }
        }
    }
}

private struct ProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        SlipCard {
            VStack(alignment: .leading, spacing: SlipSpacing.small) {
                Text(value)
                    .font(SlipFont.title2)
                    .foregroundStyle(SlipColor.ink)
                Text(label)
                    .font(SlipFont.footnote)
                    .foregroundStyle(SlipColor.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: SlipSize.minimumTap, alignment: .leading)
        }
    }
}

private enum ProfileHistoryAccessory {
    case sealed
    case score(String)
}

private struct ProfileHistoryRow: View {
    let question: String
    let detail: String
    let palette: Int
    let accessory: ProfileHistoryAccessory
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                        HStack {
                            CrewArt(size: SlipSize.art, palette: palette)
                            Spacer(minLength: SlipSpacing.standard)
                            historyAccessory
                        }
                        historyLabels
                    }
                } else {
                    HStack(spacing: SlipSpacing.medium) {
                        CrewArt(size: SlipSize.art, palette: palette)
                        historyLabels
                        Spacer(minLength: SlipSpacing.small)
                        historyAccessory
                    }
                }
            }
            .padding(.horizontal, SlipSpacing.standard)
            .padding(.vertical, SlipSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var historyLabels: some View {
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
    }

    @ViewBuilder private var historyAccessory: some View {
        switch accessory {
        case .sealed:
            SealGlyph()
        case .score(let score):
            Text(score)
                .font(SlipFont.title3Bold)
                .foregroundStyle(SlipColor.win)
        }
    }
}

private struct ProfileSettingRow: View {
    let title: String
    let detail: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SlipSpacing.small) {
                        Text(title).font(SlipFont.body).foregroundStyle(SlipColor.ink)
                        HStack(spacing: SlipSpacing.small) {
                            Text(detail).font(SlipFont.subheadline).foregroundStyle(SlipColor.secondary)
                            Spacer(minLength: SlipSpacing.small)
                            Image(systemName: "chevron.right")
                                .font(SlipFont.footnoteBold)
                                .foregroundStyle(SlipColor.secondary)
                        }
                    }
                } else {
                    HStack(spacing: SlipSpacing.medium) {
                        Text(title).font(SlipFont.body).foregroundStyle(SlipColor.ink)
                        Spacer(minLength: SlipSpacing.small)
                        Text(detail).font(SlipFont.subheadline).foregroundStyle(SlipColor.secondary)
                        Image(systemName: "chevron.right")
                            .font(SlipFont.footnoteBold)
                            .foregroundStyle(SlipColor.secondary)
                    }
                }
            }
            .padding(SlipSpacing.standard)
            .frame(minHeight: SlipSize.minimumTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CrewMember: Identifiable, Sendable {
    let name: String
    let detail: String
    let score: String

    var id: String { name }

    static let preview = [
        CrewMember(name: "Ana", detail: "4 of 4 this week", score: "12"),
        CrewMember(name: "You", detail: "3 of 4", score: "10"),
        CrewMember(name: "Raj", detail: "2 of 4", score: "7"),
        CrewMember(name: "Maya", detail: "2 of 4", score: "6"),
        CrewMember(name: "Tomás", detail: "1 of 4", score: "4")
    ]
}

private enum CrewMetrics {
    static let saturdayPalette = 0
    static let officePalette = 1
    static let bookPalette = 2
    static let lastItemOffset = 1
    static let summaryRowHeight: CGFloat = 80
    static let summaryDividerInset: CGFloat = SlipSize.art + SlipSpacing.standard * 2
    static let historyDividerInset: CGFloat = SlipSize.art + SlipSpacing.standard * 2
}
