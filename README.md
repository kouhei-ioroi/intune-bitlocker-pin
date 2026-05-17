# intune-bitlocker-pin

Windows の BitLocker に TPM + PIN を設定し、PIN 変更を促すための PowerShell スクリプト集です。  
Intune から配布する運用を想定しており、初期設定・スケジュール タスク登録・状態確認を分けて実行できます。

## 目的

- BitLocker が未有効の端末に対して、回復パスワードと TPM + PIN を設定する
- 既に TPM のみで保護されている端末を TPM + PIN に移行する
- PIN 変更用の画面を起動するタスクをログオン時に実行する
- 変更完了後はタスクや補助スクリプトを片付ける

## ファイル構成

- [Setup-BitLockerPIN.ps1](Setup-BitLockerPIN.ps1): BitLocker の初期設定を行い、必要に応じてスケジュール タスクを登録する
- [Register-Task.ps1](Register-Task.ps1): [Enforce-BitLockerPIN.ps1](Enforce-BitLockerPIN.ps1) を `C:\Scripts` に配置し、ログオン時に実行するタスクを作成する
- [Enforce-BitLockerPIN.ps1](Enforce-BitLockerPIN.ps1): PIN 変更画面を繰り返し起動し、変更完了を検知したら後処理を行う
- [Verify-BitLockerPIN.ps1](Verify-BitLockerPIN.ps1): BitLocker と TPM + PIN の設定状態を確認する

## 処理の流れ

1. [Setup-BitLockerPIN.ps1](Setup-BitLockerPIN.ps1) を管理者権限で実行する
2. スクリプトが BitLocker の状態を確認し、必要なら回復パスワードと TPM + PIN を設定する
3. [Register-Task.ps1](Register-Task.ps1) が [Enforce-BitLockerPIN.ps1](Enforce-BitLockerPIN.ps1) を `C:\Scripts` にコピーしてタスクを登録する
4. ログオン時に `bdechangepin.exe` が起動し、PIN の変更を促す
5. 変更が完了すると、フラグ ファイル `C:\Scripts\.PinChanged` が作成される
6. [Verify-BitLockerPIN.ps1](Verify-BitLockerPIN.ps1) で設定済みかどうかを確認する

## 前提条件

- Windows の管理者権限(Intuneで配布する場合、システムコンテキストでの実行を想定)
- TPMを搭載した、BitLocker が利用可能な端末
- `Get-BitLockerVolume` や `Enable-BitLocker` が利用できる PowerShell 環境
- `C:\Windows\System32\bdechangepin.exe` を実行できること

## 使い方

### 1. 初期設定

[Setup-BitLockerPIN.ps1](Setup-BitLockerPIN.ps1) を管理者として実行します。

```powershell
.\Setup-BitLockerPIN.ps1
```

### 2. 設定確認

設定状況だけ確認したい場合は、次のスクリプトを実行します。

```powershell
.\Verify-BitLockerPIN.ps1
```

## Intune での配布

このリポジトリは、`IntuneWinAppUtil.exe` を使って Win32 アプリケーションとしてパッケージ化し、Intune から配布する運用を想定しています。

### パッケージ化の例

スクリプト一式を 1 つのフォルダーにまとめ、`IntuneWinAppUtil.exe` で `.intunewin` ファイルを作成します。

### インストール コマンド

```powershell
%windir%\SysNative\WindowsPowerShell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -File .\Setup-BitLockerPIN.ps1
```

### アンインストール コマンド

```powershell
%windir%\SysNative\WindowsPowerShell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -File .\Setup-BitLockerPIN.ps1
```

### リターンコード
- `0`: 既に TPM + PIN が設定されているため、変更は行わない
- `1641`: BitLocker処理の継続のため、再起動が必要

### 検出ルール

検出ルールは「カスタム検出スクリプト」を選択し、[Verify-BitLockerPIN.ps1](Verify-BitLockerPIN.ps1) を使用します。これにより、BitLocker が有効で、TPM + PIN が設定済みどうかを判定できます。
PIN変更済フラグを対象に含めると、インストールチェックがPIN変更を完了するまで常時失敗してしまうため、`0`を返すようにしています。

## 注意事項

- [Setup-BitLockerPIN.ps1](Setup-BitLockerPIN.ps1) の既定 PIN は `123456` です。本番利用前に必ず見直してください。
- スクリプトは `C:\Scripts` と `C:` ドライブを前提にしています。
- 実行には管理者権限が必要です。
- 端末の運用ポリシーに合わせて、タスク名や保存先を変更しても構いません。

## 補足

このリポジトリは、BitLocker の導入済み端末に対して PIN 付き保護へ移行させるための最小構成を意図しています。Intune で配布する場合は、実行コンテキストと管理者権限の扱いを事前に確認してください。

## 動作確認条件
- Windows 11 Enterprise 25H2(TPM 2.0 搭載機)
- Autopilot 登録済み端末でのユーザー主導展開

## 不具合が確認された条件
- Autopilot デバイス準備ポリシーでの展開
- BYOD端末での展開(デバイスフィルタで除外することを推奨)

## ライセンス
特に制限はないです。ご自由にお使いください。

## 免責事項
本スクリプトは現状のまま提供されており、動作保証はありません。実行前に内容を確認し、必要に応じて修正してください。スクリプトの実行によるいかなる損害についても、作者は責任を負いません。