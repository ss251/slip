import SwiftUI

struct SlipRootView: View {
    @Bindable var model: AppModel
    let flow: SealFlowModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        screenContent
            .font(SlipFont.body).foregroundStyle(SlipColor.ink)
            .background(SlipColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: SlipSpacing.zero) {
                if model.screen.hasTabs { GlassTabBar() }
            }
            .environment(model).environment(flow)
            .overlay {
                // Conceal private UI before the app switcher captures an inactive scene.
                if scenePhase != .active && !model.isPreview {
                    SlipColor.background.ignoresSafeArea()
                        .overlay(Text("Slip").font(SlipFont.large).foregroundStyle(SlipColor.ink))
                }
            }
            .alert("Slip", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                Button("OK", role: .cancel) { model.notice = nil }
            } message: { Text(model.notice ?? "") }
    }

    @ViewBuilder private var screenContent: some View {
        switch model.screen {
        case .howItWorks: HowItWorksScreen()
        case .home: HomeScreen(firstRun: false)
        case .firstRun: HomeScreen(firstRun: true)
        case .newSlip: NewSlipScreen()
        case .invite: InviteScreen()
        case .seal, .sealing, .proofFailed, .alreadySealed: SealScreen(mode: model.screen)
        case .ticket: TicketScreen()
        case .postingLater: TicketScreen(postingLater: true)
        case .room: SealedRoomScreen()
        case .opening: OpeningScreen(mode: .opening)
        case .awaiting: OpeningScreen(mode: .awaiting)
        case .mismatch: OpeningScreen(mode: .mismatch)
        case .verdict: VerdictScreen(satOut: false)
        case .satOut: VerdictScreen(satOut: true)
        case .standings: StandingsScreen()
        case .crews: CrewsScreen()
        case .crewDetail: CrewDetailScreen()
        case .you: YouScreen()
        case .settle: SettleScreen()
        case .challenge: ChallengeScreen()
        case .voided: VoidedScreen()
        }
    }
}

#Preview("Slips") {
    SlipRootView(model: .preview(.home), flow: SealFlowModel())
}

#Preview("Seal") {
    SlipRootView(model: .preview(.seal), flow: SealFlowModel())
}
