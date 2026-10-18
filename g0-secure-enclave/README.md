# 顧客情報保護 PoC — G0 実機API検証

このフォルダは開発計画のG0を実装したものです。Mac実機のSecure Enclaveと既成APIの動作を確かめます。保管庫本体・サーバー・2台登録プロトコルはG1以降です。

状態：コード作成済み。自動テストとビルドの結果は `evidence/development-result.md` を参照してください。実機での本人確認・ロック・再起動の確認と人のレビューは別です。受入試験は **0/23** を維持します。

## 最新の再開状況（2026年10月18日）

Xcode [検証環境版非公開]とPersonal Teamの開発用署名を準備し、署名済みアプリで3用途のSE鍵生成とECIES封緘・開封の実機成功を確認しました。初回の `-34018` は解消しています。以降の本文にある10月17日の署名不足の説明は初回ビルドの記録です。本人確認取消時の停止（code=-2）と、アプリ再起動後の同じ3用途の鍵による封緘・署名の再利用も確認済みです。

G0全体の人による判定と統合受入はまだ未実施です。

今後は `xcode/ProtectionG0.xcodeproj` を開き、ProtectionG0ターゲットのSigning & Capabilitiesで利用するTeamを選んで実行できます。既存のソースを参照する構成で、Team IDをソースへ固定していません。端末固有の証明書・プロファイルはGit管理しません。

コマンドからは `G0_DEVELOPMENT_TEAM` を環境変数で指定して `zsh scripts/build-xcode.sh` を使います。`scripts/build-app.sh` は従来の手動/ad-hocビルド用として残しています。現在、通常の `build/ProtectionG0.app` は署名済み版へ差し替え、旧版は `build/archive/` に保管しています。

署名と再試験の最新結果は `evidence/signing-retest-2026-10-18.md` を参照してください。

## まず開くもの

`build/ProtectionG0.app` をダブルクリックしてください。起動だけでは鍵を生成しません。「環境を確認」から始め、`docs/G0-MANUAL-TEST.md` の順に操作します。結果は「観測記録を保存」でJSONに書き出し、人による確認票へ添付します。

アプリがまだない場合は、このフォルダで次を実行します。

```sh
zsh scripts/build-app.sh
open build/ProtectionG0.app
```

macOS 14以降、Apple Silicon Mac、Swift 6以上の開発環境を想定しています。追加ライブラリ・外部サービス・APIトークンは使いません。開発端末ではmacOS [実機OS情報非公開]、[検証CPU情報非公開]、Swift [検証環境版非公開]、Command Line Toolsを確認しました。Xcode.appと有効なコード署名用IDは見つかっていません。

ビルドは既定でローカル確認用のad-hoc署名を使います。Developer IDによる商用配布・公証済みアプリではありません。これでSE鍵へアクセスできるかは実行条件に依存し、未検証です。鍵生成が `code=-34018` 等で失敗した場合は `docs/G0-MANUAL-TEST.md` の環境不足として記録し、正規の署名・権限設定を検討します。ソフト鍵へ切り替える機能はありません。

既に利用可能な署名IDと必要なentitlement/provisioning条件が確認できた場合は、環境変数 `G0_SIGNING_IDENTITY`、`G0_ENTITLEMENTS_FILE`、必要に応じて `G0_PROVISIONING_PROFILE` を指定してビルドできます。Team IDやKeychain共有権限を推測して設定するテンプレートは入れていません。再署名すると既存PoC鍵へのアクセス条件が変わる可能性があるため、署名条件を記録してください。

## 実装した操作

| 操作 | 実装 |
| --- | --- |
| 環境確認 | OS、CPUアーキテクチャ、SE利用可否、本人確認APIの利用可否。本人確認UIは出さない |
| 専用鍵生成 | DK、管理者署名鍵、書込署名鍵を別々にSEで生成。P-256・userPresence・ThisDeviceOnly。既存鍵を上書きしない |
| 秘密鍵の抽出要求 | 3用途の秘密鍵に外部表現を要求。失敗コードと属性を記録。失敗だけで抽出不能性を確定しない |
| 封緘・開封 | 既成ECIES APIで用途付き32byteダミー鍵を往復。等値比較の真偽だけを記録 |
| 用途混同 | VK用途とDKチャレンジ用途を相互に入れ替え、開封後の用途チェックで拒否 |
| 署名 | 管理者・書込鍵で既成ECDSAを使用。正常検証・メッセージ改ざん拒否・CryptoKitでDER署名の相互確認 |
| 鍵継続性 | 初回の3つの公開鍵指紋を保存し、再起動後に照合。鍵欠如を自動再生成しない |
| ロック | 操作者のロック、OSセッション離脱/画面ロック通知、5分無操作で認証コンテキストを無効化。進行中の結果は破棄 |
| 証跡保存 | 公開鍵指紋・真偽・結果コードのみ。自動合格判定や人の承認を偽らない |
| 片付け | 明示的な確認後、このG0の3つの専用タグだけを削除。一般のKeychain全体を操作しない |

毎回の秘密鍵操作で新しい `LAContext` を作り、処理後に無効化します。アプリ内の常設VK/DEK/秘密鍵キャッシュは作っていません。Swiftの管理メモリ中のすべてのコピーの即時消去は保証しません。実際の本人確認表示・OSキャッシュ挙動は人が観測してください。

## テスト

```sh
zsh scripts/test.sh
zsh scripts/check-environment.sh
```

自動テストはG0用符号化、用途・保管庫・世代の拒否、切詰め/末尾付加、指紋比較、レポート、キャンセル直後の操作開始拒否を検証します。実機鍵の生成や本人確認は行いません。`g0-check` は環境照会だけを行い、鍵の生成・参照・認証ダイアログを起動しません。

この端末のCommand Line ToolsにはXCTestがないため、テストは専用の検証プログラムで実行します。失敗時は終了コード1になります。開発ツールに古いPackageDescription定義が混在する問題は、`scripts/swift-env.sh` が現在の公開定義からローカルの補助モジュールを作ることで回避します。システムの開発ツールを書き換えません。

通常環境での読み取り専用照会ではSE・本人確認の利用可能を確認しました。開発ツールの隔離環境内では両方がfalseになったため、両方の結果を `evidence/` に保存しています。利用可能という照会結果と、SE鍵生成・暗号処理の成功は別です。

**今回の実機観測：** アプリ起動と環境確認は成功しましたが、最初のDK生成は `key-create-dk code=-34018` で停止しました。ビルド済みアプリにKeychain用entitlementがないことを確認しています。開発上の状態は「署名条件待ち」です。`docs/SIGNING-SETUP.md` と `evidence/ui-observations.json` を参照してください。

## 保存先・対象データ

- ソースとビルド：このプロジェクトフォルダ内。
- SE鍵のタグ：`jp.customer-protection.poc.g0.v1.dk`、`.admin-sign`、`.writer-sign` の3つのみ。
- 鍵本体：OSのData Protection Keychain/SE。秘密鍵のファイル出力はしません。
- 初回比較用公開鍵指紋：`~/Library/Application Support/jp.customer-protection.poc.g0/public-baseline.json`。公開情報のみ。G1の信頼根保存設計の代替ではありません。
- 観測JSON：操作者が保存先を選択します。`evidence/` にまとめて保管できます。
- ダミー鍵と用途付き平文：操作中のメモリ内のみ。UI・JSON・ログへ出しません。

## レビューの入口

`docs/G0-REVIEW.md` にAPI定数、鍵属性、G0専用形式、コードの確認箇所、未実施項目をまとめました。操作担当・レビュー担当は親フォルダの確認票に記名し、G0が通過するまで依存するG1確定・PoC-A実装へ進めません。

参考： [AppleのSE鍵の説明](https://developer.apple.com/documentation/Security/protecting-keys-with-the-secure-enclave?changes=la)、[ECIES API](https://developer.apple.com/documentation/security/seckeyalgorithm/eciesencryptioncofactorx963sha256aesgcm)、[Data Protection Keychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)。API候補の根拠であり、この実装の安全性認定ではありません。
