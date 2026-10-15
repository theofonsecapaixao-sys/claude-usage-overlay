# Baixa os componentes oficiais do WebView2 (Microsoft, via NuGet) para overlay\webview2.
# Rode uma vez (o "Abrir overlay.cmd" faz isso sozinho se faltar). Confere a assinatura digital da Microsoft.
param([string]$Destino = (Join-Path $PSScriptRoot 'webview2'))
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$idx = (Invoke-WebRequest -Uri 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json' -UseBasicParsing).Content | ConvertFrom-Json
$ver = ($idx.versions | Where-Object { $_ -notmatch '-' } | Select-Object -Last 1)
Write-Host "WebView2 SDK $ver"

$tmp = Join-Path $env:TEMP ('wv2_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
try {
  $zip = Join-Path $tmp 'wv2.zip'
  Invoke-WebRequest -Uri "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$ver/microsoft.web.webview2.$ver.nupkg" -OutFile $zip -UseBasicParsing
  $x = Join-Path $tmp 'x'
  Expand-Archive $zip $x
  $files = 'lib\net462\Microsoft.Web.WebView2.Core.dll', 'lib\net462\Microsoft.Web.WebView2.Wpf.dll', 'runtimes\win-x64\native\WebView2Loader.dll'
  foreach ($f in $files) {
    $sig = Get-AuthenticodeSignature (Join-Path $x $f)
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw "Assinatura invalida em $f ($($sig.Status))" }
  }
  New-Item -ItemType Directory -Force $Destino, (Join-Path $Destino 'runtimes\win-x64\native') | Out-Null
  Copy-Item (Join-Path $x $files[0]) $Destino -Force
  Copy-Item (Join-Path $x $files[1]) $Destino -Force
  Copy-Item (Join-Path $x $files[2]) (Join-Path $Destino 'runtimes\win-x64\native') -Force
  Copy-Item (Join-Path $x 'LICENSE.txt') (Join-Path $Destino 'LICENSE-WebView2.txt') -Force
  Write-Host "OK: componentes em $Destino"
} finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
