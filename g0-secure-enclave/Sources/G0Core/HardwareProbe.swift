import Foundation
import Security
import CryptoKit
import LocalAuthentication

enum KeyRole: String, CaseIterable {
    case device = "dk"
    case administrator = "admin-sign"
    case writer = "writer-sign"

    var tag: Data { Data("jp.customer-protection.poc.g0.v1.\(rawValue)".utf8) }
}

// UI serializes probes. The lock protects only cancellation/context bookkeeping;
// slow Security.framework calls run on a background task and can be invalidated.
public final class HardwareProbe: @unchecked Sendable {
    public static let encryptionAlgorithm = "eciesEncryptionCofactorX963SHA256AESGCM"
    public static let signatureAlgorithm = "ecdsaSignatureMessageX962SHA256 / ASN.1 DER"
    private let mutex = NSLock()
    private var contexts: [UUID: LAContext] = [:]
    private var generation: UInt64 = 0
    private var operationGeneration: UInt64 = 0
    private let vaultID = UUID(uuidString: "9ef7732c-571b-45da-9076-d7834b123b10")!
    private let encryption: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM
    private let signature: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256

    public init() {}

    public func prepareOperation() {
        mutex.lock()
        operationGeneration = generation
        mutex.unlock()
    }

    public func cancel() {
        mutex.lock()
        generation &+= 1
        let pending = Array(contexts.values)
        mutex.unlock()
        pending.forEach { $0.invalidate() }
    }

    private func withContext<T>(_ body: (LAContext, UInt64) throws -> T) throws -> T {
        let context = LAContext()
        context.localizedReason = "G0検証の専用ハードウェア鍵を使用します"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        let id = UUID()
        mutex.lock()
        guard operationGeneration == generation else {
            mutex.unlock()
            context.invalidate()
            throw ProbeError.interrupted
        }
        let token = generation
        contexts[id] = context
        mutex.unlock()
        defer {
            context.invalidate()
            mutex.lock()
            contexts.removeValue(forKey: id)
            mutex.unlock()
        }
        let value = try body(context, token)
        try ensureCurrent(token)
        return value
    }

    private func ensureCurrent(_ token: UInt64) throws {
        mutex.lock()
        let current = generation
        mutex.unlock()
        guard token == current else { throw ProbeError.interrupted }
    }

    private func query(_ role: KeyRole, context: LAContext) -> [String: Any] {
        [kSecClass as String: kSecClassKey,
         kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
         kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
         kSecAttrApplicationTag as String: role.tag,
         kSecUseDataProtectionKeychain as String: true,
         kSecUseAuthenticationContext as String: context]
    }

    private func exists(_ role: KeyRole) throws -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        defer { context.invalidate() }
        var attributes = query(role, context: context)
        attributes[kSecReturnAttributes as String] = true
        let status = SecItemCopyMatching(attributes as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        // An existing protected item may disallow even a noninteractive lookup.
        if status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed { return true }
        throw ProbeError.status("key-exists", status)
    }

    private func load(_ role: KeyRole, context: LAContext) throws -> SecKey {
        var attributes = query(role, context: context)
        attributes[kSecReturnRef as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { throw ProbeError.keyMissing }
        guard status == errSecSuccess, let result else { throw ProbeError.status("key-load", status) }
        guard CFGetTypeID(result) == SecKeyGetTypeID() else { throw ProbeError.invalidHardwareKey }
        let key = result as! SecKey
        try validateHardware(key)
        return key
    }

    private func validateHardware(_ key: SecKey) throws {
        guard let attributes = SecKeyCopyAttributes(key) as? [String: Any],
              attributes[kSecAttrTokenID as String] as? String == kSecAttrTokenIDSecureEnclave as String,
              attributes[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeECSECPrimeRandom as String,
              attributes[kSecAttrKeyClass as String] as? String == kSecAttrKeyClassPrivate as String,
              attributes[kSecAttrKeySizeInBits as String] as? Int == 256 else {
            throw ProbeError.invalidHardwareKey
        }
    }

    private func publicKey(_ key: SecKey) throws -> SecKey {
        guard let value = SecKeyCopyPublicKey(key) else { throw ProbeError.invalidHardwareKey }
        return value
    }

    private func publicFingerprint(_ key: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let bytes = SecKeyCopyExternalRepresentation(try publicKey(key), &error) as Data? else {
            throw ProbeError.security("public-export", error)
        }
        guard bytes.count == 65, bytes.first == 4 else { throw ProbeError.invalidHardwareKey }
        return fingerprint(bytes)
    }

    public func generateKeys() throws -> [String: String] {
        guard SecureEnclave.isAvailable else { throw ProbeError.hardwareUnavailable }
        for role in KeyRole.allCases {
            if try exists(role) { throw ProbeError.keyAlreadyExists }
        }
        var fingerprints: [String: String] = [:]
        for role in KeyRole.allCases {
            let value = try withContext { context, token in
                try ensureCurrent(token)
                var error: Unmanaged<CFError>?
                guard let access = SecAccessControlCreateWithFlags(
                    nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error
                ) else { throw ProbeError.security("access-control", error) }
                let attributes: [String: Any] = [
                    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                    kSecAttrKeySizeInBits as String: 256,
                    kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
                    kSecUseDataProtectionKeychain as String: true,
                    kSecUseAuthenticationContext as String: context,
                    kSecPrivateKeyAttrs as String: [
                        kSecAttrIsPermanent as String: true,
                        kSecAttrApplicationTag as String: role.tag,
                        kSecAttrAccessControl as String: access
                    ]
                ]
                guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
                    throw ProbeError.security("key-create-\(role.rawValue)", error)
                }
                try validateHardware(key)
                return try publicFingerprint(key)
            }
            fingerprints[role.rawValue] = value
        }
        guard Set(fingerprints.values).count == 3 else { throw ProbeError.verificationFailed }
        return fingerprints
    }

    public func verifyExistingKeys(against baseline: PublicBaseline) throws -> [ProbeEvent] {
        var current: [String: String] = [:]
        // A real private-key signature/decrypt is performed separately; public fingerprint
        // comparison alone does not demonstrate private-key usability after reboot.
        for role in KeyRole.allCases {
            current[role.rawValue] = try withContext { context, _ in
                try publicFingerprint(load(role, context: context))
            }
        }
        try baseline.validate(current)
        return [ProbeEvent(check: "G0-07-fingerprint", outcome: "成功",
                           detail: "3用途の公開鍵SHA-256指紋が初回記録と一致。秘密鍵の再利用確認には封緘/署名を続けて実施")]
    }

    public func checkExtraction() throws -> [ProbeEvent] {
        var results: [ProbeEvent] = []
        for role in KeyRole.allCases {
            let event = try withContext { context, _ in
                let key = try load(role, context: context)
                var error: Unmanaged<CFError>?
                let representation = SecKeyCopyExternalRepresentation(key, &error)
                guard representation == nil else { throw ProbeError.exportUnexpectedlySucceeded }
                guard let error else { throw ProbeError.verificationFailed }
                let code = CFErrorGetCode(error.takeRetainedValue())
                return ProbeEvent(check: "G0-02-export-\(role.rawValue)", outcome: "観測",
                                  detail: "SE/P-256秘密鍵属性確認済み。外部表現要求は失敗 code=\(code)。拒否理由は人が照合")
            }
            results.append(event)
        }
        return results
    }

    private func encrypt(_ bytes: Data, to publicKey: SecKey) throws -> Data {
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, encryption) else { throw ProbeError.unsupportedAlgorithm }
        var error: Unmanaged<CFError>?
        guard let blob = SecKeyCreateEncryptedData(publicKey, encryption, bytes as CFData, &error) as Data? else {
            throw ProbeError.security("ecies-encrypt", error)
        }
        return blob
    }

    private func decrypt(_ blob: Data, with key: SecKey) throws -> Data {
        guard SecKeyIsAlgorithmSupported(key, .decrypt, encryption) else { throw ProbeError.unsupportedAlgorithm }
        var error: Unmanaged<CFError>?
        guard let bytes = SecKeyCreateDecryptedData(key, encryption, blob as CFData, &error) as Data? else {
            throw ProbeError.security("ecies-decrypt", error)
        }
        return bytes
    }

    public func checkSealing() throws -> [ProbeEvent] {
        try withContext { context, token in
            let key = try load(.device, context: context)
            let expected = try ProbeEnvelope(purpose: .vaultKey, vaultID: vaultID, epoch: 1, secret: secureRandom32()).encoded()
            let blob = try encrypt(expected, to: publicKey(key))
            let opened = try decrypt(blob, with: key)
            _ = try ProbeEnvelope.decode(opened, purpose: .vaultKey, vaultID: vaultID, epoch: 1)
            guard expected == opened else { throw ProbeError.verificationFailed }
            try ensureCurrent(token)
            return [ProbeEvent(check: "G0-03-ecies", outcome: "成功",
                               detail: "\(Self.encryptionAlgorithm)、用途付き32byte鍵の往復一致=true、blob=\(blob.count)bytes。鍵値/平文は記録しない")]
        }
    }

    public func checkPurposeSeparation() throws -> [ProbeEvent] {
        // No remote inputs or generic decrypt endpoint: only internally generated probes.
        try withContext { context, token in
            let key = try load(.device, context: context)
            var events: [ProbeEvent] = []
            for actual in ProbePurpose.allCases {
                let expected: ProbePurpose = actual == .vaultKey ? .deviceChallenge : .vaultKey
                let data = try ProbeEnvelope(purpose: actual, vaultID: vaultID, epoch: 1, secret: secureRandom32()).encoded()
                let blob = try encrypt(data, to: publicKey(key))
                let opened = try decrypt(blob, with: key)
                do {
                    _ = try ProbeEnvelope.decode(opened, purpose: expected, vaultID: vaultID, epoch: 1)
                    throw ProbeError.verificationFailed
                } catch ProbeError.wrongContext {
                    events.append(ProbeEvent(check: "G0-04-purpose-\(actual.rawValue)", outcome: "成功",
                                             detail: "逆用途の入力を拒否。復号値を応答・ログへ返さない"))
                }
                try ensureCurrent(token)
            }
            return events
        }
    }

    public func checkSignatures() throws -> [ProbeEvent] {
        var events: [ProbeEvent] = []
        for role in [KeyRole.administrator, .writer] {
            let event = try withContext { context, token in
                let key = try load(role, context: context)
                guard SecKeyIsAlgorithmSupported(key, .sign, signature) else { throw ProbeError.unsupportedAlgorithm }
                let envelope = try ProbeEnvelope(purpose: .deviceChallenge, vaultID: vaultID, epoch: 1, secret: secureRandom32()).encoded()
                let message = challengeDigest(envelope)
                var error: Unmanaged<CFError>?
                guard let signed = SecKeyCreateSignature(key, signature, message as CFData, &error) as Data? else {
                    throw ProbeError.security("ecdsa-sign", error)
                }
                let publicKey = try publicKey(key)
                guard SecKeyVerifySignature(publicKey, signature, message as CFData, signed as CFData, &error) else {
                    throw ProbeError.security("ecdsa-verify", error)
                }
                var altered = message
                altered[0] ^= 1
                var invalidError: Unmanaged<CFError>?
                let invalidAccepted = SecKeyVerifySignature(publicKey, signature, altered as CFData, signed as CFData, &invalidError)
                if let invalidError { _ = invalidError.takeRetainedValue() }
                guard !invalidAccepted else { throw ProbeError.verificationFailed }
                var alteredSignature = signed
                alteredSignature[0] ^= 1
                var signatureError: Unmanaged<CFError>?
                let badSignatureAccepted = SecKeyVerifySignature(publicKey, signature, message as CFData,
                                                                  alteredSignature as CFData, &signatureError)
                if let signatureError { _ = signatureError.takeRetainedValue() }
                guard !badSignatureAccepted else { throw ProbeError.verificationFailed }
                // Independent system parser also checks the DER public/signature representation.
                var pubError: Unmanaged<CFError>?
                guard let pubBytes = SecKeyCopyExternalRepresentation(publicKey, &pubError) as Data? else {
                    throw ProbeError.security("public-export", pubError)
                }
                let cryptoKey = try P256.Signing.PublicKey(x963Representation: pubBytes)
                let cryptoSig = try P256.Signing.ECDSASignature(derRepresentation: signed)
                guard cryptoKey.isValidSignature(cryptoSig, for: message) else { throw ProbeError.verificationFailed }
                try ensureCurrent(token)
                return ProbeEvent(check: "G0-05-\(role.rawValue)", outcome: "成功",
                                  detail: "\(Self.signatureAlgorithm)、正常=true/本文改ざん=false/署名改ざん=false、公開鍵=X9.63 65bytes、CryptoKit検証=true")
            }
            events.append(event)
        }
        return events
    }

    // Called only by an explicit destructive-action confirmation in the G0 UI.
    // Exact private-key tags prevent touching a user's other Keychain items.
    public func deleteProbeKeys() throws -> [ProbeEvent] {
        try withContext { context, token in
            for role in KeyRole.allCases {
                try ensureCurrent(token)
                let status = SecItemDelete(query(role, context: context) as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw ProbeError.status("probe-key-delete", status)
                }
            }
            return [ProbeEvent(check: "G0-cleanup", outcome: "観測", detail: "g0.v1の3つの専用鍵タグのみ削除。次の生成は別鍵として扱う")]
        }
    }
}
