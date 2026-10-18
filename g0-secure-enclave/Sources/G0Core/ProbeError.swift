import Foundation
import Security
import LocalAuthentication

public enum ProbeError: Error, Equatable, Sendable {
    case invalidEnvelope
    case wrongContext
    case hardwareUnavailable
    case keyMissing
    case keyAlreadyExists
    case invalidHardwareKey
    case unsupportedAlgorithm
    case verificationFailed
    case exportUnexpectedlySucceeded
    case fingerprintsChanged
    case baselineMissing
    case locked
    case interrupted
    case cancelled(code: Int)
    case system(operation: String, code: Int)

    // Only fixed operation identifiers and numeric errors cross the UI/report boundary.
    public var safeDescription: String {
        switch self {
        case .invalidEnvelope: return "G0-FORMAT: 用途付き入力の形式・長さが不正です"
        case .wrongContext: return "G0-CONTEXT: 用途・保管庫・世代が一致しません"
        case .hardwareUnavailable: return "E01: Secure Enclaveを利用できません"
        case .keyMissing: return "G0-MISSING: 専用鍵がありません。自動再生成せず停止しました"
        case .keyAlreadyExists: return "G0-EXISTS: 専用鍵が既に存在します。上書きしません"
        case .invalidHardwareKey: return "G0-ATTR: SE・P-256秘密鍵の属性を確認できません"
        case .unsupportedAlgorithm: return "G0-API: この鍵で候補APIを利用できません"
        case .verificationFailed: return "G0-VERIFY: 検証が期待値と一致しません"
        case .exportUnexpectedlySucceeded: return "G0-EXPORT: 秘密鍵の外部表現要求が成功しました。要調査"
        case .fingerprintsChanged: return "G0-IDENTITY: 記録した公開鍵指紋と一致しません"
        case .baselineMissing: return "G0-BASELINE: 再起動比較用の公開鍵指紋記録がありません"
        case .locked: return "E02: ロック中です。本人確認を伴う操作から再開してください"
        case .interrupted: return "G0-INTERRUPTED: ロック・離席・終了操作により結果を破棄しました"
        case let .cancelled(code): return "E02: 本人確認が取り消されました code=\(code)"
        case let .system(operation, code): return "G0-SYSTEM: \(operation) code=\(code)"
        }
    }

    public static func status(_ operation: String, _ code: OSStatus) -> ProbeError {
        if code == errSecUserCanceled { return .cancelled(code: Int(code)) }
        return .system(operation: operation, code: Int(code))
    }

    static func security(_ operation: String, _ error: Unmanaged<CFError>?) -> ProbeError {
        guard let error else { return .system(operation: operation, code: -1) }
        let value = error.takeRetainedValue()
        let code = CFErrorGetCode(value)
        if code == Int(errSecUserCanceled) ||
            (CFErrorGetDomain(value) as String == LAError.errorDomain && [-2, -4, -9].contains(code)) {
            return .cancelled(code: code)
        }
        return .system(operation: operation, code: code)
    }

    public var outcome: String {
        switch self {
        case .cancelled: return "取消"
        case .interrupted: return "中断"
        default: return "失敗"
        }
    }
}
