import Foundation
import Testing
@testable import Slip

/// The join half of the two-device round: an invite must put the joiner in the
/// creator's round, not a lookalike of it.
@Suite(.serialized)
struct RoundJoinTests {
    static func defaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor
    @Test("joining adopts the invite's round id, so both devices seal into one round")
    func joinAdoptsRoundIdentity() {
        let invite = RoundInviteTests.invite()
        let model = AppModel()
        let before = model.localRound.id
        #expect(before != invite.roundID)

        model.join(invite: invite, defaults: Self.defaults())

        #expect(model.localRound.id == invite.roundID)
        #expect(model.localRound.question == invite.question)
        #expect(model.localRound.sides == invite.sides)
        #expect(model.localRound.crewName == invite.crewName)
        #expect(model.localRound.sealDeadline == invite.sealDeadline)
        #expect(model.isCurrentLocalRound(invite.roundID))
    }

    @MainActor
    @Test("joining lands on the seal screen with a clean history and no carried-over seal")
    func joinLandsOnSeal() {
        let model = AppModel()
        model.go(.crews)
        model.go(.crewDetail)
        model.markLocalSeal(roundID: model.localRound.id)
        #expect(model.hasLocalSeal)

        model.join(invite: RoundInviteTests.invite(), defaults: Self.defaults())

        #expect(model.screen == .seal)
        #expect(model.history.isEmpty)
        #expect(!model.hasLocalSeal)
        #expect(model.selectedSide == "Yes")
        #expect(model.sideLabels == ["Yes", "No"])
    }

    @MainActor
    @Test("a seal from the round we left cannot be relabelled onto the joined round")
    func staleSealIsRejectedAfterJoining() {
        let model = AppModel()
        let abandoned = model.localRound.id
        model.join(invite: RoundInviteTests.invite(), defaults: Self.defaults())
        #expect(model.markLocalSeal(roundID: abandoned) == false)
        #expect(!model.hasLocalSeal)
    }

    @MainActor
    @Test("an unconfigured device adopts the invite's relay and contract")
    func joinAdoptsNetworkWhenAbsent() {
        let invite = RoundInviteTests.invite()
        let defaults = Self.defaults()
        let outcome = AppModel().join(invite: invite, defaults: defaults)

        #expect(outcome == .joinedAndAdoptedNetwork)
        let setup = NetworkSetup.load(defaults: defaults)
        #expect(setup?.contractAddressHex == invite.contractAddressHex)
        #expect(setup?.relayURL == invite.relayURL)
    }

    @MainActor
    @Test("an already-matching device reports a plain join and keeps its token")
    func joinKeepsMatchingNetwork() {
        let invite = RoundInviteTests.invite()
        let defaults = Self.defaults()
        NetworkSetup(relayURL: invite.relayURL, contractAddressHex: invite.contractAddressHex,
                     relayToken: "existing-token").save(defaults: defaults)

        let outcome = AppModel().join(invite: invite, defaults: defaults)

        #expect(outcome == .joined)
        #expect(NetworkSetup.load(defaults: defaults)?.relayToken == "existing-token")
    }

    /// An invite arrives from outside the app. It may carry a round id, but it may not
    /// quietly repoint a configured phone at somebody else's relay or contract.
    @MainActor
    @Test("an invite cannot silently repoint a device that is already configured")
    func joinRefusesToRepointConfiguredDevice() {
        let invite = RoundInviteTests.invite()
        let defaults = Self.defaults()
        let configured = NetworkSetup(relayURL: URL(string: "https://own-relay.test")!,
                                      contractAddressHex: String(repeating: "cd", count: 32),
                                      relayToken: "existing-token")
        configured.save(defaults: defaults)

        let outcome = AppModel().join(invite: invite, defaults: defaults)

        #expect(outcome == .joinedWithNetworkConflict(configuredContractHex: configured.contractAddressHex))
        let after = NetworkSetup.load(defaults: defaults)
        #expect(after?.contractAddressHex == configured.contractAddressHex)
        #expect(after?.relayURL == configured.relayURL)
        #expect(after?.relayToken == "existing-token")
    }

    @MainActor
    @Test("joining twice from the same invite leaves the round untouched")
    func joiningTwiceIsIdempotent() {
        let invite = RoundInviteTests.invite()
        let defaults = Self.defaults()
        let model = AppModel()
        model.join(invite: invite, defaults: defaults)
        let first = model.localRound
        model.join(invite: invite, defaults: defaults)
        #expect(model.localRound == first)
    }

    /// Invites live in group chats and get tapped more than once. Re-tapping after
    /// sealing must not discard the seal or restart the round.
    @MainActor
    @Test("re-tapping the invite after sealing keeps the seal")
    func rejoinPreservesAnExistingSeal() {
        let invite = RoundInviteTests.invite()
        let defaults = Self.defaults()
        let model = AppModel()
        model.join(invite: invite, defaults: defaults)
        model.selectedSide = "No"
        #expect(model.markLocalSeal(roundID: invite.roundID))

        model.join(invite: invite, defaults: defaults)

        #expect(model.hasLocalSeal)
        #expect(model.selectedSide == "No")
        #expect(model.localRound.id == invite.roundID)
        #expect(model.screen == .seal)
    }

    @MainActor
    @Test("a relay-only conflict across repeated joins preserves all saved network fields")
    func repeatedRelayOnlyConflictPreservesSetup() {
        let invite = RoundInviteTests.invite()
        let defaults = Self.defaults()
        let configured = NetworkSetup(relayURL: URL(string: "https://own-relay.test")!,
            contractAddressHex: invite.contractAddressHex, relayToken: "existing-token")
        configured.save(defaults: defaults)
        let model = AppModel()
        for _ in 0..<2 {
            #expect(model.join(invite: invite, defaults: defaults)
                == .joinedWithNetworkConflict(configuredContractHex: configured.contractAddressHex))
            #expect(NetworkSetup.load(defaults: defaults) == configured)
        }
    }

}
