$TaskName = "EnforceBitLockerPIN"

# ディレクトリ作成
if (-not (Test-Path -Path "C:\Scripts")) {
    New-Item -ItemType Directory -Path "C:\Scripts" | Out-Null
}

# 対象のスクリプトをBase64エンコード
$ScriptContent = Get-Content -Path "$PSScriptRoot\Enforce-BitLockerPIN.ps1" -Raw
$EncodedScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptContent))

# 実行アクション
$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand `"$EncodedScript`""

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
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable

# 登録
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Force
