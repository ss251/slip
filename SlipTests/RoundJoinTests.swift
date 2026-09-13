import Foundation
import Testing
@testable import Slip

/// Public invite import and local seal preservation. These tests do not establish
/// membership or bind imported metadata to an on-chain round.
@Suite(.serialized)
struct RoundJoinTests {
    static func defaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor
    @Test("joining imports the invite’s local round id and presentation metadata")
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

    @MainActor
    @Test("an invite preserves incomplete or invalid saved network settings")
    func partialConfigurationIsNotAbsent() {
        let keys = [NetworkSetup.relayKey, NetworkSetup.contractKey, NetworkSetup.tokenKey]
        let configurations: [[String: Any]] = [
            [NetworkSetup.relayKey: "https://original-relay.test"],
            [NetworkSetup.contractKey: String(repeating: "ab", count: 32)],
            [NetworkSetup.tokenKey: "existing-token"],
            [NetworkSetup.relayKey: "https://original-relay.test",
             NetworkSetup.contractKey: "invalid", NetworkSetup.tokenKey: "existing-token"],
            [NetworkSetup.relayKey: "https://original-relay.test",
             NetworkSetup.contractKey: String(repeating: "+f", count: 32),
             NetworkSetup.tokenKey: "existing-token"],
            [NetworkSetup.relayKey: "https://original-relay.test",
             NetworkSetup.contractKey: String(repeating: "-0", count: 32),
             NetworkSetup.tokenKey: "existing-token"],
            [NetworkSetup.relayKey: 42, NetworkSetup.contractKey: "invalid"]
        ]
        for configuration in configurations {
            let defaults = Self.defaults()
            for (key, value) in configuration { defaults.set(value, forKey: key) }
            #expect(NetworkSetup.load(defaults: defaults) == nil)
            let expectedContract = defaults.string(forKey: NetworkSetup.contractKey) ?? ""
            let outcome = AppModel().join(invite: RoundInviteTests.invite(), defaults: defaults)
            #expect(outcome == .joinedWithNetworkConflict(configuredContractHex: expectedContract))
            let after = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
                defaults.object(forKey: key).map { (key, $0) }
            })
            #expect(NSDictionary(dictionary: configuration).isEqual(to: after))
        }
    }

    enum ChangedField: CaseIterable, Equatable, Sendable {
        case roundID, contract, relay, question, sides, deadline, crew
    }

    private static func changing(_ field: ChangedField, in invite: RoundInvite) -> RoundInvite {
        RoundInvite(
            relayURL: field == .relay ? URL(string: "https://other-relay.test")! : invite.relayURL,
            contractAddressHex: field == .contract ? String(repeating: "cd", count: 32) : invite.contractAddressHex,
            roundID: field == .roundID ? UUID() : invite.roundID,
            question: field == .question ? "A different question?" : invite.question,
            sides: field == .sides ? Array(invite.sides.reversed()) : invite.sides,
            crewName: field == .crew ? "Different crew" : invite.crewName,
            paletteKey: invite.paletteKey,
            sealDeadline: field == .deadline ? invite.sealDeadline.addingTimeInterval(60) : invite.sealDeadline
        )
    }

    @MainActor
    @Test("each changed identity field replaces the round without its seal", arguments: ChangedField.allCases)
    func changedIdentityDiscardsSeal(_ field: ChangedField) throws {
        let original = RoundInviteTests.invite()
        let replacement = Self.changing(field, in: original)
        let defaults = Self.defaults()
        let model = AppModel()
        model.join(invite: original, defaults: defaults)
        let configured = NetworkSetup(relayURL: original.relayURL,
            contractAddressHex: original.contractAddressHex, relayToken: "existing-token")
        configured.save(defaults: defaults)
        let oldRound = model.localRound
        let oldRevision = model.localRoundRevision
        model.selectedSide = "No"
        #expect(model.markLocalSeal(roundID: oldRound.id))
        var discarded: [UUID] = []

        let outcome = model.join(invite: replacement, defaults: defaults, beforeReplacingRound: { oldID in
            #expect(model.localRound == oldRound) // invalidation precedes replacement
            discarded.append(oldID)
        })

        #expect(discarded == [oldRound.id])
        #expect(model.localRoundRevision != oldRevision)
        #expect(!model.hasLocalSeal)
        #expect(model.localRound.id == replacement.roundID)
        #expect(model.localRound.question == replacement.question)
        #expect(model.localRound.sides == replacement.sides)
        #expect(model.localRound.crewName == replacement.crewName)
        #expect(model.localRound.sealDeadline == replacement.sealDeadline)
        #expect(model.selectedSide == replacement.sides.first)
        #expect(NetworkSetup.load(defaults: defaults) == configured)
        if field == .contract || field == .relay {
            #expect(outcome == .joinedWithNetworkConflict(configuredContractHex: configured.contractAddressHex))
        } else {
            #expect(outcome == .joined)
        }
    }

    @MainActor
    @Test("changing saved configuration cannot rebind a prior seal to the same UUID")
    func changedDefaultsDoNotRebindSeal() {
        let original = RoundInviteTests.invite()
        let replacement = Self.changing(.contract, in: original)
        let defaults = Self.defaults()
        let model = AppModel()
        model.join(invite: original, defaults: defaults)
        #expect(model.markLocalSeal(roundID: original.roundID))
        NetworkSetup(relayURL: replacement.relayURL,
                     contractAddressHex: replacement.contractAddressHex).save(defaults: defaults)
        var invalidated = false
        model.join(invite: replacement, defaults: defaults, beforeReplacingRound: { _ in invalidated = true })
        #expect(invalidated)
        #expect(!model.hasLocalSeal)
    }

    @MainActor
    @Test("an identical invite preserves the cached ticket and never invokes replacement")
    func identicalInviteKeepsFlow() async {
        let invite = RoundInviteTests.invite()
        let defaults = Self.defaults()
        let model = AppModel()
        model.join(invite: invite, defaults: defaults)
        let original = model.localRound
        let originalRevision = model.localRoundRevision
        let flow = SealFlowModel { round, choice in Self.syntheticSeal(round, choice: choice) }
        flow.beginSeal(round: original, choice: 0)
        await flow.waitForCurrentSeal()
        #expect(flow.stage == .sealed)
        #expect(model.markLocalSeal(roundID: original.id))
        model.selectedSide = "No"
        var replaced = false
        model.join(invite: invite, defaults: defaults, beforeReplacingRound: { _ in
            replaced = true
            flow.discard()
        })
        #expect(!replaced)
        #expect(model.localRound == original)
        #expect(model.localRoundRevision == originalRevision)
        #expect(model.hasLocalSeal)
        #expect(model.selectedSide == "No")
        #expect(flow.receipt?.roundID == original.id)
        #expect(flow.stage == .sealed)
    }

    @MainActor
    @Test("same-UUID replacement removes the cached ticket and rejects old confirmation writes")
    func replacedInviteClearsCachedPresentation() async {
        let original = RoundInviteTests.invite()
        let replacement = Self.changing(.question, in: original)
        let defaults = Self.defaults()
        let model = AppModel()
        model.join(invite: original, defaults: defaults)
        let flow = SealFlowModel { round, choice in Self.syntheticSeal(round, choice: choice) }
        flow.beginSeal(round: model.localRound, choice: 0)
        await flow.waitForCurrentSeal()
        #expect(flow.stage == .sealed)
        #expect(model.markLocalSeal(roundID: original.roundID))
        let tracker = NetworkSealTracker()
        let token = tracker.recordingToken(for: original.roundID)
        let receipt = NetworkSealReceipt(commitment: Data(repeating: 1, count: 32),
            txID: "synthetic", submitPending: true, executeDuration: .zero,
            assembleDuration: .zero, transactionBytes: 1)
        tracker.record(receipt, for: original.roundID, token: token)
        tracker.record(.pending, for: original.roundID, token: token)

        model.join(invite: replacement, defaults: defaults, beforeReplacingRound: { oldID in
            flow.discard()
            tracker.discard(roundID: oldID)
        })

        #expect(!model.hasLocalSeal)
        #expect(flow.stage == .choosing)
        #expect(flow.result == nil)
        #expect(flow.roundResult == nil)
        #expect(flow.activeRoundID == nil)
        tracker.record(receipt, for: original.roundID, token: token)
        tracker.record(.confirmed, for: original.roundID, token: token)
        #expect(tracker.receipt(for: original.roundID) == nil)
        #expect(tracker.confirmations[original.roundID] == nil)
        let newToken = tracker.recordingToken(for: original.roundID)
        #expect(newToken != token)
        tracker.record(receipt, for: original.roundID, token: newToken)
        #expect(tracker.receipt(for: original.roundID) == receipt)
    }

    @MainActor
    @Test("a local lookalike without an imported network binding cannot keep its seal")
    func localLookalikeDoesNotAcquireNetworkBinding() {
        let model = AppModel()
        let local = model.localRound
        let invite = RoundInvite(relayURL: URL(string: "https://relay.test")!,
            contractAddressHex: String(repeating: "ab", count: 32), roundID: local.id,
            question: local.question, sides: local.sides, crewName: local.crewName,
            paletteKey: "unused", sealDeadline: local.sealDeadline)
        let defaults = Self.defaults()
        NetworkSetup(relayURL: invite.relayURL, contractAddressHex: invite.contractAddressHex)
            .save(defaults: defaults)
        #expect(model.markLocalSeal(roundID: local.id))
        let revision = model.localRoundRevision
        model.join(invite: invite, defaults: defaults)
        #expect(!model.hasLocalSeal)
        #expect(model.localRoundRevision != revision)
    }

    @MainActor
    @Test("replacement also clears a departed round's cached private ticket")
    func replacementClearsDepartedTicket() async {
        let model = AppModel()
        let flow = SealFlowModel { round, choice in Self.syntheticSeal(round, choice: choice) }
        let previous = model.localRound
        flow.beginSeal(round: previous, choice: 0)
        await flow.waitForCurrentSeal()
        flow.depart(roundID: previous.id)
        model.startLocalRound(question: "Next?", sides: ["Yes", "No"], crewName: "Test")
        #expect(flow.activeRoundID == nil)
        #expect(flow.sealedDisplay?.roundID == previous.id)
        model.join(invite: RoundInviteTests.invite(), defaults: Self.defaults(),
                   beforeReplacingRound: { _ in flow.discard() })
        #expect(flow.result == nil)
        #expect(flow.sealedDisplay == nil)
        #expect(flow.stage == .choosing)
    }

    private nonisolated static func syntheticSeal(_ round: LocalRound, choice: UInt8) -> LocalSealResult {
        let index = choice == 1 ? 0 : 1
        return LocalSealResult(receipt: LocalSealReceipt(roundID: round.id,
            questionCommitment: round.questionCommitment, proofData: Data([1]), proofBytes: 1,
            executeDuration: .zero, keyLoadDuration: .zero, proveDuration: .zero, commitment: nil),
            privateDisplay: LocalSealedDisplay(roundID: round.id, question: round.question,
                sides: round.sides, crewName: round.crewName, sealDeadline: round.sealDeadline,
                selectedSideIndex: index, selectedSide: round.sides[index], sealedAt: round.createdAt))
    }

}
