# Claude Usage Overlay - janelinha nativa, transparente, sempre por cima, com clique atravessando.
# Recebe os dados da extensão do Chrome em http://127.0.0.1:47831 (só esta máquina). Não guarda nenhuma credencial.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CuoWin {
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
}
"@

$PORT = 47831
$mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeUsageOverlay')
if (-not $mutex.WaitOne(0)) { exit }   # já está aberto

$cfgDir  = Join-Path $env:APPDATA 'ClaudeUsageOverlay'
$cfgFile = Join-Path $cfgDir 'config.json'
$cfg = @{ left = $null; top = $null; alpha = 110; clickthrough = $true }
if (Test-Path $cfgFile) {
  try { $o = Get-Content $cfgFile -Raw | ConvertFrom-Json
        foreach ($k in 'left','top','alpha','clickthrough') { if ($null -ne $o.$k) { $cfg[$k] = $o.$k } } } catch {}
}
function Save-Cfg { try { New-Item -ItemType Directory -Force $cfgDir | Out-Null; ($cfg | ConvertTo-Json) | Set-Content $cfgFile -Encoding UTF8 } catch {} }

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize" ShowActivated="False">
  <Border x:Name="Panel" CornerRadius="10" Padding="11,9,11,9" BorderThickness="0">
    <StackPanel Width="196">
      <StackPanel.Effect><DropShadowEffect BlurRadius="4" ShadowDepth="0" Opacity="0.95" Color="Black"/></StackPanel.Effect>
      <TextBlock x:Name="T1" FontSize="13" FontWeight="SemiBold" Foreground="White"/>
      <Border Width="196" Height="5" CornerRadius="2.5" Background="#44FFFFFF" Margin="0,3,0,0" HorizontalAlignment="Left">
        <Border x:Name="B1" HorizontalAlignment="Left" CornerRadius="2.5" Width="0"/>
      </Border>
      <TextBlock x:Name="S1" FontSize="11" Foreground="#FFE5E5E5"/>
      <TextBlock x:Name="T2" FontSize="13" FontWeight="SemiBold" Foreground="White" Margin="0,7,0,0"/>
      <Border Width="196" Height="5" CornerRadius="2.5" Background="#44FFFFFF" Margin="0,3,0,0" HorizontalAlignment="Left">
        <Border x:Name="B2" HorizontalAlignment="Left" CornerRadius="2.5" Width="0"/>
      </Border>
      <TextBlock x:Name="S2" FontSize="11" Foreground="#FFE5E5E5"/>
      <TextBlock x:Name="Foot" FontSize="10" Foreground="#FFCFCFCF" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
  </Border>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'Panel','T1','B1','S1','T2','B2','S2','Foot') { $ui[$n] = $win.FindName($n) }

function Brush($hex) { (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }
function Apply-Alpha {
  $a = [math]::Max(0, [math]::Min(255, [int]$cfg.alpha))
  $ui.Panel.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb([byte]$a, 15, 15, 18))
}
function Level-Color($p) { if ($p -ge 85) { '#EF4444' } elseif ($p -ge 60) { '#F59E0B' } else { '#22C55E' } }

function Fmt-Reset($iso) {
  try { $d = [DateTimeOffset]::Parse([string]$iso, [Globalization.CultureInfo]::InvariantCulture) } catch { return '' }
  $span = $d - [DateTimeOffset]::Now
  if ($span.TotalMinutes -le 0) { return 'resetando…' }
  if ($span.TotalHours -lt 1)   { return ('reseta em {0}min' -f [int][math]::Round($span.TotalMinutes)) }
  if ($span.TotalHours -lt 24)  { return ('reseta em {0}h{1:00}' -f [int][math]::Floor($span.TotalHours), $span.Minutes) }
  return 'reseta ' + $d.LocalDateTime.ToString('ddd HH:mm', [Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
}

function Paint-Row($label, $row, $t, $b, $s) {
  if ($null -eq $row -or $null -eq $row.utilization) { $ui[$t].Text = ''; $ui[$s].Text = ''; $ui[$b].Width = 0; return }
  $u = [double]$row.utilization
  $pct = [math]::Max(0, [math]::Min(100, $u))
  $ui[$t].Text = ('{0}   {1}%' -f $label, [int][math]::Round($u))
  $ui[$b].Width = 196 * $pct / 100
  $ui[$b].Background = Brush (Level-Color $u)
  $ui[$s].Text = Fmt-Reset $row.resets_at
}

$script:data = $null
$script:at = $null
$script:needLogin = $false
function Render {
  try {
    if ($null -eq $script:data) {
      $ui.Foot.Text = $(if ($script:needLogin) { 'Entre no claude.ai na janela que abriu (ou bandeja > Entrar).' } else { 'aguardando dados…' })
    } else {
      Paint-Row 'Sessão (5h)' $script:data.five_hour 'T1' 'B1' 'S1'
      Paint-Row 'Semana' $script:data.seven_day 'T2' 'B2' 'S2'
      $age = ([DateTimeOffset]::Now - $script:at).TotalMinutes
      if ($age -gt 3) { $ui.Foot.Text = ('sem dados há {0} min' -f [int]$age) }
      else { $ui.Foot.Text = 'atualizado ' + $script:at.LocalDateTime.ToString('HH:mm') }
    }
    if (-not $cfg.clickthrough) { $ui.Foot.Text = 'MODO MOVER: arraste a janela. Clique no ícone da bandeja para travar.' }
    New-Item -ItemType Directory -Force $cfgDir | Out-Null
    ($ui.T1.Text + ' | ' + $ui.S1.Text + ' | ' + $ui.T2.Text + ' | ' + $ui.S2.Text + ' | ' + $ui.Foot.Text) | Set-Content (Join-Path $cfgDir 'last.txt') -Encoding UTF8
  } catch {}
}

function Set-ClickThrough($on) {
  $h = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
  $ex = [CuoWin]::GetWindowLong($h, -20)
  if ($on) { $ex = $ex -bor 0x20 -bor 0x80 -bor 0x08000000 }          # transparente ao mouse, toolwindow, sem foco
  else     { $ex = ($ex -bor 0x80) -band (-bnot 0x20) }                # permite arrastar
  [void][CuoWin]::SetWindowLong($h, -20, $ex)
  $cfg.clickthrough = [bool]$on
  if ($on) { $ui.Panel.BorderThickness = New-Object Windows.Thickness 0 }
  else { $ui.Panel.BorderThickness = New-Object Windows.Thickness 1; $ui.Panel.BorderBrush = Brush '#CCFFFFFF' }
  Save-Cfg; Render
}

$win.Add_SourceInitialized({
  Apply-Alpha
  Set-ClickThrough ([bool]$cfg.clickthrough)
})
$win.Add_Loaded({
  $wa = [System.Windows.SystemParameters]::WorkArea
  if ($null -ne $cfg.left -and $null -ne $cfg.top) {
    $win.Left = [math]::Max($wa.Left, [math]::Min([double]$cfg.left, $wa.Right - 60))
    $win.Top  = [math]::Max($wa.Top,  [math]::Min([double]$cfg.top,  $wa.Bottom - 40))
  } else {
    $win.Left = $wa.Right - $win.ActualWidth - 24
    $win.Top  = $wa.Bottom - $win.ActualHeight - 24
  }
  Render
})
$win.Add_MouseLeftButtonDown({
  if (-not $cfg.clickthrough) {
    try { $win.DragMove() } catch {}
    $cfg.left = $win.Left; $cfg.top = $win.Top; Save-Cfg
  }
})

# ---- bandeja (ícone perto do relógio) ----
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = [System.Drawing.SystemIcons]::Information
$tray.Text = 'Uso do Claude'
$tray.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miMove  = $menu.Items.Add('Mover janela (arrastar)')
$miMore  = $menu.Items.Add('Mais transparente')
$miLess  = $menu.Items.Add('Menos transparente')
$miReset = $menu.Items.Add('Voltar ao canto da tela')
[void]$menu.Items.Add('-')
$miLogin = $menu.Items.Add('Entrar / trocar conta do claude.ai')
$miLogout = $menu.Items.Add('Sair da conta (apagar login)')
[void]$menu.Items.Add('-')
$miExit  = $menu.Items.Add('Sair')
$tray.ContextMenuStrip = $menu
$toggle = { Set-ClickThrough (-not $cfg.clickthrough) }
$miMove.Add_Click($toggle)
$tray.Add_MouseClick({ param($s, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { & $toggle } })
$miMore.Add_Click({ $cfg.alpha = [math]::Max(0, [int]$cfg.alpha - 25);  Apply-Alpha; Save-Cfg })
$miLess.Add_Click({ $cfg.alpha = [math]::Min(255, [int]$cfg.alpha + 25); Apply-Alpha; Save-Cfg })
$miReset.Add_Click({
  $wa = [System.Windows.SystemParameters]::WorkArea
  $win.Left = $wa.Right - $win.ActualWidth - 24; $win.Top = $wa.Bottom - $win.ActualHeight - 24
  $cfg.left = $win.Left; $cfg.top = $win.Top; Save-Cfg
})
$miExit.Add_Click({ $win.Close() })

# ---- recebe os dados da extensão ----
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$PORT/")
try { $listener.Start() } catch {
  [System.Windows.MessageBox]::Show("Não consegui abrir a porta $PORT (já em uso?).`n$($_.Exception.Message)", 'Uso do Claude') | Out-Null
  exit
}
$script:task = $listener.GetContextAsync()
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
  try {
    if ($script:task.IsCompleted) {
      $ctx = $script:task.Result
      $script:task = $listener.GetContextAsync()
      try {
        $res = $ctx.Response
        $res.Headers.Add('Access-Control-Allow-Origin', '*')
        $res.Headers.Add('Access-Control-Allow-Headers', '*')
        $res.StatusCode = 200
        if ($ctx.Request.HttpMethod -eq 'POST' -and $ctx.Request.ContentLength64 -lt 200000) {
          $sr = New-Object System.IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
          $p = $sr.ReadToEnd() | ConvertFrom-Json
          if ($null -ne $p.usage) { $script:data = $p.usage; $script:at = [DateTimeOffset]::Now; Render }
        }
      } catch { try { $ctx.Response.StatusCode = 400 } catch {} }
      finally { try { $ctx.Response.Close() } catch {} }
    }
  } catch {}
})
$timer.Start()
$tick = New-Object System.Windows.Threading.DispatcherTimer
$tick.Interval = [TimeSpan]::FromSeconds(30)
$tick.Add_Tick({ Render })
$tick.Start()

# ---- fonte própria: login embutido (WebView2). O login fica só nesta máquina, na pasta de dados do WebView2. ----
$script:exiting = $false
$script:loginVisible = $false
$script:loginPrompted = $false
$wvOk = $false
try {
  $wvDir = Join-Path $PSScriptRoot 'webview2'
  Add-Type -Path (Join-Path $wvDir 'Microsoft.Web.WebView2.Core.dll')
  Add-Type -Path (Join-Path $wvDir 'Microsoft.Web.WebView2.Wpf.dll')
  $wvOk = $true
} catch { $miLogin.Enabled = $false; $miLogout.Enabled = $false }

if ($wvOk) {
  $wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
  $props = New-Object Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties
  $props.UserDataFolder = Join-Path $cfgDir 'webview'
  $wv.CreationProperties = $props
  $loginWin = New-Object Windows.Window
  $loginWin.Title = 'Entrar no claude.ai'
  $loginWin.Width = 520; $loginWin.Height = 740
  $loginWin.WindowStartupLocation = 'Manual'
  $loginWin.Left = -32000; $loginWin.Top = -32000
  $loginWin.ShowInTaskbar = $false
  $loginWin.Content = $wv

  function Show-Login {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $loginWin.ShowInTaskbar = $true
    $loginWin.Left = $wa.Left + ($wa.Width - $loginWin.Width) / 2
    $loginWin.Top = $wa.Top + ($wa.Height - $loginWin.Height) / 2
    $loginWin.Topmost = $true; [void]$loginWin.Activate(); $loginWin.Topmost = $false
    $script:loginVisible = $true
  }
  function Hide-Login {
    $loginWin.ShowInTaskbar = $false
    $loginWin.Left = -32000; $loginWin.Top = -32000
    $script:loginVisible = $false
  }
  $loginWin.Add_Closing({ param($s, $e) if (-not $script:exiting) { $e.Cancel = $true; Hide-Login } })

  $fetchJs = @'
(async () => {
  const send = (o) => window.chrome.webview.postMessage(JSON.stringify(o));
  try {
    const m = document.cookie.match(/(?:^|;\s*)lastActiveOrg=([^;]+)/);
    let org = m ? decodeURIComponent(m[1]) : null;
    if (!org) {
      const r = await fetch('/api/organizations', { credentials: 'include' });
      if (!r.ok) { send({ err: String(r.status) }); return; }
      const o = await r.json();
      const p = o.find((x) => (x.capabilities || []).includes('chat')) || o[0];
      org = p && p.uuid;
    }
    if (!org) { send({ err: '401' }); return; }
    const u = await fetch('/api/organizations/' + encodeURIComponent(org) + '/usage', { credentials: 'include' });
    if (!u.ok) { send({ err: String(u.status) }); return; }
    send({ usage: await u.json() });
  } catch (e) { send({ err: String(e) }); }
})();
'@
  function Fetch-Usage {
    try {
      if ($null -eq $wv.CoreWebView2) { return }
      if ([string]$wv.CoreWebView2.Source -notmatch '^https://claude\.ai/') { return }
      [void]$wv.CoreWebView2.ExecuteScriptAsync($fetchJs)
    } catch {}
  }

  $wv.add_CoreWebView2InitializationCompleted([EventHandler[Microsoft.Web.WebView2.Core.CoreWebView2InitializationCompletedEventArgs]]{
    param($s, $e)
    if (-not $e.IsSuccess) { $ui.Foot.Text = 'WebView2 falhou: ' + $e.InitializationException.Message; return }
    $wv.CoreWebView2.add_WebMessageReceived([EventHandler[Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs]]{
      param($s2, $e2)
      try {
        $o = $e2.TryGetWebMessageAsString() | ConvertFrom-Json
        if ($null -ne $o.usage) {
          $script:data = $o.usage; $script:at = [DateTimeOffset]::Now; $script:needLogin = $false; $script:loginPrompted = $false
          if ($script:loginVisible) { Hide-Login }
          Render
        } elseif ("$($o.err)" -match '^(401|403)$') {
          $script:needLogin = $true
          if (-not $script:loginPrompted) { $script:loginPrompted = $true; Show-Login }
          Render
        }
      } catch {}
    })
    $wv.CoreWebView2.add_NavigationCompleted([EventHandler[Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs]]{ param($s3, $e3) Fetch-Usage })
    $wv.CoreWebView2.Navigate('https://claude.ai/settings/usage')
  })
  $loginWin.Add_Loaded({ [void]$wv.EnsureCoreWebView2Async() })

  $fetchTimer = New-Object System.Windows.Threading.DispatcherTimer
  $fetchTimer.Interval = [TimeSpan]::FromSeconds(60)
  $fetchTimer.Add_Tick({ Fetch-Usage })
  $fetchTimer.Start()

  $miLogin.Add_Click({ Show-Login })
  $miLogout.Add_Click({
    try {
      $wv.CoreWebView2.CookieManager.DeleteAllCookies()
      $script:data = $null; $script:needLogin = $true; $script:loginPrompted = $true
      $wv.CoreWebView2.Navigate('https://claude.ai/login'); Show-Login; Render
    } catch {}
  })
}

$win.Add_Closed({
  $script:exiting = $true
  try { if ($wvOk) { $loginWin.Close() } } catch {}
  try { $tray.Visible = $false; $tray.Dispose() } catch {}
  try { $listener.Stop() } catch {}
  try { $mutex.ReleaseMutex() } catch {}
})
$app = New-Object Windows.Application
$app.ShutdownMode = 'OnMainWindowClose'
if ($wvOk) { $loginWin.Show() }
[void]$app.Run($win)
