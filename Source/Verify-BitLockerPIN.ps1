# BitLocker状態取得
$blv = Get-BitLockerVolume -MountPoint $env:SystemDrive

if ($blv.VolumeStatus -eq "FullyDecrypted") {
    Write-Output "BitLockerが有効ではありません。"
    exit 1
}elseif (-not ($blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq "TpmPin" })) {
    Write-Output "TPM+PINが設定されていません。"
    exit 1
}elseif (-not (Test-Path -Path "C:\Scripts\.PinChanged")) {
    Write-Output "TPM+PINは設定されていますが、PIN変更が完了していません。"
    exit 0
}else {
    Write-Output "BitLockerが有効で、TPM+PINが既に設定され、変更済みです。"
    exit 0
}
