# Intune-BitLocker-PIN

Intuneのアプリケーション配布機能を利用して、Windows の BitLocker に TPM + PIN をサイレント設定し、PIN 変更を促すタスクを登録するスクリプトです。  

# 使い方

1. Releasesから最新のintunewinパッケージと`Verify.ps1`をダウンロードします。
2. Microsoft Intune 管理センターにアクセスし、アプリケーションの追加からWin32アプリを選択します。
3. ダウンロードしたintunewinパッケージをアップロードします。
4. インストールコマンドに以下を指定します。
   ```
   %windir%\SysNative\WindowsPowerShell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -File .\Setup-BitLockerPIN.ps1
   ```
5. アンインストールコマンドに以下を指定します。
   ```
    %windir%\SysNative\WindowsPowerShell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -File .\Setup-BitLockerPIN.ps1
   ```
6. インストールの処理をシステムに指定します。
7. リターンコードを以下のように設定します。
    - 成功 : 0
    - ハードリブート : 1641
    - 失敗 : 1
8. 検出規則の形式をカスタム検出スクリプトに設定し、`Verify.ps1`を指定します。
9. アプリケーションを割り当て、配信します。
