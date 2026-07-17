<#
.SYNOPSIS
    BitLocker に "TPM + PIN" をサイレント設定し、PIN 変更を促すタスクを登録するセットアップスクリプト

.DESCRIPTION
    このスクリプトは、Windows の BitLocker を TPM+PIN 認証方式で構成します。
    現在の状態に応じて以下の処理を行います。
      1. 管理者権限の確認
      2. プリセット PIN の妥当性チェック（4~20 桁の数字）
      3. 現在の BitLocker 状態とキープロテクターの取得
      4. 状態別処理
         - 未暗号化           : 回復パスワード + TPM+PIN を設定して有効化し、暗号化完了まで待機
         - TPM only           : 回復パスワードを確認し TPM+PIN を追加
         - TPM+PIN(変更未完了) : PIN 変更タスクのみ登録
         - TPM+PIN(変更済み)  : 変更なし
      5. PIN 変更を促すスケジュールタスクの登録
      6. 構成結果の検証

.PARAMETER PresetPin
    初期設定する PIN（4~20 桁の数字）。既定値は "123456"。
    BitLocker ポリシーで桁数が制限されている場合は、その範囲内で指定してください。

.NOTES
    実行環境: Windows 10/11（BitLocker 管理権限必須）
    推奨実行: システムコンテキストまたは管理者権限の PowerShell

    リターンコード:
      0    = 成功（変更不要／タスク登録のみ）
      1641 = ハードリブート要求（暗号化完了 or TPM+PIN 追加）
      1    = 失敗
#>

# 引数でプリセットPINを受け取る
param (
    [string]$PresetPin = "123456"
)

# エラー時は即座に停止するが、検証ロジックで Exit Code を制御するため try/catch で囲む
$ErrorActionPreference = "Stop"

# ログ出力先フォルダを作成する
if (-not (Test-Path -Path "C:\Scripts")) {
    New-Item -ItemType Directory -Path "C:\Scripts" | Out-Null
}

# スクリプトの実行ログを保存する
Start-Transcript -Path "C:\Scripts\Setup-BitLockerPIN.log" -Append

$PIN_CHANGED_FLAG = "C:\Scripts\.PinChanged"
$MountPoint = $env:SystemDrive
$MAX_WAIT_MINUTES = 30

function Write-Step {
    param([string]$Message)
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

# 回復パスワードキープロテクターが無ければ追加する
function Ensure-RecoveryPassword {
    param($Volume)
    if (-not ($Volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" })) {
        Write-Step "回復パスワードキープロテクターが存在しないため追加します。"
        Add-BitLockerKeyProtector `
            -MountPoint $MountPoint `
            -RecoveryPasswordProtector
    } else {
        Write-Step "回復パスワードキープロテクターは既に存在します。"
    }
}

# リターンコード: 0=成功, 1641=要再起動, 1=失敗
$exitCode = 0

try {
    Write-Step "BitLocker TPM+PIN セットアップを開始します。"

    # --- 1. 管理者権限の確認 ---
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Step "エラー: このスクリプトは管理者権限で実行する必要があります。"
        $exitCode = 1
        return
    }
    Write-Step "管理者権限を確認しました。"

    # --- 2. プリセット PIN の妥当性チェック ---
    if ($PresetPin -notmatch '^\d{4,20}$') {
        Write-Step "エラー: プリセットPINは4~20桁の数字でなければなりません。また、BitLockerポリシーで桁数が制限されている場合は、その範囲内で指定してください。"
        $exitCode = 1
        throw
    }
    Write-Step "プリセットPINの形式を確認しました。"

    # プリセットPINをSecureStringに変換
    $SecurePin = ConvertTo-SecureString $PresetPin -AsPlainText -Force

    # --- 3. BitLocker 状態の取得 ---
    $blv = Get-BitLockerVolume -MountPoint $MountPoint
    if ($null -eq $blv) {
        Write-Step "エラー: ドライブ $MountPoint の BitLocker ボリュームが見つかりません。"
        $exitCode = 1
        throw
    }
    Write-Step "現在の状態: $($blv.VolumeStatus) / キープロテクター: $($blv.KeyProtector.KeyProtectorType -join ', ')"

    $hasTpm    = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "Tpm" }
    $hasTpmPin = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "TpmPin" }

    # --- 4. 状態別処理 ---
    if ($blv.VolumeStatus -ne "FullyEncrypted") {
        Write-Step "BitLockerが無効のため、有効化 + TPM+PINを設定します。"

        Ensure-RecoveryPassword -Volume $blv

        Enable-BitLocker `
            -MountPoint $MountPoint `
            -TpmAndPinProtector `
            -Pin $SecurePin `
            -UsedSpaceOnly `
            -SkipHardwareTest

        # タスクスケジューラにPIN変更タスクを登録
        Write-Step "PIN変更タスクを登録します。"
        & "$PSScriptRoot\Register-Task.ps1"

        # BitLockerの暗号化が完了するまで待機
        Write-Step "BitLockerの暗号化完了を待機します（最大 $MAX_WAIT_MINUTES 分）。"
        $blv = Get-BitLockerVolume -MountPoint $MountPoint
        $waitCounter = 0
        while ($blv.VolumeStatus -ne "FullyEncrypted") {
            Write-Step "BitLockerの暗号化が進行中です（進捗: $($blv.EncryptionPercentage)%）。完了まで待機します..."
            Start-Sleep -Seconds 60
            $waitCounter++
            if ($waitCounter -ge $MAX_WAIT_MINUTES) {
                Write-Step "BitLockerの暗号化が想定時間内に完了しないため、処理を中断します。"
                break
            }
            $blv = Get-BitLockerVolume -MountPoint $MountPoint
        }

        # 暗号化が完了したか確認（検証）
        if ($blv.VolumeStatus -eq "FullyEncrypted") {
            Write-Step "検証成功: BitLockerの暗号化が完了しました。再起動が必要です。"
            $exitCode = 1641
        } else {
            Write-Step "検証失敗: BitLockerの暗号化に失敗した可能性があります。状態: $($blv.VolumeStatus)"
            $exitCode = 1
        }

    } elseif ($blv.VolumeStatus -eq "FullyEncrypted" -and $hasTpm -and -not $hasTpmPin) {
        Write-Step "TPMのみのため、PIN必須に変更します。"

        Ensure-RecoveryPassword -Volume $blv

        Add-BitLockerKeyProtector `
            -MountPoint $MountPoint `
            -TpmAndPinProtector `
            -Pin $SecurePin

        # タスクスケジューラにPIN変更タスクを登録
        Write-Step "PIN変更タスクを登録します。"
        & "$PSScriptRoot\Register-Task.ps1"

        # 検証: TpmPin キープロテクターが追加されたか確認
        $blv = Get-BitLockerVolume -MountPoint $MountPoint
        if ($blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "TpmPin" }) {
            Write-Step "検証成功: TPM+PINを設定しました。再起動が必要です。"
            $exitCode = 1641
        } else {
            Write-Step "検証失敗: TPM+PINキープロテクターの追加を確認できませんでした。"
            $exitCode = 1
        }

    } elseif (-not (Test-Path -Path $PIN_CHANGED_FLAG)) {
        Write-Step "TPM+PINは設定済みですが、PIN変更が完了していないため、PIN変更タスクを登録します。"
        & "$PSScriptRoot\Register-Task.ps1"
        $exitCode = 0

    } else {
        Write-Step "既にTPM+PINが設定され、変更済みです。変更は行いません。"
        $exitCode = 0
    }

} catch {
    Write-Step "予期せぬエラーが発生しました: $_"
    if ($exitCode -eq 0) { $exitCode = 1 }
} finally {
    Stop-Transcript
}

exit $exitCode
