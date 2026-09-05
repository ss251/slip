import MidnightKit
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

                VStack(spacing: SlipSpacing.standard) {
                        CrewSummaryRow(
                            name: "Saturday crew",
                            people: "5 people",
                            slips: "6 slips",
                            status: "Seal by Fri"
                        ) {
                            model.go(.crewDetail)
                        }
                        CrewSummaryRow(
                            name: "Office pool",
                            people: "9 people",
                            slips: "14 slips",
                            status: "Opens 17:00"
                        ) {
                            model.inform("Only the Saturday crew is wired into this local preview.")
                        }
                        CrewSummaryRow(
                            name: "Book club",
                            people: "4 people",
                            slips: "2 slips",
                            status: "Quiet"
                        ) {
                            model.inform("Only the Saturday crew is wired into this local preview.")
                        }
                    }

                Button {
                    model.go(.invite)
                } label: {
                    SlipCard {
                        HStack(spacing: SlipSpacing.medium) {
                            Image(systemName: "square.and.arrow.up")
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
                .buttonStyle(SlipPressStyle())

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
    let people: String
    let slips: String
    let status: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: SlipSpacing.medium) {
                if !typeSize.isAccessibilitySize { CrewArt(size: SlipSize.art, crewID: name) }
                VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                    HStack(alignment: .firstTextBaseline, spacing: SlipSpacing.small) {
                        Text(name).font(SlipFont.headline).foregroundStyle(SlipColor.ink)
                        Spacer(minLength: SlipSpacing.tiny)
                        Text(status).font(SlipFont.footnote).foregroundStyle(SlipColor.secondary)
                    }
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: SlipSpacing.tiny))
                        : AnyLayout(HStackLayout(spacing: SlipSpacing.small))
                    layout {
                        RowMetadata(symbol: "person.2", text: people)
                        RowMetadata(symbol: "doc", text: slips)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, SlipSpacing.medium)
            .frame(minHeight: CrewMetrics.summaryRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(SlipPressStyle())
    }

}

struct CrewDetailScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            ArtBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: SlipSpacing.zero) {
                    toolbar
                    identity.padding(.top, SlipSpacing.tiny)
                    openSlip.padding(.top, SlipSpacing.large)
                    members.padding(.top, SlipSpacing.large)
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
            .buttonStyle(SlipPressStyle())
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
            .buttonStyle(SlipPressStyle())
            .accessibilityLabel("Share crew")
        }
    }

    private var identity: some View {
        VStack(spacing: SlipSpacing.small) {
            CrewArt(size: SlipSize.artLarge)
                .padding(.bottom, SlipSpacing.medium)
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
                    .overlay { CrewCapsuleBorder() }
            }
            .buttonStyle(SlipPressStyle())
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
                openSlipLabels
                    .padding(.vertical, SlipSpacing.medium)
                    .frame(maxWidth: .infinity, minHeight: SlipSize.minimumTap, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SlipPressStyle())
            .accessibilityLabel(RowAccessibility.slip(
                question: model.sampleQuestion,
                crew: PreviewContent.crew,
                status: RowAccessibility.sealStatus(sealed: false),
                metadata: "Seal by Fri 20:00 · 3 of 5 sealed"
            ))
        }
    }

    private var openSlipLabels: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
            CrewIdentityLine(crew: PreviewContent.crew) {
                SealStatusTag(sealed: false)
            }
            Text(model.sampleQuestion)
                .font(SlipFont.headline)
                .foregroundStyle(SlipColor.ink)
                .lineLimit(typeSize.isAccessibilitySize ? nil : SlipSize.questionLines)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            RowMetadata(symbol: "clock", text: "Seal by Fri 20:00 · 3 of 5 sealed")
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
    @Environment(NetworkSealTracker.self) private var networkTracker: NetworkSealTracker?
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SlipSpacing.screen) {
                    profileHeader
                    profileIdentity
                    stats
                    history
                        .padding(.top, SlipSpacing.tiny)
                    settings
                    ProfileFooter()
                }
                .padding(.horizontal, SlipSpacing.screen)
                .padding(.top, SlipSpacing.large)
                // Root scroll chrome already supplies the remaining 8pt of clearance.
                .padding(.bottom, SlipSpacing.standard)
                .id("profile-footer")
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("you")
            #if DEBUG
            .task {
                // Review-only scrolling uses synthetic preview data and no animation.
                if model.isPreview && ProcessInfo.processInfo.arguments.contains("--profile-footer") {
                    proxy.scrollTo("profile-footer", anchor: .bottom)
                }
            }
            #endif
        }
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
            .overlay { CrewCapsuleBorder() }
            .buttonStyle(SlipPressStyle())
        }
    }

    private var profileIdentity: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SlipSpacing.standard) {
                    InitialAvatar(name: "You", size: SlipSize.avatarLarge)
                    profileLabels
                }
            } else {
                HStack(spacing: SlipSpacing.standard) {
                    InitialAvatar(name: "You", size: SlipSize.avatarLarge)
                    profileLabels
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var profileLabels: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
            Text("Sailesh")
                .font(SlipFont.title2)
                .foregroundStyle(SlipColor.ink)
            Text("3 crews · sealing since June")
                .font(SlipFont.subheadline)
                .foregroundStyle(SlipColor.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
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
                        crew: "Saturday crew",
                        detail: "Opens Fri 21:00",
                        accessory: .sealed
                    ) {
                        model.go(.room)
                    }
                    InsetDivider(inset: CrewMetrics.historyDividerInset)
                    ProfileHistoryRow(
                        question: "Does the demo survive the all-hands?",
                        crew: "Office pool",
                        detail: "Yes · opens today 17:00",
                        accessory: .sealed
                    ) {
                        model.go(.room)
                    }
                    InsetDivider(inset: CrewMetrics.historyDividerInset)
                    ProfileHistoryRow(
                        question: "Will Raj actually ship this week?",
                        crew: "Saturday crew",
                        detail: "No · called it",
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
                ProfileSettingRow(title: "Notifications", symbol: "bell", detail: "Opens and nudges") {
                    model.inform("Notification settings open after app permissions are connected.")
                }
                InsetDivider(inset: SlipSpacing.standard)
                ProfileSettingRow(title: "Appearance", symbol: "circle.lefthalf.filled", detail: "Match iPhone") {
                    model.inform("Slip currently follows your iPhone appearance.")
                }
                InsetDivider(inset: SlipSpacing.standard)
                ProfileSettingRow(title: "Your receipts", symbol: "doc.text", detail: "Every proof this iPhone made") {
                    model.inform("Receipt history is local-only and will appear after you seal a pick.")
                }
                InsetDivider(inset: SlipSpacing.standard)
                ProfileSettingRow(title: "Steward relay", symbol: "antenna.radiowaves.left.and.right", detail: networkTracker?.relayHost ?? "Not connected") {
                    model.inform(networkTracker?.relayHost == nil ? "Launch with --relay and --contract, or ask your steward for a setup link." : "Sealed picks are handed to this steward, who pays the fee and posts them.")
                }
                InsetDivider(inset: SlipSpacing.standard)
                ProfileSettingRow(title: "Your member id", symbol: "person.crop.square", detail: networkTracker?.memberIDHex.map { "\($0.prefix(6))…\($0.suffix(4))" } ?? "Made when you connect", machine: networkTracker?.memberIDHex != nil) {
                    if let id = networkTracker?.memberIDHex {
                        UIPasteboard.general.string = id
                        model.inform("Copied. Send it to your steward to be enrolled — it reveals nothing about your picks.")
                    } else {
                        model.inform("Your member id appears once a steward relay is set up.")
                    }
                }
            }
        }
    }
}

private struct ProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        SlipCard(padding: SlipSpacing.zero) {
            VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                Text(value)
                    .font(SlipFont.title2)
                    .foregroundStyle(SlipColor.ink)
                Text(label)
                    .font(SlipFont.footnote)
                    .foregroundStyle(SlipColor.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: CrewMetrics.profileStatContentHeight, alignment: .leading)
            .padding(.horizontal, SlipSpacing.standard)
            .padding(.vertical, SlipSpacing.medium)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RowAccessibility.statistic(value: value, label: label))
    }
}

private enum ProfileHistoryAccessory {
    case sealed
    case score(String)
}

private struct ProfileHistoryRow: View {
    let question: String
    let crew: String
    let detail: String
    let accessory: ProfileHistoryAccessory
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                        HStack {
                            CrewArt(size: SlipSize.artSmall, crewID: crew)
                            Spacer(minLength: SlipSpacing.standard)
                        }
                        historyLabels
                    }
                } else {
                    HStack(spacing: SlipSpacing.medium) {
                        CrewArt(size: SlipSize.artSmall, crewID: crew)
                        historyLabels.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, SlipSpacing.standard)
            .padding(.vertical, SlipSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(SlipPressStyle())
        .accessibilityLabel(RowAccessibility.slip(question: question, crew: crew, status: spokenStatus, metadata: detail))
    }

    private var spokenStatus: String {
        switch accessory {
        case .sealed: RowAccessibility.sealStatus(sealed: true)
        case .score(let score): RowAccessibility.points(score)
        }
    }

    private var historyLabels: some View {
        VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
            CrewIdentityLine(crew: crew) { historyAccessory }
            Text(question)
                .font(SlipFont.headline)
                .foregroundStyle(SlipColor.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(typeSize.isAccessibilitySize ? nil : SlipSize.questionLines)
            RowMetadata(symbol: "clock", text: detail)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var historyAccessory: some View {
        switch accessory {
        case .sealed:
            SealStatusTag()
        case .score(let score):
            Text(score)
                .font(SlipFont.footnote)
                .foregroundStyle(SlipColor.win)
        }
    }
}

private struct ProfileSettingRow: View {
    let title: String
    let symbol: String
    let detail: String
    var machine: Bool = false
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: SlipSpacing.medium) {
                Image(systemName: symbol).resizable().scaledToFit()
                    .foregroundStyle(SlipColor.secondary)
                    .frame(width: SlipSize.icon, height: SlipSize.icon)
                    .accessibilityHidden(true)
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: SlipSpacing.small))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: SlipSpacing.medium))
                layout {
                    Text(title).font(SlipFont.body).foregroundStyle(SlipColor.ink)
                        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                        .layoutPriority(SlipPriority.primary)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: SlipSpacing.tiny) }
                    Text(detail).font(machine ? SlipFont.machine : SlipFont.footnote)
                        .foregroundStyle(SlipColor.secondary)
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(SlipFont.footnoteBold)
                    .foregroundStyle(SlipColor.secondary).accessibilityHidden(true)
            }
            .padding(SlipSpacing.standard)
            .frame(minHeight: SlipSize.minimumTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(SlipPressStyle())
    }
}

private struct ProfileFooter: View {
    var body: some View {
        VStack(spacing: SlipSpacing.tiny) {
            Text("Slip").font(SlipFont.footnote).opacity(SlipOpacity.wordmark)
            Text(version).font(SlipFont.caption)
            Text("Terms · Privacy").font(SlipFont.caption)
        }
        .foregroundStyle(SlipColor.secondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, SlipSpacing.large)
        .accessibilityElement(children: .combine)
    }

    private var version: String {
        // Generated development builds omit Apple's version keys when their build
        // settings are empty. Prefer release metadata, then the local app metadata.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "SlipDevelopmentVersion") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "SlipDevelopmentBuild") as? String
        guard let version, let build else {
            return "Development build"
        }
        return "Version \(version) (\(build))"
    }
}

private struct CrewCapsuleBorder: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility

    var body: some View {
        if contrast == .increased || accessibility.increaseContrast {
            Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis)
        }
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
    static let lastItemOffset = 1
    static let summaryRowHeight: CGFloat = 80
    static let profileStatContentHeight: CGFloat = 50
    static let summaryDividerInset: CGFloat = SlipSize.art + SlipSpacing.standard * 2
    static let historyDividerInset: CGFloat = SlipSize.artSmall + SlipSpacing.standard + SlipSpacing.medium
}
