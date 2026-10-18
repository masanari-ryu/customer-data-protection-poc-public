import Foundation
import CryptoKit
import Security

// G0-only format, not a G1 protocol. No plaintext/secret description or Codable conformance.
enum ProbePurpose: UInt8, CaseIterable {
    case vaultKey = 1
    case deviceChallenge = 2
}

struct ProbeEnvelope {
    static let magic = Data("g0-envelope-v1\0".utf8)
    static let byteCount = magic.count + 1 + 16 + 8 + 32
    let purpose: ProbePurpose
    let vaultID: UUID
    let epoch: UInt64
    let secret: Data

    func encoded() throws -> Data {
        guard secret.count == 32 else { throw ProbeError.invalidEnvelope }
        var bytes = Self.magic
        bytes.append(purpose.rawValue)
        var uuid = vaultID.uuid
        withUnsafeBytes(of: &uuid) { bytes.append(contentsOf: $0) }
        var bigEndian = epoch.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
        bytes.append(secret)
        return bytes
    }

    static func decode(_ data: Data, purpose: ProbePurpose, vaultID: UUID, epoch: UInt64) throws -> ProbeEnvelope {
        // Exact size first: neither trailing bytes nor truncated data are accepted.
        let b = [UInt8](data)
        let offset = magic.count
        guard b.count == byteCount, Data(b.prefix(offset)) == magic,
              let actualPurpose = ProbePurpose(rawValue: b[offset]) else {
            throw ProbeError.invalidEnvelope
        }
        let u = Array(b[(offset + 1)..<(offset + 17)])
        let actualID = UUID(uuid: (u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7],
                                   u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]))
        let actualEpoch = b[(offset + 17)..<(offset + 25)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard actualPurpose == purpose, actualID == vaultID, actualEpoch == epoch else {
            throw ProbeError.wrongContext
        }
        return ProbeEnvelope(purpose: actualPurpose, vaultID: actualID, epoch: actualEpoch,
                             secret: Data(b.suffix(32)))
    }
}

func secureRandom32() throws -> Data {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else { throw ProbeError.status("random32", status) }
    return Data(bytes)
}

func fingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// Only a digest is eligible for a challenge response. G0 has no return-plaintext API.
func challengeDigest(_ canonicalEnvelope: Data) -> Data {
    Data(SHA256.hash(data: Data("g0-dk-pop-digest-v1\0".utf8) + canonicalEnvelope))
}
