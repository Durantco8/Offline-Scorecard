import Foundation
import CRDTKit

/// Messages exchanged during anti-entropy gossip.
///
/// Protocol:
/// 1. Peer sends `.vvDigest` containing its current version vector for a round
/// 2. Receiver compares against local state; if local has newer data, responds with `.delta`
/// 3. Receiver also sends its own `.vvDigest` back so the originator can do the same
public enum SyncMessage {
    /// "Here's what I have" — version vector summary for a round.
    case vvDigest(roundID: UUID, vv: VersionVector)

    /// "Here's what you're missing" — delta payload.
    case delta(RoundDelta)
}

// MARK: - CBOR encoding

extension SyncMessage {
    /// CBOR layout: map { 0: type (0=digest, 1=delta), 1: payload }
    public func encode() -> Data {
        let cbor: CBORValue
        switch self {
        case .vvDigest(let roundID, let vv):
            cbor = cborMap(
                (0, .unsigned(0)),
                (1, uuidToCBOR(roundID)),
                (2, vv.toCBOR())
            )
        case .delta(let roundDelta):
            cbor = cborMap(
                (0, .unsigned(1)),
                (1, roundDelta.toCBOR())
            )
        }
        var encoder = CBOREncoder()
        return encoder.encode(cbor)
    }

    public static func decode(_ data: Data) throws -> SyncMessage {
        var decoder = CBORDecoder(data: data)
        let cbor = try decoder.decode()
        let m = try readCBORMap(cbor)
        let type = try requireUnsigned(try requireKey(m, 0))

        switch type {
        case 0:
            let roundID = try uuidFromCBOR(try requireKey(m, 1))
            let vv = try VersionVector.fromCBOR(try requireKey(m, 2))
            return .vvDigest(roundID: roundID, vv: vv)
        case 1:
            let delta = try RoundDelta.fromCBOR(try requireKey(m, 1))
            return .delta(delta)
        default:
            throw CBORError.typeMismatch(expected: "SyncMessage type 0 or 1", got: .unsigned(type))
        }
    }
}
