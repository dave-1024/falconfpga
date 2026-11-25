# sd_upload.ps1 - copy a file to the board's SD card through the AE350
# companion console (put / h / pend commands). Usage:
#   .\sd_upload.ps1 -File gb403.st [-Name gb403.st] [-Port COM4]
param([Parameter(Mandatory)][string]$File, [string]$Name, [string]$Port = 'COM4')
if (-not $Name) { $Name = [IO.Path]::GetFileName($File) }
$b = [IO.File]::ReadAllBytes((Resolve-Path $File))
$sp = New-Object IO.Ports.SerialPort $Port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 3000; $sp.NewLine = "`r`n"; $sp.Open()
function Cmd([string]$l) {
  for ($try = 0; $try -lt 5; $try++) {
    $sp.DiscardInBuffer(); $sp.Write("$l`r")
    try { while ($true) { $r = $sp.ReadLine().Trim(); if ($r -match '^(k|e|done) ') { break } } } catch { $r = 'timeout' }
    if ($r -like 'k *' -or $r -like 'done*') { return $r }
    Write-Host "retry ($r)"
  }
  throw "failed: $l"
}
try {
  $sp.Write("`r"); Start-Sleep -Milliseconds 300
  Cmd "put $Name" | Out-Null
  $sw = [Diagnostics.Stopwatch]::StartNew()
  for ($o = 0; $o -lt $b.Length; $o += 64) {
    $n = [Math]::Min(64, $b.Length - $o); $z = $true
    for ($i = 0; $i -lt $n; $i++) { if ($b[$o + $i]) { $z = $false; break } }
    if ($z -and $n -eq 64) { $l = 'h 0' } else { $l = 'h ' + [BitConverter]::ToString($b, $o, $n).Replace('-', '') }
    $r = Cmd $l
    if ($r -ne "k $($o + $n)") { throw "offset mismatch at $o : $r" }
    if (($o % 65536) -eq 0) { Write-Host "$o / $($b.Length)  $([int]$sw.Elapsed.TotalSeconds) s" }
  }
  Write-Host (Cmd 'pend')
} finally { $sp.Close() }
