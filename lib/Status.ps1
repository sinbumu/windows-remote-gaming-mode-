# Live snapshot: re-query devices/services. Do not trust the last button press.

function Get-RmTailscaleStatus {
    $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    $exe = 'C:\Program Files\Tailscale\tailscale.exe'
    $self = $null
    if (Test-Path -LiteralPath $exe) {
        try { $self = (& $exe status --self --json 2>$null | Out-String) } catch { $self = $null }
        if (-not $self) {
            try { $self = (& $exe ip -4 2>$null | Select-Object -First 1) } catch { }
        }
    }
    [pscustomobject]@{
        Present   = [bool]$svc
        Status    = if ($svc) { [string]$svc.Status } else { 'Missing' }
        StartType = if ($svc) { [string]$svc.StartType } else { $null }
        Detail    = $self
    }
}

function Get-RmLiveSnapshot {
    $cfg = Get-RmConfig
    $state = Get-RmState
    $vdd = Get-RmVddStatus
    $sun = Get-RmSunshineStatus
    $auto = Get-RmAutologonStatus
    $ts = Get-RmTailscaleStatus
    $primary = 'n/a'
    try { $primary = Get-RmPrimaryKind } catch { $primary = 'error' }
    $physical = $false
    try { $physical = [bool](Test-RmPhysicalMonitorActive) } catch { }
    $watch = $false
    try { $watch = [bool](Test-RmWatchRunning) } catch { }
    $pending = @()
    try { $pending = @(Get-RmPendingReboot) } catch { }

    $sunRunning = $sun.Present -and ($sun.Status -eq 'Running')
    $desired = [string]$state.desired
    if ([string]::IsNullOrWhiteSpace($desired)) { $desired = 'off' }

    $payloadOn = [bool]$vdd.Enabled -and $sunRunning
    $payloadOff = (-not $vdd.Enabled) -and (-not $sunRunning)

    $mode = 'PARTIAL'
    if ($desired -eq 'on' -and $payloadOn) { $mode = 'ON' }
    elseif ($desired -ne 'on' -and $payloadOff) { $mode = 'OFF' }

    $issues = @()
    if ($desired -eq 'on') {
        if (-not $vdd.Enabled) { $issues += 'VDD off' }
        if (-not $sunRunning) { $issues += 'Sunshine stopped' }
        if (-not $auto.ArmedInRegistry) { $issues += 'Autologon not armed' }
        if (-not $watch) { $issues += 'Watchdog not running' }
    }
    else {
        if ($vdd.Enabled) { $issues += 'VDD still on' }
        if ($sunRunning) { $issues += 'Sunshine still running' }
        if ($auto.ArmedInRegistry) { $issues += 'Autologon still armed' }
    }
    if ($ts.Status -ne 'Running') { $issues += 'Tailscale not running' }

    [pscustomobject]@{
        Mode            = $mode
        Desired         = $desired
        PayloadOn       = $payloadOn
        Tailscale       = $ts.Status
        TailscaleStart  = $ts.StartType
        VddEnabled      = [bool]$vdd.Enabled
        VddStatus       = $vdd.Status
        Sunshine        = $sun.Status
        SunshineStart   = $sun.StartType
        AutologonArmed  = [bool]$auto.ArmedInRegistry
        AutologonSecret = [bool]$auto.SecretOnDisk
        PrimaryKind     = $primary
        PhysicalActive  = $physical
        Watchdog        = $watch
        PendingReboot   = ($pending -join ', ')
        LastOn          = $state.lastOn
        LastOff         = $state.lastOff
        Issues          = $issues
        PhysicalMonitor = $cfg.physicalMonitorName
        VddInstanceId   = $cfg.vddInstanceId
        CheckedAt       = Get-Date
    }
}
