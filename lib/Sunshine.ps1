# Sunshine Windows service + DisplaySwitch prep removal.

function Get-RmSunshineService {
    $cfg = Get-RmConfig
    Get-Service -Name $cfg.sunshineService -ErrorAction SilentlyContinue
}

function Get-RmSunshineStatus {
    $svc = Get-RmSunshineService
    if (-not $svc) {
        return [pscustomobject]@{ Present = $false; Status = 'Missing'; StartType = $null }
    }
    return [pscustomobject]@{
        Present   = $true
        Status    = [string]$svc.Status
        StartType = [string]$svc.StartType
        Name      = $svc.Name
    }
}

function Backup-RmSunshinePrep {
    $cfg = Get-RmConfig
    $conf = $cfg.sunshineConf
    if (-not (Test-Path -LiteralPath $conf)) {
        Write-RmLog 'sunshine.conf가 없어 DisplaySwitch 정리를 건너뜁니다.' 'WARN'
        return
    }

    $state = Get-RmState
    $text = [System.IO.File]::ReadAllText($conf)
    if ($text -notmatch 'displayswitch\.exe') {
        Write-RmLog 'sunshine.conf에 DisplaySwitch prep이 없습니다.'
        return
    }

    $bak = "$conf.remotemode.bak"
    if (-not (Test-Path -LiteralPath $bak)) {
        Copy-Item -LiteralPath $conf -Destination $bak -Force
        Write-RmLog "sunshine.conf 백업: $bak"
    }

    $new = [regex]::Replace(
        $text,
        '(?m)^global_prep_cmd\s*=\s*.*$',
        'global_prep_cmd = []'
    )
    if ($new -eq $text) {
        # JSON-ish inline might not be at line start with spaces
        $new = $text -replace 'global_prep_cmd\s*=\s*\[\{.*?\}\]', 'global_prep_cmd = []'
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($conf, $new, $utf8)
    $state | Add-Member -NotePropertyName sunshinePrepCleared -NotePropertyValue $true -Force
    Save-RmState $state
    Write-RmLog 'sunshine.conf에서 displayswitch.exe global_prep_cmd를 비웠습니다. OFF 때도 복원하지 않습니다.'
}

function Start-RmSunshine {
    Assert-RmAdmin
    $cfg = Get-RmConfig
    $svc = Get-RmSunshineService
    if (-not $svc) { throw 'SunshineService를 찾을 수 없습니다.' }

    Backup-RmSunshinePrep

    if ($svc.StartType -ne 'Automatic') {
        Set-Service -Name $cfg.sunshineService -StartupType Automatic
        Write-RmLog 'SunshineService StartType = Automatic'
    }
    $svc.Refresh()
    if ($svc.Status -ne 'Running') {
        Start-Service -Name $cfg.sunshineService
        Write-RmLog 'SunshineService 시작'
    }
    else {
        Write-RmLog 'SunshineService는 이미 실행 중입니다.'
    }
}

function Stop-RmSunshine {
    Assert-RmAdmin
    $cfg = Get-RmConfig
    $svc = Get-RmSunshineService
    if (-not $svc) {
        Write-RmLog 'SunshineService가 없어 중지를 건너뜁니다.' 'WARN'
        return
    }
    $svc.Refresh()
    if ($svc.Status -ne 'Stopped') {
        Stop-Service -Name $cfg.sunshineService -Force -ErrorAction SilentlyContinue
        Write-RmLog 'SunshineService 중지'
    }
    if ($svc.StartType -ne 'Manual') {
        Set-Service -Name $cfg.sunshineService -StartupType Manual
        Write-RmLog 'SunshineService StartType = Manual'
    }
}
