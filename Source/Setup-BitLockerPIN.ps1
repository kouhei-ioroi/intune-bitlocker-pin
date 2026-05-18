# 引数でプリセットPINを受け取る
param (
    [string]$PresetPin = "123456"
)

# ログ出力先フォルダを作成する
if (-not (Test-Path -Path "C:\Scripts")) {
    New-Item -ItemType Directory -Path "C:\Scripts" | Out-Null
}

# スクリプトの実行ログを保存する
Start-Transcript -Path "C:\Scripts\Setup-BitLockerPIN.log"

# プリセットPINが4~20桁の数字であることをチェックする
if ($PresetPin -notmatch '^\d{4,20}$') {
    Write-Output "エラー: プリセットPINは4~20桁の数字でなければなりません。また、BitLockerポリシーで桁数が制限されている場合は、その範囲内で指定してください。"
    exit 1
}

# BitLocker状態取得
$blv = Get-BitLockerVolume -MountPoint $env:SystemDrive

# プリセットPINをSecureStringに変換
$SecurePin = ConvertTo-SecureString $PresetPin -AsPlainText -Force

if ($blv.VolumeStatus -ne "FullyEncrypted") {
    Write-Output "BitLockerが無効のため、有効化 + TPM+PINを設定します。"

    if (-not ($blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" })) {
        Add-BitLockerKeyProtector `
            -MountPoint $env:SystemDrive `
            -RecoveryPasswordProtector
    }

    Enable-BitLocker `
        -MountPoint $env:SystemDrive `
        -TpmAndPinProtector `
        -Pin $SecurePin `
        -UsedSpaceOnly `
        -SkipHardwareTest

    # タスクスケジューラにPIN変更タスクを登録
    & "$PSScriptRoot\Register-Task.ps1"

    # BitLocker状態を再取得
    $blv = Get-BitLockerVolume -MountPoint $env:SystemDrive

    # BitLockerの暗号化が完了するまで待機
    $waitCounter = 0
    while($blv.VolumeStatus -ne "FullyEncrypted") {
        Write-Output "BitLockerの暗号化が進行中のため、完了まで待機します..."
        Start-Sleep -Seconds 60
        $waitCounter++
        # 30分以上待機しても完了しない場合は、エラーと見なしループを抜ける
        if ($waitCounter -ge 30) {
            Write-Output "BitLockerの暗号化が想定時間内に完了しないため、処理を中断します。"
            break
        }
        $blv = Get-BitLockerVolume -MountPoint $env:SystemDrive
    }
    # 暗号化が完了したか確認
    if ($blv.VolumeStatus -eq "FullyEncrypted") {
        # 暗号化が完了したら再起動を促す
        Write-Output "BitLockerの暗号化が完了しました。"
        exit 1641
    }else{
        # 暗号化に失敗した場合はエラーメッセージを表示して終了
        Write-Output "BitLockerの暗号化に失敗した可能性があります。状態: $($blv.VolumeStatus)"
        exit 1
    }

}elseif ($blv.VolumeStatus -eq "FullyEncrypted" -and $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "Tpm" }) {
    Write-Output "TPMのみのため、PIN必須に変更します。"

    if (-not ($blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" })) {
        Add-BitLockerKeyProtector `
            -MountPoint $env:SystemDrive `
            -RecoveryPasswordProtector
    }

    Add-BitLockerKeyProtector `
        -MountPoint $env:SystemDrive `
        -TpmAndPinProtector `
        -Pin $SecurePin

    # タスクスケジューラにPIN変更タスクを登録
    & "$PSScriptRoot\Register-Task.ps1"

    # スクリプトを終了して再起動を促す
    exit 1641

}elseif (-not (Test-Path -Path "C:\Scripts\.PinChanged")) {
    Write-Output "TPM+PINは設定済みですが、PIN変更が完了していないため、PIN変更タスクを登録します。"
    # タスクスケジューラにPIN変更タスクを登録
    & "$PSScriptRoot\Register-Task.ps1"
    exit 0

}else {
    Write-Output "既にTPM+PINが設定され、変更済みです。変更は行いません。"
    exit 0
}

Stop-Transcript