@echo off
if not exist "%~dp0overlay\webview2\Microsoft.Web.WebView2.Wpf.dll" (
  echo Baixando componentes do WebView2 ^(so na primeira vez^)...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0overlay\baixar-webview2.ps1"
)
start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0overlay\usage-overlay.ps1"
