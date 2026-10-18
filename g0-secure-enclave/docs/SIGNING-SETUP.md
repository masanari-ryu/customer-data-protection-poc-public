# G0を再開するための署名条件

## 解消記録（2026年10月18日）

Personal Teamで開発用証明書を作成した後、Apple公式のWWDR G3中間証明書を検証してユーザーKeychainへ補い、署名IDを有効として認識できました。常に信頼する等の信頼例外は作成していません。G3はApple Developmentの発行に使われる中間証明書です。[Appleの説明](https://developer.apple.com/help/account/certificates/wwdr-intermediate-certificates/)

`xcode/ProtectionG0.xcodeproj` を用意し、Xcodeの自動署名でアプリIDとTeamに整合する開発プロファイルを作成。署名済み版で専用DKを含む3用途のSE鍵生成が成功し、初回の-34018は解消しました。署名の観測記録と残るG0試験は `../evidence/signing-retest-2026-10-18.md` を参照してください。

同じ構成の再ビルドはXcodeでTeamを選ぶか、環境変数 `G0_DEVELOPMENT_TEAM` を指定して `scripts/build-xcode.sh` を実行します。プロファイル・証明書・Team固有の設定をGitへ含めません。Personal Teamのプロファイルは期限付きなので、期限後はXcodeで再生成・再ビルドして再確認します。

## 初回に確認した不足（2026年10月17日）

現在のローカルad-hocビルドは起動できるが、専用DK生成が `-34018` で失敗する。ビルド済みアプリのentitlementは空で、開発署名用IDは0件。API定数・暗号方式が不成立という結論にはしない。

`-34018` は必要なentitlementの不足を示す。MacのData Protection Keychainは、アプリ識別子やKeychainアクセス権限をもとにアクセスを判断する。コードには他アプリのアクセスグループを指定していないため、現在のアプリ自身の有効な署名と識別の条件を整える必要がある。参考： [Appleのエラー定義](https://developer.apple.com/documentation/security/errsecmissingentitlement?changes=_2_4)、[Apple DTSの確認手順](https://developer.apple.com/forums/thread/114456)。

## 次に確認すること

1. 利用できるAppleの開発用署名証明書、対応する秘密鍵とTeam、必要なプロファイルがあるかを確認する。既存組織のTeamを使う場合はその開発権限が必要。
2. Xcodeを使う場合は、公式のXcodeでアカウントとTeamの利用可否を本人が確認する。現端末にXcode.appはない。インストール、アカウントログイン、契約同意や新規費用の発生はこの開発では行っていない。
3. 専用bundle ID `jp.customer-protection.poc.g0` と一致するアプリ識別子/権限を構成する。Team ID、App ID prefix、Keychainグループを推測して埋めない。有償加入の要否は利用できるTeamと権限を確認してから判断する。
4. ビルド済みアプリに実際に入ったentitlementと署名を確認する。入力用entitlementファイルだけの確認で済ませない。プロファイルが必要な構成ではアプリへ埋め込む。
5. 再署名後に起動→環境確認→鍵生成を再試行。成功したらG0操作票の抽出要求・封緘・用途・署名・本人確認・再起動へ進む。

署名条件が用意できるまでのG0判定は「環境/署名条件不足」。実機試験をソフト鍵で置き換えたり、Keychainアクセス検証を無効化したりしない。

## ビルド手順の対応

`scripts/build-app.sh` は以下の既存材料を受け取れる。

| 環境変数 | 指定するもの |
| --- | --- |
| `G0_SIGNING_IDENTITY` | 既にインストール済みの有効なコード署名ID |
| `G0_ENTITLEMENTS_FILE` | 実際のTeam/App IDと整合するentitlementファイルのパス |
| `G0_PROVISIONING_PROFILE` | 必要な場合、承認されたMac用プロファイルのパス |

未指定時はad-hocの起動確認用になる。これらの材料をアプリが自動発行・登録する機能はない。ビルド後は署名整合性検査に加え、実際の鍵生成で権限が受理されたかを確認する。開発署名の成功を商用配布の安全性と同一視しない。
