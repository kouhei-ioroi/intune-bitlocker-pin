# BitLocker PIN変更イベントログ確認
function Test-PinChanged {
    $events = Get-WinEvent -LogName "Microsoft-Windows-BitLocker/BitLocker Management" -ErrorAction SilentlyContinue | 
        Where-Object {
            $_.Id -eq 789 -and 
            $_.TimeCreated -gt (Get-Date).AddDays(-1)
        }

    if ($events) {
        return $true
    }
    return $false
}

$TaskName = "EnforceBitLockerPIN"

# メイン処理ループ
while ($true) {

    if (Test-PinChanged) {
        # タスクを削除する
        schtasks /Delete /TN $TaskName /F 2>$null
        # PIN変更完了フラグファイルを作成する
        New-Item -Path "C:\Scripts\.PinChanged" -ItemType File -Force | Out-Null
        exit
    }

    # PIN変更画面起動
    Start-Process "C:\Windows\System32\bdechangepin.exe" -Wait

}