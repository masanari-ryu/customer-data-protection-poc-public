import Foundation
import CryptoKit
import LocalAuthentication

public struct ProbeEnvironment: Codable, Sendable {
    public let os: String
    public let architecture: String
    public let secureEnclaveAvailable: Bool
    public let ownerAuthenticationAvailable: Bool
    public let authenticationErrorCode: Int?
    public let bundleIdentifier: String
    public let build: String

    public static func current() -> ProbeEnvironment {
        let context = LAContext()
        defer { context.invalidate() }
        var error: NSError?
        let authentication = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "other"
        #endif
        return ProbeEnvironment(os: ProcessInfo.processInfo.operatingSystemVersionString,
                                architecture: architecture,
                                secureEnclaveAvailable: SecureEnclave.isAvailable,
                                ownerAuthenticationAvailable: authentication,
                                authenticationErrorCode: error?.code,
                                bundleIdentifier: Bundle.main.bundleIdentifier ?? "unbundled-check",
                                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development")
    }
}

public struct ProbeEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let check: String
    public let outcome: String
    public let detail: String

    public init(check: String, outcome: String, detail: String) {
        self.id = UUID()
        self.date = Date()
        self.check = check
        self.outcome = outcome
        self.detail = detail
    }
}

public struct ProbeReport: Encodable, Sendable {
    public let format = "g0-evidence-v1"
    public let environment: ProbeEnvironment
    public let events: [ProbeEvent]
    public let acceptanceTestsPassed = 0
    public let humanReview = "未実施（このJSONはアプリの観測記録）"
    public let pending = ["本人確認の成功・取消・失敗の人による照合", "画面ロック後の再確認", "5分無操作後の再確認", "アプリ再起動とOS再起動後の同一鍵利用", "再署名後の鍵アクセス", "コード・実機ログの人によるレビュー", "G1仕様確定", "T01〜T23統合受入"]

    public init(environment: ProbeEnvironment, events: [ProbeEvent]) {
        self.environment = environment
        self.events = events
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

// This baseline contains public fingerprints only. It is a G0 restart comparison,
// not the production trust-anchor storage design.
public struct PublicBaseline: Codable, Equatable, Sendable {
    public let fingerprints: [String: String]
    public let createdAt: Date

    public init(fingerprints: [String: String], createdAt: Date = Date()) {
        self.fingerprints = fingerprints
        self.createdAt = createdAt
    }

    public func validate(_ current: [String: String]) throws {
        guard fingerprints == current else { throw ProbeError.fingerprintsChanged }
    }
}
