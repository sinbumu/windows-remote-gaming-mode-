# Shared paths, config, state, logging, elevation.

$script:RmDataDir = 'C:\ProgramData\RemoteMode'
$script:RmLogPath = Join-Path $script:RmDataDir 'remote-mode.log'
$script:RmStatePath = Join-Path $script:RmDataDir 'state.json'
$script:RmWatchPidPath = Join-Path $script:RmDataDir 'watchdog.pid'
$script:RmAutologonPath = Join-Path $script:RmDataDir 'autologon.bin'
$script:RmAutologonUserPath = Join-Path $script:RmDataDir 'autologon-user.json'
$script:RmEntropy = [byte[]](83, 105, 110, 98, 117, 82, 101, 109, 111, 116, 101, 77, 111, 100, 101)

function Get-RmToolRoot {
    if ($script:RmToolRoot) { return $script:RmToolRoot }
    return Split-Path -Parent $PSScriptRoot
}

function Test-RmAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-RmAdmin {
    if (-not (Test-RmAdmin)) {
        throw '관리자 권한이 필요합니다. PowerShell을 관리자로 다시 실행하세요.'
    }
}

function Initialize-RmDataDir {
    if (-not (Test-Path -LiteralPath $script:RmDataDir)) {
        New-Item -ItemType Directory -Path $script:RmDataDir -Force | Out-Null
    }
}

function Write-RmLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    Initialize-RmDataDir
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $mutex = $null
    try {
        $mutex = New-Object System.Threading.Mutex($false, 'Global\RemoteModeLogFile')
        [void]$mutex.WaitOne(2000)
        $utf8 = New-Object System.Text.UTF8Encoding $false
        $fs = [System.IO.File]::Open(
            $script:RmLogPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            $sw = New-Object System.IO.StreamWriter($fs, $utf8)
            $sw.WriteLine($line)
            $sw.Flush()
            $sw.Dispose()
        }
        catch {
            try { $fs.Dispose() } catch { }
            throw
        }
    }
    catch {
        # Logging must never fail ON/OFF.
    }
    finally {
        if ($mutex) {
            try { $mutex.ReleaseMutex() | Out-Null } catch { }
            $mutex.Dispose()
        }
    }
    try {
        switch ($Level) {
            'WARN' { Write-Host $line -ForegroundColor Yellow }
            'ERROR' { Write-Host $line -ForegroundColor Red }
            default { Write-Host $line }
        }
    }
    catch { }
    if ($script:RmLogCallback) {
        try { & $script:RmLogCallback $line $Level } catch { }
    }
}

function Test-RmWatchRunning {
    if (-not (Test-Path -LiteralPath $script:RmWatchPidPath)) { return $false }
    $watchPid = 0
    [void][int]::TryParse((Get-Content -LiteralPath $script:RmWatchPidPath -ErrorAction SilentlyContinue | Select-Object -First 1), [ref]$watchPid)
    if ($watchPid -le 0) { return $false }
    return [bool](Get-Process -Id $watchPid -ErrorAction SilentlyContinue)
}

function Get-RmConfig {
    if ($script:RmConfig) { return $script:RmConfig }

    $candidates = @(
        (Join-Path $script:RmDataDir 'config.json'),
        (Join-Path (Get-RmToolRoot) 'config.json')
    )
    $path = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $path) {
        throw 'config.json을 찾을 수 없습니다.'
    }
    $script:RmConfig = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    return $script:RmConfig
}

function Get-RmState {
    Initialize-RmDataDir
    if (-not (Test-Path -LiteralPath $script:RmStatePath)) {
        return [pscustomobject]@{
            desired        = 'off'
            powerBackup    = $null
            updateBackup   = $null
            nicBackup      = $null
            lastOn         = $null
            lastOff        = $null
            sunshinePrepBackup = $null
        }
    }
    return Get-Content -LiteralPath $script:RmStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-RmState {
    param([Parameter(Mandatory)]$State)
    Initialize-RmDataDir
    $json = $State | ConvertTo-Json -Depth 8
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:RmStatePath, $json, $utf8)
}

function Get-RmCurrentUser {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $name = $id.Name
    if ($name -match '\\') {
        $parts = $name.Split('\', 2)
        return [pscustomobject]@{ Domain = $parts[0]; User = $parts[1]; FullName = $name }
    }
    return [pscustomobject]@{ Domain = $env:COMPUTERNAME; User = $name; FullName = $name }
}

function ConvertTo-Hashtable {
    param($Object)
    if ($null -eq $Object) { return @{} }
    if ($Object -is [hashtable]) { return $Object }
    $ht = @{}
    foreach ($p in $Object.PSObject.Properties) {
        $ht[$p.Name] = $p.Value
    }
    return $ht
}
