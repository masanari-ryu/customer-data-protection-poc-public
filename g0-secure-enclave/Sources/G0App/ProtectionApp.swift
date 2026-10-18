import AppKit
import SwiftUI
import G0Core

@main
struct ProtectionApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("顧客情報保護 PoC — G0 実機検証") {
            ProbeView(model: model)
                .frame(minWidth: 920, minHeight: 660)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.lock(reason: "アプリ終了")
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

struct ProbeView: View {
    @ObservedObject var model: AppModel
    @State private var confirmCleanup = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("顧客情報保護 PoC").font(.title2.bold())
                Text("G0｜Mac実機のAPI検証").font(.headline).foregroundStyle(.secondary)
                Text("架空の32byte鍵だけを使います。顧客データの入力・通信機能はありません。")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Button("1  環境を確認", action: model.checkEnvironment)
                    Button("2  初回の専用鍵を生成", action: model.generate)
                    Button("2  秘密鍵の抽出要求を試す", action: model.checkExtraction)
                    Button("3  封緘・開封を確認", action: model.checkSealing)
                    Button("4  用途の入替を拒否", action: model.checkPurpose)
                    Button("5  署名・改ざんを確認", action: model.checkSignatures)
                    Button("7  同じ鍵を照合", action: model.checkExisting)
                }
                .buttonStyle(.bordered)
                .disabled(model.busy)
                Divider()
                Button("6  ロック／処理を中断") { model.lock(reason: "操作者によるロック") }
                    .buttonStyle(.bordered)
                Button("観測記録を保存", action: model.exportReport)
                    .disabled(model.busy)
                Button("PoC専用鍵を削除…", role: .destructive) { confirmCleanup = true }
                    .disabled(model.busy)
                    .confirmationDialog("G0専用の3用途の鍵と公開鍵指紋記録を削除します。再起動試験の前には実行しないでください。", isPresented: $confirmCleanup) {
                        Button("G0専用鍵だけを削除", role: .destructive, action: model.deleteProbeKeys)
                        Button("取消", role: .cancel) { }
                    }
                Spacer()
                Text("受入試験 0/23\nG0判定：人の確認待ち")
                    .font(.callout.bold()).foregroundStyle(.secondary)
            }
            .padding(24).frame(width: 290)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(model.locked ? "ロック中" : "操作確認済み・キャッシュなし", systemImage: model.locked ? "lock.fill" : "checkmark.shield")
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }.font(.headline)
                Text(model.notice).font(.callout).frame(minHeight: 42, alignment: .topLeading)
                if let env = model.environment {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(env.os)｜\(env.architecture)")
                        Text("SE利用可能：\(env.secureEnclaveAvailable ? "はい" : "いいえ") ／ 本人確認利用可能：\(env.ownerAuthenticationAvailable ? "はい" : "いいえ")")
                        Text("鍵操作・再起動・取消・ロックは別々に確認してください。")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text("観測記録").font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if model.events.isEmpty {
                            Text("まだ実行していません。左側の「環境を確認」から始めてください。")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.events.reversed()) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(event.check).fontWeight(.semibold)
                                    Spacer()
                                    Text(event.outcome).foregroundStyle(.secondary)
                                }
                                Text(event.detail).font(.caption.monospaced()).textSelection(.enabled)
                                Text(event.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("操作の成功とG0通過は別です。本人確認の取消は失敗コードと画面を照合し、手順票に記録します。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}
