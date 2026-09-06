import MidnightKit
import SwiftUI

struct SealScreen: View {
    var mode: SlipScreen = .seal
    @Environment(AppModel.self) private var model
    @Environment(SealFlowModel.self) private var flow
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.slipAccessibility) private var accessibility
    @State private var hold = SealHold()
    @State private var peek = PickPeekState()
    @State private var peekTask: Task<Void, Never>?
    @State private var accessibleHold: Task<Void, Never>?
    @State private var displayedRoundID: UUID?
    private var proving: Bool { mode == .sealing || (flow.stage == .proving && flow.activeRoundID == model.localRound.id) }
    private var failed: Bool { mode == .proofFailed || (flow.stage == .failed && flow.activeRoundID == model.localRound.id) }
    private var already: Bool { mode == .alreadySealed || model.hasLocalSeal }
    private var canPeek: Bool { already && (model.isPreview || flow.sealedDisplay?.roundID == model.localRound.id) }
    private var holdAccessibility: SealHoldAccessibility { SealHoldAccessibility(isPending: accessibleHold != nil) }
    private var displayedChoice: String {
        if already, let display = flow.sealedDisplay, display.roundID == model.localRound.id { return display.selectedSide }
        return model.selectedSide
    }

    var body: some View {
        VStack(spacing: SlipSpacing.zero) {
            ScrollView {
                VStack(spacing: SlipSpacing.screen) {
                    SheetHeading(title: already ? "Already sealed" : proving ? "Sealing" : "Seal your pick", light: true)
                    ContextRow(detail: model.isPreview ? "3 of 5 sealed" : "local proof only", light: true,
                               crewID: model.isPreview ? PreviewContent.crew : model.localRound.crewName,
                               symbol: model.isPreview ? "person.2" : "iphone")
                    pickCard.padding(.horizontal, typeSize.isAccessibilitySize ? SlipSpacing.zero : SlipSpacing.medium)
                    if already {
                        explanation("You sealed this on this iPhone", "A sealed pick can’t be changed or sealed twice. That’s the whole point.")
                    } else if failed {
                        explanation("Couldn’t finish the proof", "It stopped partway. Nothing left this phone; your pick is still only here.")
                        if let failure = flow.failure {
                            Text(failure.displayName).font(SlipFont.machine).foregroundStyle(SlipColor.onTicket)
                                .accessibilityLabel("Error: \(failure.displayName)")
                        }
                    } else if proving {
                        VStack(spacing: SlipSpacing.medium) {
                            Text("Proving on this iPhone").font(SlipFont.headline)
                            ProgressView().tint(SlipColor.onSeal).accessibilityLabel("Making your proof")
                            Text("Nothing leaves until it’s done.").font(SlipFont.footnote).foregroundStyle(SlipColor.onTicket)
                        }.padding(.top, SlipSpacing.medium)
                    } else {
                        choices.padding(.horizontal, typeSize.isAccessibilitySize ? SlipSpacing.zero : SlipSpacing.medium)
                        Text("Your sealed pick stays on this iPhone. You can still peek at it.")
                            .font(SlipFont.footnote).foregroundStyle(SlipColor.onTicket).multilineTextAlignment(.center)
                    }
                }.padding(.horizontal, SlipSpacing.large)
                    .padding(.bottom, SlipSpacing.large)
            }
            .clipped()
            bottom
        }
        .background { AmbientBackground(crewID: model.isPreview ? PreviewContent.crew : model.localRound.crewName) }
        .foregroundStyle(SlipColor.onSeal)
        .preferredColorScheme(.dark)
        .onAppear { displayedRoundID = model.localRound.id }
        .onDisappear {
            cancelAccessibleHold(); concealPick()
            if let displayedRoundID { flow.depart(roundID: displayedRoundID) }
        }
        .onChange(of: flow.stage) { _, stage in
            if stage != .choosing { cancelAccessibleHold() }
            guard stage == .sealed, flow.receipt?.roundID == model.localRound.id,
                  model.screen == .seal || model.screen == .sealing else { return }
            model.markLocalSeal(roundID: model.localRound.id)
            model.go(.ticket)
        }
        .onChange(of: model.screen) { _, _ in cancelAccessibleHold(); concealPick() }
        .onChange(of: model.selectedSide) { _, _ in cancelAccessibleHold() }
        .onChange(of: model.localRound.id) { oldID, newID in
            flow.depart(roundID: oldID)
            displayedRoundID = newID
            cancelAccessibleHold(); concealPick()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cancelAccessibleHold(); concealPick()
                flow.depart(roundID: model.localRound.id)
            }
        }
    }

    private var pickCard: some View {
        VStack(spacing: SlipSpacing.medium) {
            Text("Your pick").font(SlipFont.footnoteBold).foregroundStyle(SlipColor.secondary)
            Text(already && !peek.isVisible ? "•••" : displayedChoice)
                .font(SlipFont.large).foregroundStyle(SlipColor.ink.opacity(proving ? SlipOpacity.muted : SlipOpacity.opaque))
                .accessibilityLabel(already && !peek.isVisible ? "Your pick is concealed" : "Your pick: \(displayedChoice)")
            if !already { Text("Only you can see this").font(SlipFont.footnote).foregroundStyle(SlipColor.secondary) }
            Group {
                if already {
                    SealMark(size: SlipSize.sealDisc)
                } else {
                    TimelineView(.animation(paused: hold.began == nil)) { context in
                        Circle().stroke(SlipColor.separator, lineWidth: SlipStroke.emphasis)
                            .overlay {
                                Circle().trim(from: SlipSpacing.zero, to: proving ? SlipOpacity.opaque : hold.progress(at: context.date.timeIntervalSinceReferenceDate))
                                    .fill(SlipColor.seal)
                            }
                            .frame(width: SlipSize.largeIcon, height: SlipSize.largeIcon)
                    }
                }
            }.padding(.top, SlipSpacing.medium)
            if already { Text("Hold to peek").font(SlipFont.footnoteBold).foregroundStyle(SlipColor.secondary) }
        }
        .padding(SlipSpacing.large)
        .frame(maxWidth: .infinity, minHeight: SlipSize.choiceCardHeight)
        .background(SlipColor.onSeal, in: RoundedRectangle(cornerRadius: SlipRadius.largeCard))
        .overlay { if contrast == .increased || accessibility.increaseContrast {
            RoundedRectangle(cornerRadius: SlipRadius.largeCard).stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis)
        } }
        .environment(\.colorScheme, .light)
        .onLongPressGesture(minimumDuration: SlipMotion.pressDuration, pressing: { pressing in
            if canPeek {
                peekTask?.cancel(); peekTask = nil
                peek.touch(pressing: pressing)
            }
        }, perform: {})
        .modifier(SealedPickAccessibilityModifier(enabled: canPeek,
            semantics: SealedPickAccessibility(isVisible: peek.isVisible, choice: displayedChoice),
            activate: { temporaryPeek(toggle: true) }, show: { temporaryPeek() }, conceal: concealPick))
    }

    private var choices: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: SlipSpacing.small))
            : AnyLayout(HStackLayout(spacing: SlipSpacing.small))
        return layout {
            ForEach(model.sideLabels, id: \.self) { side in
                Button { model.selectedSide = side } label: {
                    Text(side).font(SlipFont.headline)
                        .foregroundStyle(model.selectedSide == side ? SlipColor.ink : SlipColor.onSeal)
                        .frame(maxWidth: .infinity, minHeight: SlipSize.compactButtonHeight)
                        .background(model.selectedSide == side ? SlipColor.onSeal : (reduceTransparency || accessibility.reduceTransparency) ? SlipColor.opaqueChoice : SlipColor.onSeal.opacity(SlipOpacity.subtle),
                                    in: RoundedRectangle(cornerRadius: SlipRadius.control))
                        .overlay {
                            if contrast == .increased || accessibility.increaseContrast
                                || (model.selectedSide != side && (reduceTransparency || accessibility.reduceTransparency)) {
                                RoundedRectangle(cornerRadius: SlipRadius.control)
                                    .stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis)
                                    .environment(\.colorScheme, .dark)
                            }
                        }
                }.buttonStyle(SlipPressStyle()).environment(\.colorScheme, .light)
                    .accessibilityAddTraits(model.selectedSide == side ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var bottom: some View {
        BottomActions(background: SlipColor.clear) {
            if already {
                PillButton(title: "See your ticket", tone: .white) { model.go(.ticket) }
            } else if failed {
                PillButton(title: "Try again", tone: .white) { flow.chooseAgain(); model.screen = .seal }
                Button("Change my pick") { flow.chooseAgain(); model.screen = .seal }.font(SlipFont.subheadlineBold)
                    .frame(minHeight: SlipSize.minimumTap).foregroundStyle(SlipColor.onTicket)
            } else if proving {
                PillButton(title: "Sealing…", tone: .seal) {}.disabled(true).opacity(SlipOpacity.strong)
            } else {
                Text(model.isPreview ? "Seal by Friday 20:00" : "Seal by \(SlipDateText.weekdayTime(model.localRound.sealDeadline))").font(SlipFont.footnoteBold)
                Text(hold.began == nil ? "Hold to seal" : "Keep holding…").font(SlipFont.headline)
                    .frame(maxWidth: .infinity, minHeight: SlipSize.buttonHeight)
                    .background(SlipColor.seal, in: Capsule()).contentShape(Capsule())
                    .overlay {
                        if contrast == .increased || accessibility.increaseContrast {
                            Capsule().stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis)
                                .environment(\.colorScheme, .dark)
                        }
                    }
                    .scaleEffect(hold.began != nil && !(reduceMotion || accessibility.reduceMotion) ? SlipMotion.pressScale : SlipOpacity.opaque)
                    .animation(reduceMotion || accessibility.reduceMotion ? nil : .easeOut(duration: SlipMotion.pressDuration), value: hold.began != nil)
                    .onLongPressGesture(minimumDuration: SlipMotion.holdDuration, maximumDistance: SlipSize.minimumTap,
                        pressing: { pressing in
                            if pressing {
                                cancelAccessibleHold()
                                hold.start(at: Date.timeIntervalSinceReferenceDate)
                            }
                            else { hold.cancel() }
                        }, perform: { beginSeal() })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(holdAccessibility.label)
                    .accessibilityValue(holdAccessibility.value)
                    .accessibilityHint(holdAccessibility.hint)
                    .accessibilityAction { accessibleConfirm() }
                    .accessibilityAction(named: Text(holdAccessibility.sealActionName)) { startAccessibleHold() }
                    .accessibilityAction(named: Text(holdAccessibility.cancelActionName)) { cancelAccessibleHold() }
                Text("A sealed pick can’t be changed.").font(SlipFont.footnote).foregroundStyle(SlipColor.onTicket)
            }
        }.environment(\.colorScheme, .light)
    }

    private func explanation(_ title: String, _ detail: String) -> some View {
        VStack(spacing: SlipSpacing.small) {
            Text(title).font(SlipFont.headline)
            Text(detail).font(SlipFont.footnote).foregroundStyle(SlipColor.onTicket)
        }.multilineTextAlignment(.center).padding(.top, SlipSpacing.medium)
    }

    private func beginSeal() {
        cancelAccessibleHold()
        flow.beginSeal(round: model.localRound, choice: model.selectedSide == model.sideLabels.first ? 1 : 0)
    }

    private func accessibleConfirm() {
        if accessibleHold != nil { cancelAccessibleHold(); return }
        startAccessibleHold()
    }

    private func startAccessibleHold() {
        guard accessibleHold == nil, !already, !proving, !failed, scenePhase == .active else { return }
        let roundID = model.localRound.id
        let choice = model.selectedSide
        hold.start(at: Date.timeIntervalSinceReferenceDate)
        accessibleHold = Task {
            try? await Task.sleep(for: .seconds(SlipMotion.holdDuration))
            guard !Task.isCancelled else { return }
            guard model.localRound.id == roundID, model.selectedSide == choice,
                  scenePhase == .active, !already, !proving, !failed else {
                cancelAccessibleHold()
                return
            }
            beginSeal()
        }
    }

    private func cancelAccessibleHold() {
        accessibleHold?.cancel(); accessibleHold = nil
        hold.cancel()
    }

    private func temporaryPeek(toggle: Bool = false) {
        guard canPeek, scenePhase == .active else { return }
        guard toggle || !peek.isVisible else { return }
        peekTask?.cancel(); peekTask = nil
        let expiry = toggle ? peek.activate() : peek.show()
        guard let expiryID = expiry else { return }
        peekTask = Task {
            try? await Task.sleep(for: .seconds(SlipMotion.holdDuration))
            guard !Task.isCancelled else { return }
            peek.expire(expiryID)
            peekTask = nil
        }
    }

    private func concealPick() {
        peekTask?.cancel(); peekTask = nil
        peek.conceal()
    }
}

struct AmbientBackground: View {
    var crewID: String = PreviewContent.crew
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.slipAccessibility) private var accessibility

    var body: some View {
        ZStack {
            SlipColor.ambient
            if !(reduceTransparency || accessibility.reduceTransparency) {
                ArtField(crewID: crewID)
                    .blur(radius: SlipSize.ambientBlur, opaque: true)
                    .scaleEffect(SlipSize.ambientArtScale)
                    .opacity(SlipOpacity.ambientWash)
                SlipColor.ambient.opacity(SlipOpacity.ambientOverlay)
                SlipColor.ticket.opacity(SlipOpacity.ambientShade)
            }
        }.clipped().ignoresSafeArea()
    }
}

struct TicketScreen: View {
    var postingLater = false
    @Environment(AppModel.self) private var model
    @Environment(SealFlowModel.self) private var flow
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.slipAccessibility) private var accessibility
    @State private var peek = PickPeekState()
    @State private var peekTask: Task<Void, Never>?
    @State private var stamped = false
    private var sealedDisplay: LocalSealedDisplay? {
        flow.sealedDisplay?.roundID == model.localRound.id ? flow.sealedDisplay : nil
    }
    private var sealedChoice: String { sealedDisplay?.selectedSide ?? (model.isPreview ? model.selectedSide : "Unavailable") }
    private var receipt: LocalSealReceipt? { flow.receipt?.roundID == model.localRound.id ? flow.receipt : nil }
    @Environment(NetworkSealTracker.self) private var networkTracker: NetworkSealTracker?
    private var networkReceipt: NetworkSealReceipt? { networkTracker?.receipt(for: model.localRound.id) }
    private var networkConfirmation: ConfirmationStatus? { networkTracker?.confirmations[model.localRound.id] }
    private static func short(_ hex: String) -> String { hex.count > 12 ? "\(hex.prefix(6))…\(hex.suffix(4))" : hex }

    var body: some View {
        if model.isPreview || (receipt != nil && sealedDisplay != nil) {
            sealedTicket
        } else {
            VStack(spacing: SlipSpacing.large) {
                Text("No ticket for this slip").font(SlipFont.title2)
                Text("This local round has no completed proof in the current app session.")
                    .font(SlipFont.body).foregroundStyle(SlipColor.secondary).multilineTextAlignment(.center)
                PillButton(title: "Back to this slip") { model.go(.room) }
            }.padding(SlipSpacing.screen)
                .accessibilityIdentifier("ticket-unavailable")
        }
    }

    private var sealedTicket: some View {
        ScrollView {
            VStack(spacing: SlipSpacing.large) {
                VStack(spacing: SlipSpacing.small) {
                    SheetHeading(title: postingLater || receipt != nil ? "Sealed on this iPhone" : "Sealed", light: true, sealIndicator: true)
                    Text((sealedDisplay?.question ?? model.sampleQuestion) + (typeSize.isAccessibilitySize ? "" : " · \(sealedDisplay?.crewName ?? PreviewContent.crew)"))
                        .font(SlipFont.footnote).foregroundStyle(SlipColor.ticketSecondary).multilineTextAlignment(.center)
                }
                ticketCard.padding(.horizontal, typeSize.isAccessibilitySize ? SlipSpacing.zero : SlipSpacing.medium)
                VStack(spacing: SlipSpacing.zero) {
                    fact("Proved", "on this iPhone")
                    if let networkReceipt {
                        fact("Left this iPhone", "the proof, never the pick")
                        fact("Submitted", {
                            switch networkConfirmation {
                            case .confirmed: return "confirmed by the network"
                            case .rejected: return "rejected by the network"
                            default: return networkReceipt.submitPending ? "sent — confirming" : "via the steward"
                            }
                        }())
                        fact("Commitment", Self.short(networkReceipt.commitment.hexString), machine: true)
                        fact("Transaction", Self.short(networkReceipt.txID), machine: true)
                        fact("Execute", duration(networkReceipt.executeDuration))
                        fact("Assemble + prove", duration(networkReceipt.assembleDuration))
                        fact("Transaction size", "\(networkReceipt.transactionBytes) bytes")
                    } else {
                    fact(receipt == nil && !postingLater ? "Left this iPhone" : "Sharing", receipt == nil && !postingLater ? "the proof, never the pick" : "Stays here in this local build")
                    fact(receipt == nil ? "Opens" : "Retention", receipt == nil ? "From Friday 21:00" : "This app session only")
                    }
                    if networkReceipt != nil {
                    } else if let receipt {
                        fact("Proof time", duration(receipt.proveDuration))
                        fact("Key load", duration(receipt.keyLoadDuration))
                        fact("Proof size", "\(receipt.proofData.count) bytes")
                    } else if !postingLater {
                        fact("Receipt", "0x8f2a…c41d", machine: true)
                    }
                }.padding(.top, SlipSpacing.small)
                if networkReceipt != nil {
                    Text("Your proof was made here and handed to the steward, who paid the fee and posted it. Only the proof and the commitment left this iPhone.")
                        .font(SlipFont.footnote).foregroundStyle(SlipColor.ticketSecondary).multilineTextAlignment(.center)
                } else if postingLater || receipt != nil {
                    Text("Your proof was made here. This local build doesn’t post it, and keeps this session in memory.")
                        .font(SlipFont.footnote).foregroundStyle(SlipColor.ticketSecondary).multilineTextAlignment(.center)
                }
            }.padding(.horizontal, SlipSpacing.large).padding(.bottom, SlipSpacing.large)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActions(background: SlipColor.ticket) {
                PillButton(title: "Done", tone: .white) { model.go(.room) }.environment(\.colorScheme, .light)
                if !postingLater {
                    Button { model.inform("Ticket export will include only the public receipt. It isn’t available in this local build.") } label: {
                        Label("Save ticket", systemImage: "square.and.arrow.up").font(SlipFont.subheadlineBold)
                            .foregroundStyle(SlipColor.ticketSecondary).frame(minHeight: SlipSize.minimumTap)
                    }
                }
            }
        }.background(SlipColor.ticket.ignoresSafeArea()).preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, phase in if phase != .active { concealPick() } }
            .onChange(of: model.screen) { _, _ in concealPick() }
            .onChange(of: model.localRound.id) { _, _ in concealPick() }
            .onDisappear { concealPick() }
            .task {
                guard !model.isPreview, receipt != nil,
                      flow.consumeSealFeedback(roundID: model.localRound.id) else { stamped = true; return }
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                withAnimation(reduceMotion || accessibility.reduceMotion ? nil
                              : .spring(duration: SlipMotion.stampDuration, bounce: SlipMotion.stampBounce)) {
                    stamped = true
                }
            }
    }

    private var ticketCard: some View {
        VStack(spacing: SlipSpacing.large) {
            HStack(spacing: SlipSpacing.small) {
                CrewArt(size: SlipSize.largeIcon, crewID: sealedDisplay?.crewName ?? PreviewContent.crew)
                Text(sealedDisplay.map { "\($0.crewName) · sealed \(SlipDateText.weekdayTime($0.sealedAt))" } ?? "Saturday crew · sealed Tuesday 18:42")
                    .font(SlipFont.footnote).foregroundStyle(SlipColor.secondary)
            }
            VStack(spacing: SlipSpacing.medium) {
                Text("Your pick").font(SlipFont.footnoteBold).foregroundStyle(SlipColor.secondary)
                Text(peek.isVisible ? sealedChoice : "•••").font(SlipFont.large).foregroundStyle(SlipColor.ink)
                    .accessibilityLabel(peek.isVisible ? "Your pick: \(sealedChoice)" : "Your pick is concealed")
                SealMark(size: SlipSize.sealDisc)
                    .scaleEffect(stamped || model.isPreview || reduceMotion || accessibility.reduceMotion ? SlipOpacity.opaque : SlipMotion.stampStartScale)
                Text("Hold to peek").font(SlipFont.footnoteBold).foregroundStyle(SlipColor.secondary)
            }
            .modifier(SealedPickAccessibilityModifier(enabled: true,
                semantics: SealedPickAccessibility(isVisible: peek.isVisible, choice: sealedChoice),
                activate: { temporaryPeek(toggle: true) }, show: { temporaryPeek() }, conceal: concealPick))
        }.padding(SlipSpacing.large)
            .frame(maxWidth: .infinity, minHeight: SlipSize.receiptCardHeight)
            .background(SlipColor.onSeal, in: RoundedRectangle(cornerRadius: SlipRadius.largeCard))
            .overlay { if contrast == .increased || accessibility.increaseContrast {
                RoundedRectangle(cornerRadius: SlipRadius.largeCard).stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis)
            } }
            .environment(\.colorScheme, .light)
            .onLongPressGesture(minimumDuration: SlipMotion.pressDuration, pressing: {
                peekTask?.cancel(); peekTask = nil
                peek.touch(pressing: $0)
            }, perform: {})
    }

    private func temporaryPeek(toggle: Bool = false) {
        guard scenePhase == .active else { return }
        guard toggle || !peek.isVisible else { return }
        peekTask?.cancel(); peekTask = nil
        let expiry = toggle ? peek.activate() : peek.show()
        guard let expiryID = expiry else { return }
        peekTask = Task {
            try? await Task.sleep(for: .seconds(SlipMotion.holdDuration))
            guard !Task.isCancelled else { return }
            peek.expire(expiryID)
            peekTask = nil
        }
    }

    private func concealPick() {
        peekTask?.cancel(); peekTask = nil
        peek.conceal()
    }

    private func fact(_ label: String, _ value: String, machine: Bool = false) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: SlipSpacing.small))
            : AnyLayout(HStackLayout(spacing: SlipSpacing.medium))
        return VStack(spacing: SlipSpacing.standard) {
            layout {
                Text(label).font(SlipFont.subheadline).foregroundStyle(SlipColor.ticketSecondary)
                if !typeSize.isAccessibilitySize { Spacer(minLength: SlipSpacing.small) }
                Text(value).font(machine ? SlipFont.machine : SlipFont.bodyBold)
                    .foregroundStyle(machine ? SlipColor.ticketSecondary : SlipColor.onTicket)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(SlipColor.ticketSecondary.opacity(SlipOpacity.subtle)).frame(height: SlipStroke.hairline)
        }.padding(.top, SlipSpacing.standard)
    }

    private func duration(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return seconds.formatted(.number.precision(.fractionLength(3))) + " s"
    }
}
