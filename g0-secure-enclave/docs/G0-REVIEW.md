# G0 レビュー資料

状態：実装者による静的点検と自動テストの対象。人のレビューは未実施。G1の確定仕様ではない。

## 実装の範囲

既成APIを呼ぶG0用のローカルアプリ。通信、復号値の返送API、サーバー命令の読込、顧客情報入力、複数端末プロトコルはない。G0の用途付き平文はAPI動作確認専用で、DK所持確認の登録プロトコルが完成したとは扱わない。

## 採用候補API・属性

| 対象 | コードで指定した値 | 実機で確定すること |
| --- | --- | --- |
| 鍵生成 | `SecKeyCreateRandomKey`、`kSecAttrTokenIDSecureEnclave`、`kSecAttrKeyTypeECSECPrimeRandom`、256bit | 作成可否と属性。ソフト鍵への切替なし |
| アクセス制御 | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`、`privateKeyUsage + userPresence` | 本人確認・取消・ロック・OSの認証キャッシュの実挙動 |
| 保存/取得 | `kSecAttrIsPermanent=true`、用途別タグ、`kSecUseDataProtectionKeychain=true` | ad-hoc/開発署名の権限、再起動・再署名後の取得 |
| ECIES | `eciesEncryptionCofactorX963SHA256AESGCM`、対応確認後に既成APIで暗号化・復号 | SE鍵で復号できるか、出力blob長と不正入力の動作。HPKEとは呼ばない |
| ECDSA | `ecdsaSignatureMessageX962SHA256`、DER署名 | 管理者/書込の別鍵で成功し、CryptoKitでも検証できるか |
| 公開鍵 | X9.63非圧縮65bytes、SHA-256指紋 | 3鍵が別で再起動後も同じか |
| 乱数 | `SecRandomCopyBytes`、32bytes | API失敗時に停止すること |

## コードの確認箇所

| ファイル | 確認点 |
| --- | --- |
| `Sources/G0Core/HardwareProbe.swift` | 鍵の用途分離、SE属性確認、API対応確認、既存鍵上書き拒否、取消、鍵タグを限定した削除 |
| `Sources/G0Core/Envelope.swift` | 固定形式・完全長検査、用途/保管庫/epochの完全一致、秘密の出力禁止、ダイジェストの用途分離 |
| `Sources/G0Core/ProbeError.swift` | エラーへ平文・秘密鍵・任意のサーバー文言を含めない。固定操作名と数値のみ |
| `Sources/G0Core/Evidence.swift` | 証跡の許可フィールド、公開鍵指紋のみの継続性比較、受入0と人の未確認の明示 |
| `Sources/G0App/AppModel.swift` | バックグラウンド処理、操作の直列化、ロックでの認証無効化と遅い結果の破棄、指紋記録、書出し |
| `Sources/G0App/ProtectionApp.swift` | 意図的な操作開始、確認画面、削除時の明示確認、観測結果と判定の区別 |
| `Sources/G0Check/main.swift` | 非対話環境照会のみ。鍵生成/参照や本人確認をしない |
| `Tests/G0CoreTests/EnvelopeTests.swift` | 期待バイト列と異常入力、SHA-256既知例、鍵継続性比較、キャンセル後の操作拒否。ハードウェア実証ではない |

## G0専用の用途付き平文

連結順は以下の固定長。区切り文字付きJSONは使わない。

| 順 | 内容 | 長さ |
| --- | --- | --- |
| 1 | ASCII `g0-envelope-v1` とNUL | 15bytes |
| 2 | 用途（VK=1、DKチャレンジ=2） | 1byte |
| 3 | vault UUIDの16bytes | 16bytes |
| 4 | epoch、符号なし64bit、big-endian | 8bytes |
| 5 | 乱数ダミー鍵またはチャレンジ | 32bytes |
| 合計 | 末尾付加・不足・未知用途を拒否 | 72bytes |

DKチャレンジ応答用ダイジェストは `SHA256(ASCII("g0-dk-pop-digest-v1") + NUL + 用途付き平文)`。署名操作はこの32byteダイジェストをメッセージとする既成ECDSA APIを使う。実際のG1では要求ID、鍵束、設定ハッシュ、署名者権限、有効期限と再利用防止を含め再定義する。現実装はその代用ではない。

用途混同試験は自分で生成した入力だけを開く。暗号文を任意に入力するUIや汎用の復号結果返送機能を公開していない。全登録プロトコルの署名検証順序や鍵注入防御はG1/G2/G3に残る。

## 保存・ログ・メモリ

公開鍵指紋の比較ファイルは公開情報のみ。端末鍵欠如・指紋不一致を自動で修復しない。アプリは秘密鍵参照・ダミー平文をオブジェクトの常設キャッシュに保持せず、操作ごとにスコープ内で使う。管理メモリの全コピー即時ゼロ化は保証しない。

レポートのフィールドは環境、公開鍵指紋、真偽、固定名、結果コード、日時。`print`で秘密を出さない。OSやクラッシュダンプまでの無漏えい保証はしない。実機ログとアプリの証跡を人が追加点検する。

ロックは進行中LAContextを無効化し、結果の表示を破棄する。すでにOS内で完了した鍵生成自体は取り消せないため、途中で専用鍵が残る可能性がある。自動削除や自動再生成は行わない。必要時は記録してから専用鍵のみ明示的に片付ける。

## G1へ渡す未確定事項

1. 実機ECIES/署名の成功条件、正確なblob形式と鍵参照の継続性。
2. 署名/entitlement/provisioningの条件、再署名時の鍵アクセス。
3. 本人確認の表示・取消コード・キャッシュ・画面ロック通知と再確認の実測。
4. 本番形式の正規化、AAD、HKDF、vk_commit、DK確認、各鍵確認値とhashの定義。
5. 署名済み設定/有効化、checkpoint、移行中断・是正の状態遷移と保存。
6. 帯域外指紋照合、リリース署名、PoC-Bの別実機準備。

G0の実機結果と人による確認を得てからG1を確定する。
