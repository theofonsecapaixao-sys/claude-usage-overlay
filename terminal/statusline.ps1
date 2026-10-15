# Statusline do Claude Code: uso 5h / semana / contexto, sempre visivel.
# Le o JSON que o proprio Claude Code envia via stdin. Sem rede, sem token.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$esc = [char]27
function Paint($pct, $text) {
    $c = if ($pct -ge 85) { 31 } elseif ($pct -ge 60) { 33 } else { 32 }
    return "$esc[${c}m$text$esc[0m"
}
function Until($epoch) {
    $span = [DateTimeOffset]::FromUnixTimeSeconds([int64]$epoch) - [DateTimeOffset]::Now
    if ($span.TotalMinutes -le 0) { return 'agora' }
    if ($span.TotalHours -lt 1) { return ('{0}min' -f [int][math]::Round($span.TotalMinutes)) }
    if ($span.TotalHours -lt 24) { return ('{0}h{1:00}' -f [int][math]::Floor($span.TotalHours), $span.Minutes) }
    return ('{0}d{1}h' -f $span.Days, $span.Hours)
}

try { $j = $input | Out-String | ConvertFrom-Json } catch { Write-Host 'claude'; exit }
$parts = @()

$five = $j.rate_limits.five_hour
if ($null -ne $five.used_percentage) {
    $p = [math]::Round($five.used_percentage)
    $parts += Paint $p ("5h {0}% ({1})" -f $p, (Until $five.resets_at))
}
$week = $j.rate_limits.seven_day
if ($null -ne $week.used_percentage) {
    $p = [math]::Round($week.used_percentage)
    $parts += Paint $p ("7d {0}% ({1})" -f $p, (Until $week.resets_at))
}
$ctx = $j.context_window.used_percentage
if ($null -ne $ctx) {
    $p = [math]::Round($ctx)
    $parts += Paint $p ("ctx {0}%" -f $p)
}
if ($parts.Count -eq 0) { $parts = @('uso: aguardando 1a resposta') }
Write-Host ($parts -join ' | ')
