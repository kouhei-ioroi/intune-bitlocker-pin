<#
.SYNOPSIS
    BitLocker認証方式を "TPM + PIN" から "TPM only" へ移行（PIN 要件の削除）するアンインストールスクリプト

.DESCRIPTION
    このスクリプトは、Intune-BitLocker-PIN によって適用された TPM+PIN 構成を解除し、
    TPM のみの認証方式へ移行します。具体的には以下を行います。
      1. 管理者権限の確認
      2. 現在の BitLocker 状態とキープロテクターの取得
      3. TpmPin キープロテクターの削除（PIN 要件の除去）
      4. TPM キープロテクターの存在確認（なければ追加）
      5. PIN 変更を促すスケジュールタスクの削除
      6. PIN 変更完了フラグファイルの削除
      7. 移行結果の検証

    検証に失敗した場合は、非ゼロのリターンコードで終了します。

.NOTES
    実行環境: Windows 10/11（BitLocker 管理権限必須）
    推奨実行: システムコンテキストまたは管理者権限の PowerShell
#>

# エラー時は即座に停止するが、検証ロジックで Exit Code を制御するため try/catch で囲む
$ErrorActionPreference = "Stop"

# ログ出力先フォルダを作成する
if (-not (Test-Path -Path "C:\Scripts")) {
    New-Item -ItemType Directory -Path "C:\Scripts" | Out-Null
}

# スクリプトの実行ログを保存する
Start-Transcript -Path "C:\Scripts\Uninstall-BitLockerPIN.log" -Append

$TASK_NAME = "EnforceBitLockerPIN"
$PIN_CHANGED_FLAG = "C:\Scripts\.PinChanged"
$MountPoint = $env:SystemDrive

function Write-Step {
    param([string]$Message)
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

# リターンコード: 0=成功, 1=失敗
$exitCode = 0

try {
    Write-Step "BitLocker 認証移行（TPM+PIN -> TPM only）を開始します。"

    # --- 1. 管理者権限の確認 ---
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Step "エラー: このスクリプトは管理者権限で実行する必要があります。"
        Stop-Transcript
        exit 1
    }
    Write-Step "管理者権限を確認しました。"

    # --- 2. BitLocker 状態の取得 ---
    $blv = Get-BitLockerVolume -MountPoint $MountPoint
    if ($null -eq $blv) {
        Write-Step "エラー: ドライブ $MountPoint の BitLocker ボリュームが見つかりません。"
        $exitCode = 1
        throw
    }

    if ($blv.VolumeStatus -ne "FullyEncrypted") {
        Write-Step "警告: BitLocker が有効ではありません（状態: $($blv.VolumeStatus)）。移行処理をスキップします。"
        $exitCode = 1
        throw
    }
    Write-Step "BitLocker は有効です（状態: $($blv.VolumeStatus)）。"

    # --- 3. TpmPin キープロテクターの削除 ---
    $tpmPinProtectors = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "TpmPin" }

    if ($tpmPinProtectors) {
        foreach ($protector in $tpmPinProtectors) {
            Write-Step "TpmPin キープロテクター (ID: $($protector.KeyProtectorId)) を削除します。"
            Remove-BitLockerKeyProtector `
                -MountPoint $MountPoint `
                -KeyProtectorId $protector.KeyProtectorId
        }
    } else {
        Write-Step "TpmPin キープロテクターは存在しません。削除をスキップします。"
    }

    # --- 4. TPM キープロテクターの確認／追加 ---
    $blv = Get-BitLockerVolume -MountPoint $MountPoint
    $tpmProtector = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "Tpm" }

    if (-not $tpmProtector) {
        Write-Step "TPM キープロテクターが存在しないため追加します。"
        Add-BitLockerKeyProtector `
            -MountPoint $MountPoint `
            -TpmProtector
    } else {
        Write-Step "TPM キープロテクターは既に存在します。"
    }

    # --- 5. PIN 変更スケジュールタスクの削除 ---
    $existingTask = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Step "スケジュールタスク '$TASK_NAME' を削除します。"
        Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction Stop
    } else {
        Write-Step "スケジュールタスク '$TASK_NAME' は存在しません。削除をスキップします。"
    }

    # --- 6. PIN 変更完了フラグファイルの削除 ---
    if (Test-Path -Path $PIN_CHANGED_FLAG) {
        Write-Step "PIN 変更完了フラグファイルを削除します: $PIN_CHANGED_FLAG"
        Remove-Item -Path $PIN_CHANGED_FLAG -Force
    } else {
        Write-Step "PIN 変更完了フラグファイルは存在しません。削除をスキップします。"
    }

    # --- 7. 移行結果の検証 ---
    Write-Step "移行結果を検証します。"
    $blv = Get-BitLockerVolume -MountPoint $MountPoint

    $remainingTpmPin = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "TpmPin" }
    $hasTpm = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "Tpm" }
    $taskStillExists = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    $flagStillExists = Test-Path -Path $PIN_CHANGED_FLAG

    $verificationErrors = @()

    if ($remainingTpmPin) {
        $verificationErrors += "TpmPin キープロテクターがまだ残っています。"
    }
    if (-not $hasTpm) {
        $verificationErrors += "TPM キープロテクターが存在しません（TPM only への移行が不完全です）。"
    }
    if ($taskStillExists) {
        $verificationErrors += "PIN 変更スケジュールタスクがまだ残っています。"
    }
    if ($flagStillExists) {
        $verificationErrors += "PIN 変更完了フラグファイルがまだ残っています。"
    }

    if ($verificationErrors.Count -gt 0) {
        Write-Step "検証失敗。以下の問題が検出されました:"
        foreach ($err in $verificationErrors) {
            Write-Step "  - $err"
        }
        $exitCode = 1
    } else {
        Write-Step "検証成功: TPM only への移行が完了しました。PIN 要件は削除されています。"
        Write-Step "現在のキープロテクター: $($blv.KeyProtector.KeyProtectorType -join ', ')"
        $exitCode = 0
    }

} catch {
    Write-Step "予期せぬエラーが発生しました: $_"
    $exitCode = 1
} finally {
    Stop-Transcript
}

exit $exitCode
