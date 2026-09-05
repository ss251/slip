import SwiftUI

struct NewSlipScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var firstSide = "Yes"
    @State private var draftQuestion = PreviewContent.question
    @State private var secondSide = "No"
    @State private var sealDate = CreationDefaults.nextFriday(hour: CreationDefaults.sealHour)
    @State private var openDate = CreationDefaults.nextFriday(hour: CreationDefaults.openHour)
    @State private var editedDate: CreationDateField?

    var body: some View {
        ScrollView {
            VStack(spacing: SlipSpacing.large) {
                VStack(spacing: SlipSpacing.small) {
                    creationHeader
                    crewArt
                }

                TextField("Ask your crew something", text: $draftQuestion, axis: .vertical)
                    .font(SlipFont.title)
                    .foregroundStyle(SlipColor.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(CreationMetrics.questionLineRange)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .accessibilityLabel("Slip question")

                sideEditors
                scheduleCard
                crewPicker
            }
            .padding(.horizontal, SlipSpacing.screen)
            .padding(.top, SlipSpacing.small)
            .padding(.bottom, SlipSpacing.large)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            BottomActions {
                PillButton(title: "Create slip") {
                    createLocalPreview()
                }
                Text("Your crew gets an invite. Picks stay sealed until it opens.")
                    .font(SlipFont.footnote)
                    .foregroundStyle(SlipColor.secondary)
                    .multilineTextAlignment(.center)
            }
            .background(SlipColor.background)
        }
        .sheet(item: $editedDate) { field in
            CreationDateEditor(
                field: field,
                selection: dateBinding(for: field),
                dismiss: { editedDate = nil }
            )
        }
        .accessibilityIdentifier("new-slip")
    }

    private var creationHeader: some View {
        FormHeading(title: "New slip", cancel: model.back)
    }

    private var crewArt: some View {
        CrewArt(size: CreationMetrics.newSlipArtSize)
    }

    @ViewBuilder private var sideEditors: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: SlipSpacing.small) {
                SideEditor(label: "First side", text: $firstSide, expands: true)
                Text("or").font(SlipFont.body).foregroundStyle(SlipColor.secondary)
                SideEditor(label: "Second side", text: $secondSide, expands: true)
            }
        } else {
            HStack(spacing: SlipSpacing.small) {
                SideEditor(label: "First side", text: $firstSide, expands: false)
                Text("or").font(SlipFont.body).foregroundStyle(SlipColor.secondary)
                SideEditor(label: "Second side", text: $secondSide, expands: false)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var scheduleCard: some View {
        SlipCard(padding: SlipSpacing.tiny) {
            VStack(spacing: SlipSpacing.zero) {
                CreationScheduleRow(
                    title: "Seal by",
                    date: sealDate,
                    filledMarker: true
                ) {
                    editedDate = .seal
                }
                CreationScheduleRow(
                    title: "Opens",
                    date: openDate,
                    filledMarker: false
                ) {
                    editedDate = .open
                }
            }.padding(.horizontal, SlipSpacing.medium)
        }
    }

    private var crewPicker: some View {
        Button {
            model.go(.crews)
        } label: {
            SlipCard {
                HStack(spacing: SlipSpacing.medium) {
                    Image(systemName: "person.2")
                        .font(SlipFont.headline)
                    Text("Saturday crew")
                        .font(SlipFont.body)
                    Spacer(minLength: SlipSpacing.small)
                    if !typeSize.isAccessibilitySize { CreationAvatarStack() }
                    Image(systemName: "chevron.right")
                        .font(SlipFont.footnoteBold)
                        .foregroundStyle(SlipColor.secondary)
                }
                .foregroundStyle(SlipColor.ink)
            }
            .contentShape(RoundedRectangle(cornerRadius: SlipRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose a crew")
    }

    private func dateBinding(for field: CreationDateField) -> Binding<Date> {
        Binding {
            field == .seal ? sealDate : openDate
        } set: { value in
            if field == .seal {
                sealDate = value
            } else {
                openDate = value
            }
        }
    }

    private func createLocalPreview() {
        let question = draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = firstSide.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = secondSide.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !question.isEmpty, !first.isEmpty, !second.isEmpty else {
            model.inform("Add a question and two sides before creating the slip.")
            return
        }
        guard first.localizedCaseInsensitiveCompare(second) != .orderedSame else {
            model.inform("Give the two sides different names.")
            return
        }
        guard openDate > sealDate else {
            model.inform("The opening time needs to be after the sealing deadline.")
            return
        }
        if let failure = LocalSealingService.deadlineError(for: sealDate, relativeTo: Date()) {
            model.inform(failure.displayName)
            return
        }

        model.startLocalRound(question: question, sides: [first, second], crewName: "Saturday crew", sealDeadline: sealDate)
        model.inform("Saved as a local preview. Invites are not sent until the network flow is connected.")
        model.go(.room)
    }
}

private struct SideEditor: View {
    let label: String
    @Binding var text: String
    let expands: Bool

    var body: some View {
        TextField(label, text: $text)
            .font(SlipFont.headline)
            .foregroundStyle(SlipColor.ink)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.sentences)
            .padding(.horizontal, SlipSpacing.standard)
            .frame(
                minWidth: expands ? nil : CreationMetrics.sideEditorWidth,
                maxWidth: expands ? .infinity : CreationMetrics.sideEditorWidth,
                minHeight: SlipSize.minimumTap
            )
            .background(SlipColor.fill, in: Capsule())
            .accessibilityLabel(label)
    }
}

private struct CreationScheduleRow: View {
    let title: String
    let date: Date
    let filledMarker: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SlipSpacing.medium) {
                Circle()
                    .fill(filledMarker ? SlipColor.ink : SlipColor.clear)
                    .overlay {
                        if !filledMarker {
                            Circle().stroke(SlipColor.ink, lineWidth: SlipStroke.emphasis)
                        }
                    }
                    .frame(width: SlipSize.smallIcon, height: SlipSize.smallIcon)

                Text(title)
                    .font(SlipFont.body)
                    .foregroundStyle(SlipColor.secondary)

                Spacer(minLength: SlipSpacing.small)

                Text(CreationDefaults.display(date))
                    .font(SlipFont.bodyBold)
                    .foregroundStyle(SlipColor.ink)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: SlipSize.minimumTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CreationAvatarStack: View {
    private let names = ["Ana", "Raj", "Maya"]

    var body: some View {
        HStack(spacing: -SlipSpacing.small) {
            ForEach(names, id: \.self) { name in
                InitialAvatar(name: name, size: SlipSize.sealMark)
                    .overlay(Circle().stroke(SlipColor.card, lineWidth: SlipStroke.emphasis))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ana, Raj, and Maya")
    }
}

private enum CreationDateField: String, Identifiable {
    case seal = "Seal by"
    case open = "Opens"

    var id: String { rawValue }
}

private struct CreationDateEditor: View {
    let field: CreationDateField
    @Binding var selection: Date
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: SlipSpacing.large) {
            HStack {
                Text(field.rawValue)
                    .font(SlipFont.title2)
                    .foregroundStyle(SlipColor.ink)
                Spacer(minLength: SlipSpacing.standard)
                Button("Done", action: dismiss)
                    .font(SlipFont.headline)
                    .foregroundStyle(SlipColor.ink)
                    .frame(minHeight: SlipSize.minimumTap)
            }

            DatePicker(
                field.rawValue,
                selection: $selection,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(SlipColor.ink)
        }
        .padding(SlipSpacing.screen)
        .background(SlipColor.background)
        .presentationDetents([.medium, .large])
    }
}

struct InviteScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            ArtBackdrop()

            ScrollView {
                VStack(spacing: SlipSpacing.large) {
                    Spacer(minLength: typeSize.isAccessibilitySize ? SlipSpacing.large : SlipSpacing.extraRoomy)
                    CrewArt(size: SlipSize.artHero)

                    VStack(spacing: SlipSpacing.small) {
                        Text("Ana invited you to")
                            .font(SlipFont.body)
                            .foregroundStyle(SlipColor.secondary)
                        Text("Saturday crew")
                            .font(SlipFont.large)
                            .foregroundStyle(SlipColor.ink)
                    }

                    HStack(spacing: SlipSpacing.medium) {
                        if !typeSize.isAccessibilitySize { CreationAvatarStack() }
                        Text("Ana, Raj, Maya and 1 more")
                            .font(SlipFont.subheadline)
                            .foregroundStyle(SlipColor.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: SlipSpacing.medium) {
                        Text("Waiting for you")
                            .font(SlipFont.subheadlineBold)
                            .foregroundStyle(SlipColor.secondary)

                        Button {
                            model.inform("Join the crew before sealing its open slip.")
                        } label: {
                            SlipCard {
                                HStack(spacing: SlipSpacing.medium) {
                                    SealStatusTag()
                                    VStack(alignment: .leading, spacing: SlipSpacing.tiny) {
                                        Text(model.sampleQuestion)
                                            .font(SlipFont.headline)
                                            .foregroundStyle(SlipColor.ink)
                                            .multilineTextAlignment(.leading)
                                        Text("3 of 5 sealed · seal by Fri 20:00")
                                            .font(SlipFont.subheadline)
                                            .foregroundStyle(SlipColor.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: SlipRadius.card))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, SlipSpacing.large)

                    Text("Sealed on your own iPhone, opened together. Nobody reads a pick early.")
                        .font(SlipFont.footnote)
                        .foregroundStyle(SlipColor.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, SlipSpacing.standard)

                    Spacer(minLength: SlipSpacing.expansive)
                }
                .padding(.horizontal, SlipSpacing.screen)
                .padding(.bottom, SlipSpacing.large)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActions {
                PillButton(title: "Join Saturday crew") {
                    model.inform("Joined for this local preview. No network request was sent.")
                    model.go(.seal)
                }
                Button("Not now") {
                    model.back()
                }
                .font(SlipFont.headline)
                .foregroundStyle(SlipColor.secondary)
                .frame(maxWidth: .infinity, minHeight: SlipSize.minimumTap)
            }
            .background(SlipColor.background)
        }
        .accessibilityIdentifier("invite")
    }
}

private enum CreationDefaults {
    static let sealHour = 20
    static let openHour = 21
    static let friday = 6

    static func nextFriday(hour: Int) -> Date {
        var components = DateComponents()
        components.weekday = friday
        components.hour = hour
        components.minute = 0
        return Calendar.autoupdatingCurrent.nextDate(
            after: .now,
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        ) ?? .now
    }

    static func display(_ date: Date) -> String {
        SlipDateText.weekdayTime(date)
    }
}

private enum CreationMetrics {
    static let newSlipArtSize: CGFloat = 132
    static let sideEditorWidth: CGFloat = 104
    static let questionLineRange = 1...3
}
