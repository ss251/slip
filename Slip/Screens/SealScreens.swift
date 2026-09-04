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
    @State private var peek = false
    @State private var accessibleHold: Task<Void, Never>?
    private var proving: Bool { mode == .sealing || flow.stage == .proving }
    private var failed: Bool { mode == .proofFailed || flow.stage == .failed }
    private var already: Bool { mode == .alreadySealed || model.hasLocalSeal }

    var body: some View {
        ScrollView {
            VStack(spacing: SlipSpacing.large) {
                SheetHeading(title: already ? "Already sealed" : proving ? "Sealing" : "Seal your pick", light: true)
                ContextRow(light: true).padding(.top, SlipSpacing.small)
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
                    Text("Nobody — not even Slip — can read a sealed pick.")
                        .font(SlipFont.footnote).foregroundStyle(SlipColor.onTicket).multilineTextAlignment(.center)
                }
            }.padding(.horizontal, SlipSpacing.large)
                .padding(.bottom, SlipSpacing.large)
        }
        .safeAreaInset(edge: .bottom) { bottom }
        .background { AmbientBackground() }
        .foregroundStyle(SlipColor.onSeal)
        .preferredColorScheme(.dark)
        .onDisappear { accessibleHold?.cancel(); hold.cancel(); peek = false }
        .onChange(of: model.screen) { _, _ in peek = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { accessibleHold?.cancel(); accessibleHold = nil; hold.cancel(); peek = false }
        }
    }

    private var pickCard: some View {
        VStack(spacing: SlipSpacing.medium) {
            Text("Your pick").font(SlipFont.footnoteBold).foregroundStyle(SlipColor.secondary)
            Text(already && !peek ? "•••" : model.selectedSide)
                .font(SlipFont.large).foregroundStyle(SlipColor.ink.opacity(proving ? SlipOpacity.muted : SlipOpacity.opaque))
                .accessibilityLabel(already && !peek ? "Your pick is concealed" : "Your pick: \(model.selectedSide)")
            if !already { Text("Only you can see this").font(SlipFont.footnote).foregroundStyle(SlipColor.secondary) }
            TimelineView(.animation(paused: hold.began == nil)) { context in
                Circle().stroke(SlipColor.separator, lineWidth: SlipStroke.emphasis)
                    .overlay {
                        Circle().trim(from: SlipSpacing.zero, to: already || proving ? SlipOpacity.opaque : hold.progress(at: context.date.timeIntervalSinceReferenceDate))
                            .fill(SlipColor.seal)
                    }
                    .frame(width: already ? SlipSize.sealDisc : SlipSize.largeIcon,
                           height: already ? SlipSize.sealDisc : SlipSize.largeIcon)
            }.padding(.top, SlipSpacing.medium)
            if already { Text("Hold to peek").font(SlipFont.footnoteBold).foregroundStyle(SlipColor.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: SlipSize.choiceCardHeight)
        .padding(SlipSpacing.large)
        .background(SlipColor.onSeal, in: RoundedRectangle(cornerRadius: SlipRadius.largeCard))
        .overlay { if contrast == .increased || accessibility.increaseContrast {
            RoundedRectangle(cornerRadius: SlipRadius.largeCard).stroke(SlipColor.contrastBorder, lineWidth: SlipStroke.emphasis)
        } }
        .environment(\.colorScheme, .light)
        .onLongPressGesture(minimumDuration: SlipMotion.pressDuration, pressing: { pressing in
            if already { peek = pressing }
        }, perform: {})
        .accessibilityAction(named: "Peek at your pick") { if already { temporaryPeek() } }
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
                        .background(model.selectedSide == side ? SlipColor.onSeal : (reduceTransparency || accessibility.reduceTransparency) ? SlipColor.ambient : SlipColor.onSeal.opacity(SlipOpacity.subtle),
                                    in: RoundedRectangle(cornerRadius: SlipRadius.control))
                }.buttonStyle(.plain).environment(\.colorScheme, .light)
                    .accessibilityAddTraits(model.selectedSide == side ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var bottom: some View {
        BottomActions {
            if already {
                PillButton(title: "See your ticket", tone: .white) { model.go(.ticket) }
            } else if failed {
                PillButton(title: "Try again", tone: .white) { flow.chooseAgain(); model.screen = .seal }
                Button("Change my pick") { flow.chooseAgain(); model.screen = .seal }.font(SlipFont.subheadlineBold)
                    .frame(minHeight: SlipSize.minimumTap).foregroundStyle(SlipColor.onTicket)
            } else if proving {
                PillButton(title: "Sealing…", tone: .seal) {}.disabled(true).opacity(SlipOpacity.strong)
            } else {
                Text("Seal by Friday 20:00").font(SlipFont.footnoteBold)
                Text(hold.began == nil ? "Hold to seal" : "Keep holding…").font(SlipFont.headline)
                    .frame(maxWidth: .infinity, minHeight: SlipSize.buttonHeight)
                    .background(SlipColor.seal, in: Capsule()).contentShape(Capsule())
                    .onLongPressGesture(minimumDuration: SlipMotion.holdDuration, maximumDistance: SlipSize.minimumTap,
                        pressing: { pressing in
                            if pressing { hold.start(at: Date.timeIntervalSinceReferenceDate) }
                            else { hold.cancel() }
                        }, perform: { beginSeal() })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Hold to seal")
                    .accessibilityHint("Confirms your pick after 1.2 seconds. Activate again to cancel.")
                    .accessibilityAction { accessibleConfirm() }
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
        accessibleHold?.cancel(); accessibleHold = nil; hold.cancel()
        Task {
            await flow.seal(choice: model.selectedSide == model.sideLabels.first ? 1 : 0)
            if flow.stage == .sealed {
                model.hasLocalSeal = true
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                withAnimation(reduceMotion || accessibility.reduceMotion ? .easeOut(duration: SlipMotion.cancelDuration)
                              : .spring(duration: SlipMotion.stampDuration, bounce: SlipOpacity.subtle)) {
                    model.go(.ticket)
                }
            }
        }
    }

    private func accessibleConfirm() {
        if accessibleHold != nil { accessibleHold?.cancel(); accessibleHold = nil; hold.cancel(); return }
        hold.start(at: Date.timeIntervalSinceReferenceDate)
        accessibleHold = Task {
            try? await Task.sleep(for: .seconds(SlipMotion.holdDuration))
            guard !Task.isCancelled else { return }
            beginSeal()
        }
    }

    private func temporaryPeek() {
        peek = true
        Task { try? await Task.sleep(for: .seconds(SlipMotion.holdDuration)); peek = false }
    }
}

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            SlipColor.ambient
            ArtField().opacity(SlipOpacity.muted)
        }.ignoresSafeArea()
    }
}

struct TicketScreen: View {
    var postingLater = false
    @Environment(AppModel.self) private var model
    @Environment(SealFlowModel.self) private var flow
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var peek = false

    var body: some View {
        ScrollView {
            VStack(spacing: SlipSpacing.large) {
                SheetHeading(title: postingLater || flow.receipt != nil ? "● Sealed on this iPhone" : "● Sealed", light: true)
                Text(model.sampleQuestion + (typeSize.isAccessibilitySize ? "" : " · Saturday crew"))
                    .font(SlipFont.footnote).foregroundStyle(SlipColor.ticketSecondary).multilineTextAlignment(.center)
                ticketCard.padding(.horizontal, typeSize.isAccessibilitySize ? SlipSpacing.zero : SlipSpacing.medium)
                VStack(spacing: SlipSpacing.zero) {
                    fact("Proved", "on this iPhone")
                    fact(flow.receipt == nil && !postingLater ? "Left this iPhone" : "Sharing", flow.receipt == nil && !postingLater ? "the proof, never the pick" : "Stays here in this local build")
                    fact("Opens", "Friday 21:00, with everyone")
                    if let receipt = flow.receipt {
                        fact("Proof time", duration(receipt.proveDuration))
                        fact("Key load", duration(receipt.keyLoadDuration))
                        fact("Proof size", "\(receipt.proofData.count) bytes")
                    } else if !postingLater {
                        fact("Receipt", "0x8f2a…c41d", machine: true)
                    }
                }.padding(.top, SlipSpacing.standard)
                if postingLater || flow.receipt != nil {
                    Text("Your proof was made here. This local build doesn’t post it, and keeps this session in memory.")
                        .font(SlipFont.footnote).foregroundStyle(SlipColor.ticketSecondary).multilineTextAlignment(.center)
                }
            }.padding(.horizontal, SlipSpacing.large).padding(.bottom, SlipSpacing.large)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActions {
                PillButton(title: "Done", tone: .white) { model.go(.room) }.environment(\.colorScheme, .light)
                if !postingLater {
                    Button { model.inform("Ticket export will include only the public receipt. It isn’t available in this local build.") } label: {
                        Label("Save ticket", systemImage: "square.and.arrow.up").font(SlipFont.subheadlineBold)
                            .foregroundStyle(SlipColor.ticketSecondary).frame(minHeight: SlipSize.minimumTap)
                    }
                }
            }
        }.background(SlipColor.ticket.ignoresSafeArea()).preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, phase in if phase != .active { peek = false } }
            .onDisappear { peek = false }
    }

    private var ticketCard: some View {
        VStack(spacing: SlipSpacing.large) {
            HStack(spacing: SlipSpacing.small) {
                CrewArt(size: SlipSize.largeIcon)
                Text(flow.receipt == nil ? "Saturday crew · sealed Tuesday 18:42" : "Sealed on this iPhone just now")
                    .font(SlipFont.footnote).foregroundStyle(SlipColor.secondary)
            }
            VStack(spacing: SlipSpacing.medium) {
                Text("Your pick").font(SlipFont.footnoteBold).foregroundStyle(SlipColor.secondary)
                Text(peek ? model.selectedSide : "•••").font(SlipFont.large).foregroundStyle(SlipColor.ink)
                    .accessibilityLabel(peek ? "Your pick: \(model.selectedSide)" : "Your pick is concealed")
                Circle().fill(SlipColor.seal).frame(width: SlipSize.sealDisc, height: SlipSize.sealDisc)
                Text("Hold to peek").font(SlipFont.footnoteBold).foregroundStyle(SlipColor.secondary)
            }
        }.frame(maxWidth: .infinity, minHeight: SlipSize.receiptCardHeight)
            .padding(SlipSpacing.large).background(SlipColor.onSeal, in: RoundedRectangle(cornerRadius: SlipRadius.largeCard))
            .environment(\.colorScheme, .light)
            .onLongPressGesture(minimumDuration: SlipMotion.pressDuration, pressing: { peek = $0 }, perform: {})
            .accessibilityAction(named: "Peek at your pick") {
                peek = true
                Task { try? await Task.sleep(for: .seconds(SlipMotion.holdDuration)); peek = false }
            }
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
