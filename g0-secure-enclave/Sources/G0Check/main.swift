import Foundation
import G0Core

// Read-only environment report. No key generation, key lookup or authentication UI.
let report = ProbeReport(environment: ProbeEnvironment.current(), events: [
    ProbeEvent(check: "G0-01-noninteractive", outcome: "観測",
               detail: "環境照会のみ。鍵生成・ECIES・署名・本人確認・ロック・再起動は未実施")
])
do {
    FileHandle.standardOutput.write(try report.json())
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("環境レポート生成失敗\n".utf8))
    exit(1)
}
