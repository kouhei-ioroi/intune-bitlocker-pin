$TaskName = "EnforceBitLockerPIN"
$ScriptPath = "C:\Scripts\Enforce-BitLockerPIN.ps1"

# ディレクトリ作成
if (-not (Test-Path -Path "C:\Scripts")) {
    New-Item -ItemType Directory -Path "C:\Scripts" | Out-Null
}

# 対象のスクリプトをコピー
Copy-Item -Path "$PSScriptRoot\Enforce-BitLockerPIN.ps1" -Destination $ScriptPath -Force

# 実行アクション
$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

# トリガー（ログオン時）
$Trigger = New-ScheduledTaskTrigger -AtLogOn

# ユーザーで実行（最高権限）
$Principal = New-ScheduledTaskPrincipal `
    -GroupId "BUILTIN\Administrators" `
    -RunLevel Highest

# 設定
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# 登録
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Force
