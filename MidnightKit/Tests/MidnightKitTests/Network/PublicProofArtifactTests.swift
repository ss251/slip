import Foundation
import Testing
@testable import MidnightKit

@Suite("Public proof artifact")
struct PublicProofArtifactTests {
    @Test("payload contains only proof and commitment")
    func exactPublicShape() throws {
        let artifact = try PublicProofArtifact(
            proof: Data(repeating: 0x11, count: 48),
            commitment: Data(repeating: 0x22, count: 32)
        )

        let payload = try artifact.encoded()
        let object = try #require(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )

        #expect(Set(object.keys) == ["commitment", "proof"])
        #expect(try PublicProofArtifact.decode(payload) == artifact)
    }

    @Test("planted witness pattern is detected by the positive control, never the payload")
    func witnessPatternDoesNotEnterPayload() throws {
        let privateSeal = PrivateSealFixture(
            witness: Data(repeating: 0xA5, count: 32),
            proof: Data(repeating: 0x11, count: 48),
            commitment: Data(repeating: 0x22, count: 32)
        )
        let artifact = try PublicProofArtifact(
            proof: privateSeal.proof,
            commitment: privateSeal.commitment
        )
        let payload = try artifact.encoded()

        #expect(!Self.contains(privateSeal.witness, in: payload))

        var contaminatedProof = Data([0x01])
        contaminatedProof.append(privateSeal.witness)
        contaminatedProof.append(0x02)
        let plantedPayload = try PublicProofArtifact(
            proof: contaminatedProof,
            commitment: privateSeal.commitment
        ).encoded()
        #expect(Self.contains(privateSeal.witness, in: plantedPayload))
    }

    @Test("invalid public material is rejected")
    func validation() throws {
        #expect(throws: PublicProofArtifact.ValidationError.emptyProof) {
            _ = try PublicProofArtifact(proof: Data(), commitment: Data(repeating: 0x22, count: 32))
        }
        #expect(throws: PublicProofArtifact.ValidationError.invalidCommitmentLength) {
            _ = try PublicProofArtifact(proof: Data([0x11]), commitment: Data(repeating: 0x22, count: 31))
        }

        let artifact = try PublicProofArtifact(
            proof: Data(repeating: 0x11, count: 48),
            commitment: Data(repeating: 0x22, count: 32)
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: artifact.encoded()) as? [String: Any]
        )
        object["witness"] = Data(repeating: 0xA5, count: 32).base64EncodedString()
        let payloadWithExtraField = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: PublicProofArtifact.ValidationError.unexpectedFields) {
            _ = try PublicProofArtifact.decode(payloadWithExtraField)
        }
    }

    private static func contains(_ secret: Data, in payload: Data) -> Bool {
        if payload.range(of: secret) != nil { return true }
        let text = String(decoding: payload, as: UTF8.self)
        if text.contains(secret.base64EncodedString()) { return true }
        let hex = secret.map { String(format: "%02x", $0) }.joined()
        if text.localizedCaseInsensitiveContains(hex) { return true }
        guard let json = try? JSONSerialization.jsonObject(with: payload) else { return false }
        return contains(secret, inJSON: json)
    }

    private static func contains(_ secret: Data, inJSON value: Any) -> Bool {
        switch value {
        case let string as String:
            return Data(base64Encoded: string)?.range(of: secret) != nil
        case let values as [Any]:
            return values.contains { contains(secret, inJSON: $0) }
        case let values as [String: Any]:
            return values.values.contains { contains(secret, inJSON: $0) }
        default:
            return false
        }
    }

    private struct PrivateSealFixture {
        let witness: Data
        let proof: Data
        let commitment: Data
    }
}
