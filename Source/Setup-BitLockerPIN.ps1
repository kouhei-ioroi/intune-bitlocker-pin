$PresetPin  = "123456"

# BitLocker状態取得
$blv = Get-BitLockerVolume -MountPoint $env:SystemDrive

# プリセットPINをSecureStringに変換
$SecurePin = ConvertTo-SecureString $PresetPin -AsPlainText -Force

if ($blv.VolumeStatus -eq "FullyDecrypted") {
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
    while($blv.VolumeStatus -eq "EncryptionInProgress") {
        Write-Output "BitLockerの暗号化が進行中のため、完了まで待機します..."
        Start-Sleep -Seconds 60
        $blv = Get-BitLockerVolume -MountPoint $env:SystemDrive
    }
    if ($blv.VolumeStatus -eq "FullyEncrypted") {
        Write-Output "BitLockerの暗号化が完了しました。"
        exit 1641
    }else{
        Write-Output "BitLockerの暗号化に失敗した可能性があります。状態: $($blv.VolumeStatus)"
        exit 1
    }

}elseif ($blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "Tpm" }) {
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
