# 顧客情報保護 PoC

公開用に個人情報・価格案・内部URL・実機情報をマスキングしています。[公開版の扱い](PUBLIC-RELEASE.md)を参照してください。

登録端末で顧客本文を暗号化・復号し、サーバーだけでは本文を復号できない構成を検証するための開発プロジェクトです。

## 最新状況（2026年10月18日）

Xcode [検証環境版非公開]／Swift [検証環境版非公開]とPersonal Teamの開発用署名を準備し、実機で3用途のSE鍵生成、ECIES封緘・開封、用途入替拒否、管理者・書込鍵のECDSA署名と改ざん拒否が成功しました。初回の署名権限エラー `-34018` は解消しています。本人確認の一部は操作者の協力で実施しています。

本人確認取消時の停止（code=-2）と、アプリ再起動後の同じ3用途の鍵による封緘・署名の再利用も確認済みです。

G0全体の判定・独立レビュー・統合受入は未実施です。最新の観測と残る手順は [署名後の再試験記録](g0-secure-enclave/evidence/signing-retest-2026-10-18.md) を参照してください。

開発用の再ビルドは `g0-secure-enclave/xcode/ProtectionG0.xcodeproj` をXcodeで開き、ProtectionG0ターゲットのTeamを選んで実行できます。Team固有の証明書・プロファイルをGitへ保存しない構成です。

## 初回実装時の記録（2026年10月17日）

2026年10月17日時点で、**G0のMac実機API検証アプリを実装**しています。保管庫本体、サーバー、PoC-A/B全体は未実装です。

- 自動テスト：14項目・117 assertionsが成功。
- [検証CPU情報非公開]アプリのビルド・起動・環境照会：成功。
- 実機の専用DK生成：`-34018`（署名権限不足）で停止。開発用署名・Keychain権限の準備が必要です。
- SE鍵による封緘・署名・本人確認・ロック・再起動試験と、人によるG0レビュー：未実施。
- 統合受入試験：0/23。独立専門家レビュー：未実施。

G0通過や安全性検証済みの製品としては扱いません。ソフトウェア鍵へ自動で切り替える機能はありません。

## 開発と確認

```sh
cd g0-secure-enclave
zsh scripts/test.sh
zsh scripts/check-environment.sh
zsh scripts/build-app.sh
open build/ProtectionG0.app
```

macOS 14以降、Apple Silicon Mac、Swift 6以上を想定しています。追加の外部ライブラリ・APIトークンは不要です。ビルドの既定はローカル起動確認用のad-hoc署名です。実機鍵の試験には、実際の開発用署名・アプリ識別子・Keychain権限を整える必要があります。

ビルド済みアプリ、キャッシュ、秘密鍵・証明書・プロファイルなどの署名材料はGitへ含めません。実機秘密鍵はOSのKeychain/SEで管理し、証跡には鍵値を含めません。

## 資料

| 資料 | 内容 |
| --- | --- |
| [開発フェーズ計画](poc-development-plan.md) | G0〜G5、成果物、人の確認、通過・差戻し条件 |
| [受入試験台帳](poc-test-register.md) | T01〜T23と実施・確認状態 |
| [人による確認票](poc-human-review-template.md) | 操作・レビュー・指摘・判定の記録 |
| [G0の説明](g0-secure-enclave/README.md) | 実装範囲、ビルド、保存先 |
| [実機操作手順](g0-secure-enclave/docs/G0-MANUAL-TEST.md) | 正常・取消・異常・再起動の試験 |
| [署名条件の準備](g0-secure-enclave/docs/SIGNING-SETUP.md) | 現在の停止理由と再開手順 |
| [レビュー資料](g0-secure-enclave/docs/G0-REVIEW.md) | API・鍵属性・形式・コード確認箇所 |
| [開発結果](g0-secure-enclave/evidence/development-result.md) | 自動検証・実機観測・未実施事項 |

G0の実測結果と人の確認を得てから、G1の仕様確定、PoC-A、PoC-Bへ進みます。
