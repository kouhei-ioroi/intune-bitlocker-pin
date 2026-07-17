# Intune-BitLocker-PIN

Intuneのアプリケーション配布機能を利用して、Windows の BitLocker に TPM + PIN をサイレント設定し、PIN 変更を促すタスクを登録するスクリプトです。

また、本リポジトリには認証方式を **"TPM + PIN" から "TPM only" へ移行（PIN 要件の削除）するアンインストールスクリプト** も含まれています。

---

## インストール（TPM + PIN の有効化）

1. Releasesから最新のintunewinパッケージと`Verify.ps1`をダウンロードします。
2. Microsoft Intune 管理センターにアクセスし、アプリケーションの追加からWin32アプリを選択します。
3. ダウンロードしたintunewinパッケージをアップロードします。
4. インストールコマンドに以下を指定します。
   ```
   %windir%\SysNative\WindowsPowerShell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -File .\Setup-BitLockerPIN.ps1 -PresetPin "123456"
   ```
5. インストールの処理をシステムに指定します。
6. リターンコードを以下のように設定します。
    - 成功 : 0
    - ハードリブート : 1641
    - 失敗 : 1
7. 検出規則の形式をカスタム検出スクリプトに設定し、`Verify.ps1`を指定します。
8. アプリケーションを割り当て、配信します。

> アンインストールコマンドの指定については、後述の「アンインストール（TPM only への移行）」を参照してください。

---

## アンインストール（TPM + PIN → TPM only への移行）

このスクリプトは、TPM+PIN 構成を解除し、TPM のみの認証へ移行します。
`Source/Uninstall-BitLockerPIN.ps1` を使用してください。

### 前提条件（Prerequisites）

- Windows 10 / 11（BitLocker 対応エディション）
- TPM 1.2 以上が有効／初期化済み
- BitLocker が有効（`FullyEncrypted`）であること
- **管理者権限**（または Intune のシステムコンテキスト）での実行
- 実行前に **BitLocker 回復キー（回復パスワード）を安全な場所へ退避** しておくこと

### 構成手順（Configuration Steps）

1. `Source/Uninstall-BitLockerPIN.ps1` を intunewin パッケージに同梱します。
2. Microsoft Intune 管理センターで、アプリの「アンインストールコマンド」に以下を指定します。
   ```
   %windir%\SysNative\WindowsPowerShell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -File .\Uninstall-BitLockerPIN.ps1
   ```
3. リターンコードを以下のように設定します。
    - 成功（TPM only への移行完了） : 0
    - 失敗 : 1
4. （任意）アンインストール後の検出規則として、TPM のみであることを確認するスクリプトを設定します（下記「検証」参照）。
5. アプリケーションを割り当て、アンインストール（削除）を配信します。

### スクリプトの処理内容

1. 管理者権限の確認
2. BitLocker 状態とキープロテクターの取得
3. `TpmPin` キープロテクターの削除（PIN 要件の除去）
4. `Tpm` キープロテクターの確認／不足時は追加（TPM only を保証）
5. PIN 変更を促すスケジュールタスク（`EnforceBitLockerPIN`）の削除
6. PIN 変更完了フラグファイル（`C:\Scripts\.PinChanged`）の削除
7. 移行結果の検証とリターンコードの決定

### 検証（Verification）

スクリプトは終了前に以下を検証し、すべて満たせば `0`、いずれか失敗で `1` を返します。

- `TpmPin` キープロテクターが存在しないこと
- `Tpm` キープロテクターが存在すること
- スケジュールタスク `EnforceBitLockerPIN` が存在しないこと
- フラグファイル `C:\Scripts\.PinChanged` が存在しないこと

実行ログは `C:\Scripts\Uninstall-BitLockerPIN.log` に記録されます。
アンインストール後の状態は以下で確認できます。

```powershell
Get-BitLockerVolume -MountPoint $env:SystemDrive | Select-Object VolumeStatus, @{n='Protectors';e={$_.KeyProtector.KeyProtectorType -join ', '}}
```

### 影響評価（Impact Assessment）

| 項目 | 影響 |
| --- | --- |
| 認証方式 | 起動時に PIN 入力が不要になり、TPM のみでロック解除されます（利便性向上）。 |
| セキュリティ | PIN（所持+知識の多要素）が外れるため、物理アクセスへの耐性は低下します。ポリシー上の許容を確認してください。 |
| ユーザー体験 | 再起動時の PIN プロンプトが消えます。ユーザーへの事前周知を推奨します。 |
| 回復 | 回復キーによる回復は引き続き可能です。削除前の退避を徹底してください。 |
| 他機能 | 暗号化状態・回復パスワード・その他のキープロテクターは維持されます。 |
| ロールバック | 必要に応じて再度 `Setup-BitLockerPIN.ps1 -PresetPin "..."` を実行し、TPM+PIN へ戻せます。 |

---

## 旧手順（参考）

過去の README ではアンインストールコマンドに `Setup-BitLockerPIN.ps1`（引数なし）を指定していましたが、
実質的には機能せず必須項目のためのダミーでした。本リポジトリでは上記 `Uninstall-BitLockerPIN.ps1` が実際の移行を行います。
