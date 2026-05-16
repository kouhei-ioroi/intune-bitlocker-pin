$PresetPin  = "123456"

# BitLocker状態取得
$blv = Get-BitLockerVolume -MountPoint $env:SystemDrive

# プリセットPINをSecureStringに変換
$SecurePin = ConvertTo-SecureString $PresetPin -AsPlainText -Force

# --- ケース1: BitLocker未有効 ---
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
        -SkipHardwareTest

    # タスクスケジューラにPIN変更タスクを登録
    & "$PSScriptRoot\Register-Task.ps1"

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
        -Pin $SecurePin `
        -SkipHardwareTest

    # タスクスケジューラにPIN変更タスクを登録
    & "$PSScriptRoot\Register-Task.ps1"

}elseif (-not (Test-Path -Path "C:\Scripts\.PinChanged")) {
    Write-Output "TPM+PINは設定済みですが、PIN変更が完了していないため、PIN変更タスクを登録します。"
    # タスクスケジューラにPIN変更タスクを登録
    & "$PSScriptRoot\Register-Task.ps1"

}else {
    Write-Output "既にTPM+PINが設定され、変更済みです。変更は行いません。"

}

exit 0