import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import G0Core

@MainActor
final class AppModel: ObservableObject {
    @Published var environment: ProbeEnvironment?
    @Published var events: [ProbeEvent] = []
    @Published var busy = false
    @Published var notice = "最初に環境を確認してください。鍵はボタン操作でのみ生成します。"
    @Published var locked = true
    private let hardware = HardwareProbe()
    private var operationID = UUID()
    private var lastInput = Date()
    private var localMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.lastInput = Date() }
            return event
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lock(reason: "OSセッション非アクティブ") }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lock(reason: "画面ロック通知") }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if Date().timeIntervalSince(self.lastInput) >= 300 && (!self.locked || self.busy) {
                    self.lock(reason: "5分無操作")
                }
            }
        }
    }

    private var baselineURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jp.customer-protection.poc.g0", isDirectory: true)
            .appendingPathComponent("public-baseline.json")
    }

    func checkEnvironment() {
        environment = ProbeEnvironment.current()
        guard let env = environment else { return }
        events.append(ProbeEvent(check: "G0-01-environment", outcome: "観測",
                                 detail: "SE利用可能=\(env.secureEnclaveAvailable)、本人確認利用可能=\(env.ownerAuthenticationAvailable)。鍵操作成功の証拠とは別"))
        notice = env.secureEnclaveAvailable ? "環境を記録しました。初回は専用鍵を生成してください。" : "E01: この環境ではSecure Enclaveを利用できません。停止します。"
    }

    func generate() {
        guard !FileManager.default.fileExists(atPath: baselineURL.path) else {
            notice = "公開鍵指紋が記録済みです。「同じ鍵を照合」を使ってください。"
            return
        }
        let url = baselineURL
        run("G0-02-generate") { [hardware] in
            let fingerprints = try hardware.generateKeys()
            let baseline = PublicBaseline(fingerprints: fingerprints)
            let data = try JSONEncoder().encode(baseline)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return fingerprints.sorted(by: { $0.key < $1.key }).map {
                ProbeEvent(check: "G0-02-\($0.key)", outcome: "成功",
                           detail: "SE/P-256専用鍵生成。公開鍵SHA-256=\($0.value)")
            }
        }
    }

    func checkExisting() {
        let url = baselineURL
        run("G0-07-existing") { [hardware] in
            guard FileManager.default.fileExists(atPath: url.path) else { throw ProbeError.baselineMissing }
            let baseline = try JSONDecoder().decode(PublicBaseline.self, from: Data(contentsOf: url))
            return try hardware.verifyExistingKeys(against: baseline)
        }
    }

    func checkExtraction() { run("G0-02-extraction") { [hardware] in try hardware.checkExtraction() } }
    func checkSealing() { run("G0-03-sealing") { [hardware] in try hardware.checkSealing() } }
    func checkPurpose() { run("G0-04-purpose") { [hardware] in try hardware.checkPurposeSeparation() } }
    func checkSignatures() { run("G0-05-signature") { [hardware] in try hardware.checkSignatures() } }

    func deleteProbeKeys() {
        let url = baselineURL
        run("G0-cleanup") { [hardware] in
            let results = try hardware.deleteProbeKeys()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return results
        }
    }

    private func run(_ check: String, action: @escaping @Sendable () throws -> [ProbeEvent]) {
        guard !busy else { return }
        guard let environment, environment.secureEnclaveAvailable else {
            notice = "環境確認でSecure Enclaveの利用可否を確かめてください。"
            return
        }
        busy = true
        lastInput = Date()
        let id = UUID()
        operationID = id
        hardware.prepareOperation()
        notice = "実行中。本人確認を求められたら、試験条件に従って承認または取消してください。"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                do { return Result<[ProbeEvent], ProbeError>.success(try action()) }
                catch let error as ProbeError { return .failure(error) }
                catch { return .failure(.system(operation: "local-operation", code: (error as NSError).code)) }
            }.value
            busy = false
            guard operationID == id else {
                notice = "ロック中に実行した処理の結果を破棄しました。本人確認を伴う操作で再確認してください。"
                return
            }
            switch result {
            case .success(let results):
                events += results
                // Only actual successful private-key use is evidence of authentication.
                if check == "G0-03-sealing" || check == "G0-04-purpose" || check == "G0-05-signature" {
                    locked = false
                }
                lastInput = Date()
                notice = "この操作を記録しました。G0全体の通過判定は人による確認後です。"
            case .failure(let error):
                locked = true
                hardware.cancel()
                events.append(ProbeEvent(check: check, outcome: error.outcome, detail: error.safeDescription))
                notice = error.safeDescription
            }
        }
    }

    func lock(reason: String) {
        operationID = UUID()
        hardware.cancel()
        locked = true
        notice = "ロックしました。次の秘密鍵操作は新しい本人確認コンテキストで実行します。"
        events.append(ProbeEvent(check: "G0-06-lock", outcome: "観測", detail: reason + "。進行中コンテキストを無効化、秘密鍵参照・平文の常設キャッシュなし"))
    }

    func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "g0-evidence-\(Int(Date().timeIntervalSince1970)).json"
        panel.message = "公開鍵指紋・真偽・結果コードのみ。人によるレビュー記録は別票です。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let report = ProbeReport(environment: environment ?? ProbeEnvironment.current(), events: events)
            try report.json().write(to: url, options: [.atomic])
            notice = "観測記録を保存しました。秘密の鍵値・ダミー平文は含めていません。"
        } catch {
            notice = "記録の保存に失敗しました code=\((error as NSError).code)"
        }
    }
}
