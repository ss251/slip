#if DEBUG
import Foundation

/// A DEBUG diagnostic handoff from an on-device seal to an external test harness.
///
/// This value intentionally has exactly two fields. It is public material: the
/// locally generated zero-knowledge proof bytes and the public commitment. It is not
/// a ledger transaction or a transaction-bound proof envelope. Circuit inputs,
/// private transcript outputs, choices, salts, and proof preimages do not belong at
/// this boundary.
public struct PublicProofArtifact: Codable, Sendable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case emptyProof
        case invalidCommitmentLength
        case unexpectedFields
    }

    public let proof: Data
    public let commitment: Data

    private enum CodingKeys: String, CodingKey {
        case proof
        case commitment
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    public init(proof: Data, commitment: Data) throws {
        guard !proof.isEmpty else { throw ValidationError.emptyProof }
        guard commitment.count == 32 else { throw ValidationError.invalidCommitmentLength }
        self.proof = proof
        self.commitment = commitment
    }

    public init(from decoder: any Decoder) throws {
        let unkeyed = try decoder.container(keyedBy: AnyCodingKey.self)
        let fieldNames = Set(unkeyed.allKeys.map(\.stringValue))
        guard fieldNames == ["commitment", "proof"] else {
            throw ValidationError.unexpectedFields
        }

        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            proof: values.decode(Data.self, forKey: .proof),
            commitment: values.decode(Data.self, forKey: .commitment)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(proof, forKey: .proof)
        try values.encode(commitment, forKey: .commitment)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}
#endif
