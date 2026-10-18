import Foundation
import CryptoKit
@testable import G0Core

@MainActor
final class EnvelopeTests {
    private let vault = UUID(uuidString: "00010203-0405-0607-0809-0a0b0c0d0e0f")!
    private let secret = Data(repeating: 0xa5, count: 32)

    private func sample(_ purpose: ProbePurpose = .vaultKey, epoch: UInt64 = 0x0102030405060708) throws -> Data {
        try ProbeEnvelope(purpose: purpose, vaultID: vault, epoch: epoch, secret: secret).encoded()
    }

    func testCanonicalByteLayoutHasIndependentExpectedBytes() throws {
        let expected = Data(Array("g0-envelope-v1\0".utf8) + [1] + Array(UInt8(0)...UInt8(15))
                            + [1, 2, 3, 4, 5, 6, 7, 8] + [UInt8](repeating: 0xa5, count: 32))
        checkEqual(try sample(), expected)
    }

    func testBothPurposesRoundTripAndUInt64Boundaries() throws {
        for purpose in ProbePurpose.allCases {
            for epoch in [UInt64(0), 1, UInt64.max] {
                let data = try sample(purpose, epoch: epoch)
                let decoded = try ProbeEnvelope.decode(data, purpose: purpose, vaultID: vault, epoch: epoch)
                checkEqual(decoded.secret, secret)
                checkEqual(try decoded.encoded(), data)
            }
        }
    }

    func testEveryTruncatedLengthIsRejected() throws {
        let data = try sample()
        for size in 0..<data.count {
            expectThrows(try ProbeEnvelope.decode(Data(data.prefix(size)), purpose: .vaultKey,
                                                          vaultID: vault, epoch: 0x0102030405060708))
        }
    }

    func testTrailingDataIsRejected() throws {
        for tail in [Data([0]), Data(repeating: 0, count: 10000)] {
            expectThrows(try ProbeEnvelope.decode(sample() + tail, purpose: .vaultKey,
                                                          vaultID: vault, epoch: 0x0102030405060708))
        }
    }

    func testUnknownVersionAndPurposeAreRejected() throws {
        var version = try sample()
        version[0] ^= 1
        expectThrows(try ProbeEnvelope.decode(version, purpose: .vaultKey, vaultID: vault, epoch: 0x0102030405060708))
        var purpose = try sample()
        purpose[ProbeEnvelope.magic.count] = 255
        expectThrows(try ProbeEnvelope.decode(purpose, purpose: .vaultKey, vaultID: vault, epoch: 0x0102030405060708))
    }

    func testBothDirectionsOfPurposeConfusionAreRejected() throws {
        for actual in ProbePurpose.allCases {
            let expected: ProbePurpose = actual == .vaultKey ? .deviceChallenge : .vaultKey
            expectThrows(try ProbeEnvelope.decode(sample(actual), purpose: expected, vaultID: vault,
                                                          epoch: 0x0102030405060708)) {
                checkEqual($0 as? ProbeError, .wrongContext)
            }
        }
    }

    func testOtherVaultAndEpochAreRejected() throws {
        expectThrows(try ProbeEnvelope.decode(sample(), purpose: .vaultKey, vaultID: UUID(), epoch: 0x0102030405060708))
        expectThrows(try ProbeEnvelope.decode(sample(), purpose: .vaultKey, vaultID: vault, epoch: 9))
    }

    func testWrongSecretLengthCannotBeEncoded() {
        for count in [0, 1, 31, 33, 1000] {
            expectThrows(try ProbeEnvelope(purpose: .vaultKey, vaultID: vault, epoch: 1,
                                                  secret: Data(repeating: 0, count: count)).encoded())
        }
    }

    func testDigestIsPurposeSeparatedAndContextBound() throws {
        let encoded = try sample()
        checkNotEqual(challengeDigest(encoded), Data(SHA256.hash(data: encoded)))
        checkNotEqual(challengeDigest(encoded), challengeDigest(try sample(.deviceChallenge)))
        checkNotEqual(challengeDigest(encoded), challengeDigest(try sample(epoch: 5)))
        checkEqual(challengeDigest(encoded).count, 32)
    }

    func testFingerprintUsesKnownSHA256Vector() {
        checkEqual(fingerprint(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testRestartComparisonRejectsChangedAndMissingRoles() throws {
        let baseline = PublicBaseline(fingerprints: ["dk": "a", "admin-sign": "b", "writer-sign": "c"])
        expectNoThrow(try baseline.validate(["dk": "a", "admin-sign": "b", "writer-sign": "c"]))
        expectThrows(try baseline.validate(["dk": "x", "admin-sign": "b", "writer-sign": "c"]))
        expectThrows(try baseline.validate(["dk": "a"]))
    }

    func testReportContainsNoProbeSecretAndNoAcceptanceClaim() throws {
        let report = ProbeReport(environment: .current(), events: [
            ProbeEvent(check: "unit-only", outcome: "観測", detail: "no hardware operation")
        ])
        let json = try requireValue(String(data: report.json(), encoding: .utf8))
        checkFalse(json.contains(secret.base64EncodedString()))
        checkFalse(json.contains(String(repeating: "a5", count: 32)))
        checkTrue(json.contains("\"acceptanceTestsPassed\" : 0"))
        checkTrue(json.contains("未実施"))
    }

    func testInvalidatedOperationCannotStartKeyAccess() {
        let hardware = HardwareProbe()
        hardware.prepareOperation()
        hardware.cancel()
        expectThrows(try hardware.checkSealing()) {
            checkEqual($0 as? ProbeError, .interrupted)
        }
    }

    func testCancellationAndFailureAreSeparateOutcomes() {
        checkEqual(ProbeError.status("key-load", -128).outcome, "取消")
        checkEqual(ProbeError.status("key-load", -34018).outcome, "失敗")
        checkEqual(ProbeError.interrupted.outcome, "中断")
    }
}
