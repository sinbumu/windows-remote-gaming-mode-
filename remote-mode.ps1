#Requires -Version 5.1
<#
.SYNOPSIS
    Gaming PC Remote Mode toggle (VDD + Sunshine + stay-awake). Tailscale is not touched.
.EXAMPLE
    .\remote-mode.ps1 install
    .\remote-mode.ps1 on
    .\remote-mode.ps1 off
    .\remote-mode.ps1 doctor
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('on', 'off', 'status', 'doctor', 'install', 'uninstall', 'watch', 'apply-boot', 'gui', 'set-password')]
    [string]$Action = 'status',
    [switch]$FromLogon,
    [switch]$Once,
    [switch]$Json,
    [switch]$PasswordFromStdin
)

$ErrorActionPreference = 'Stop'
$script:RmToolRoot = $PSScriptRoot
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    $OutputEncoding = [Console]::OutputEncoding
}
catch { }

Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'lib') -Filter '*.ps1' | ForEach-Object {
    . $_.FullName
}

function Invoke-RmSelfElevate {
    $need = $Action -in @('on', 'off', 'install', 'uninstall', 'watch', 'apply-boot', 'gui', 'set-password')
    if (-not $need -or (Test-RmAdmin)) { return }
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        $Action
    )
    if ($FromLogon) { $argList += '-FromLogon' }
    if ($Once) { $argList += '-Once' }
    $wait = $Action -ne 'watch'
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait:$wait -PassThru
    if ($wait) { exit $p.ExitCode }
    exit 0
}

function Get-RmInstalledScript {
    $cands = @(
        (Join-Path $script:RmToolRoot 'remote-mode.ps1'),
        (Join-Path $env:LOCALAPPDATA 'RemoteMode\remote-mode.ps1'),
        (Join-Path $script:RmDataDir 'remote-mode.ps1')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | ForEach-Object { Get-Item -LiteralPath $_ }
    if (-not $cands) { return (Join-Path $script:RmToolRoot 'remote-mode.ps1') }
    return ($cands | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).FullName
}

function Start-RmWatchProcess {
    param([switch]$FromLogon)
    if (Test-RmWatchRunning) {
        Write-RmLog 'watchdog가 이미 실행 중입니다.'
        return
    }
    $scriptPath = Get-RmInstalledScript
    $args = @(
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass',
        '-File', $scriptPath,
        'watch'
    )
    if ($FromLogon) { $args += '-FromLogon' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden | Out-Null
    Write-RmLog 'watchdog 프로세스를 시작했습니다.'
}

function Stop-RmWatchProcess {
    if (-not (Test-Path -LiteralPath $script:RmWatchPidPath)) { return }
    $watchPid = 0
    [void][int]::TryParse((Get-Content -LiteralPath $script:RmWatchPidPath -ErrorAction SilentlyContinue | Select-Object -First 1), [ref]$watchPid)
    if ($watchPid -gt 0) {
        $p = Get-Process -Id $watchPid -ErrorAction SilentlyContinue
        if ($p) {
            Write-RmLog ("watchdog 종료 (PID {0})" -f $watchPid)
            Stop-Process -Id $watchPid -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $script:RmWatchPidPath -Force -ErrorAction SilentlyContinue
}

function Invoke-RmWatchTick {
    $state = Get-RmState
    if ($state.desired -ne 'on') { return }

    $vdd = Get-RmVddStatus
    if ($vdd.Present -and -not $vdd.Enabled) {
        Write-RmLog 'watch: VDD가 꺼져 있어 다시 켭니다.' 'WARN'
        Enable-RmVdd
        [void](Restore-RmDeskPrimary)
        [void](Wait-RmVddReady -TimeoutSeconds 5)
        [void](Restore-RmDeskPrimary)
    }

    $sun = Get-RmSunshineStatus
    if ($sun.Present -and $sun.Status -ne 'Running') {
        Write-RmLog 'watch: Sunshine이 멈춰 있어 다시 시작합니다.' 'WARN'
        Start-RmSunshine
    }

    $rc = Restore-RmDeskPrimary
    if ($rc -notin @('already-primary', 'vdd-only', 'no-displays', 'ok')) {
        Write-RmLog ("watch: 메인 전환 결과 {0}" -f $rc) 'WARN'
    }

    try { Enter-RmExecutionState } catch { }
}

function Invoke-RmWatch {
    $state = Get-RmState
    if ($state.desired -ne 'on') {
        Write-RmLog 'desired=off 이라 watchdog를 끝냅니다.'
        return
    }

    if ($Once) {
        Invoke-RmWatchTick
        if (-not (Test-RmWatchRunning)) { Start-RmWatchProcess }
        return
    }

    $created = $false
    $mutex = New-Object System.Threading.Mutex($false, 'Global\RemoteModeWatchdog', [ref]$created)
    if (-not $mutex.WaitOne(0)) {
        Write-RmLog '다른 watchdog가 이미 실행 중입니다.'
        return
    }
    try {
        Initialize-RmDataDir
        $PID | Set-Content -LiteralPath $script:RmWatchPidPath -Encoding ASCII
        Enter-RmExecutionState
        if ($FromLogon) {
            Start-Sleep -Seconds 8
            try {
                Start-Process -FilePath "$env:SystemRoot\System32\rundll32.exe" -ArgumentList 'user32.dll,LockWorkStation' | Out-Null
                Write-RmLog '로그온 후 워크스테이션을 잠갔습니다.'
            }
            catch {
                Write-RmLog ("잠금 실패: {0}" -f $_.Exception.Message) 'WARN'
            }
        }
        Write-RmLog 'watchdog 루프 시작'
        while ($true) {
            $state = Get-RmState
            if ($state.desired -ne 'on') { break }
            Invoke-RmWatchTick
            Start-Sleep -Seconds 30
        }
        Write-RmLog 'watchdog 루프 종료'
    }
    finally {
        Exit-RmExecutionState
        Remove-Item -LiteralPath $script:RmWatchPidPath -Force -ErrorAction SilentlyContinue
        $mutex.ReleaseMutex() | Out-Null
        $mutex.Dispose()
    }
}

function Invoke-RmApplyPayload {
    param([switch]$SkipDisplay)
    Enable-RmStayAwake
    Enable-RmUpdateHold
    Enable-RmAutologon

    $preferred = $null
    try {
        $preferred = @(Get-RmDisplayList | Where-Object Primary | Select-Object -First 1).Adapter
    }
    catch { }

    Enable-RmVdd
    if (-not $SkipDisplay) {
        # VDD enable can steal primary immediately. Restore the desk monitor
        # before any long wait so the user can still see the screen.
        [void](Restore-RmDeskPrimary -PreferredAdapter $preferred)
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 200
            $rc = Restore-RmDeskPrimary -PreferredAdapter $preferred
            if ($rc -in @('already-primary', 'ok')) { break }
        }
        $kind = Get-RmPrimaryKind
        Write-RmLog ("메인 디스플레이: {0} / kind={1}" -f (Restore-RmDeskPrimary -PreferredAdapter $preferred), $kind)
    }

    [void](Wait-RmVddReady -TimeoutSeconds 8)
    if (-not $SkipDisplay) {
        [void](Restore-RmDeskPrimary -PreferredAdapter $preferred)
    }
    Start-RmSunshine
    if (-not $SkipDisplay) {
        [void](Restore-RmDeskPrimary -PreferredAdapter $preferred)
    }
}

function Invoke-RmOn {
    Assert-RmAdmin
    $state = Get-RmState
    $state.desired = 'on'
    $state.lastOn = (Get-Date).ToString('o')
    Save-RmState $state
    Write-RmLog 'Remote Mode ON'
    Invoke-RmApplyPayload
    Start-RmWatchProcess
    Write-RmLog 'Remote Mode ON 완료. 모니터를 끄고 나가도 이 상태는 유지됩니다. 끌 때는 off를 실행하세요.'
}

function Invoke-RmOff {
    Assert-RmAdmin
    Write-RmLog 'Remote Mode OFF'
    $state = Get-RmState
    $state.desired = 'off'
    $state.lastOff = (Get-Date).ToString('o')
    Save-RmState $state
    Stop-RmWatchProcess
    Stop-RmSunshine
    Disable-RmAutologon
    Disable-RmStayAwake
    Disable-RmUpdateHold
    Disable-RmVdd
    Complete-RmDeskAfterOff
    Write-RmLog 'Remote Mode OFF 완료.'
}

function Invoke-RmApplyBoot {
    Assert-RmAdmin
    $state = Get-RmState
    if ($state.desired -ne 'on') {
        Write-RmLog '부팅 적용 건너뜀 (desired=off)'
        return
    }
    Write-RmLog '부팅 후 Remote Mode 재적용 (Session 0 — 디스플레이 전환 없음)'
    Invoke-RmApplyPayload -SkipDisplay
}

function Get-RmTaskNames {
    @(
        'RemoteMode-Boot',
        'RemoteMode-Logon',
        'RemoteMode-WatchPulse',
        'RemoteMode-On',
        'RemoteMode-Off'
    )
}

function Write-RmStatus {
    Get-RmLiveSnapshot
}

function Write-RmStatusJson {
    $s = Get-RmLiveSnapshot
    $checked = $null
    if ($s.CheckedAt) {
        try { $checked = ([datetime]$s.CheckedAt).ToString('o') } catch { $checked = [string]$s.CheckedAt }
    }
    $obj = [ordered]@{
        Mode            = [string]$s.Mode
        Desired         = [string]$s.Desired
        PayloadOn       = [bool]$s.PayloadOn
        Tailscale       = [string]$s.Tailscale
        TailscaleStart  = [string]$s.TailscaleStart
        VddEnabled      = [bool]$s.VddEnabled
        VddStatus       = [string]$s.VddStatus
        Sunshine        = [string]$s.Sunshine
        SunshineStart   = [string]$s.SunshineStart
        AutologonArmed  = [bool]$s.AutologonArmed
        AutologonSecret = [bool]$s.AutologonSecret
        PrimaryKind     = [string]$s.PrimaryKind
        PhysicalActive  = [bool]$s.PhysicalActive
        Watchdog        = [bool]$s.Watchdog
        PendingReboot   = [string]$s.PendingReboot
        LastOn          = [string]$s.LastOn
        LastOff         = [string]$s.LastOff
        Issues          = @($s.Issues)
        PhysicalMonitor = [string]$s.PhysicalMonitor
        VddInstanceId   = [string]$s.VddInstanceId
        CheckedAt       = $checked
    }
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 5))
}

function Read-RmPasswordFromStdin {
    $plain = [Console]::In.ReadLine()
    if ([string]::IsNullOrWhiteSpace($plain)) {
        throw 'stdin 비밀번호가 비어 있습니다.'
    }
    ConvertTo-SecureString $plain -AsPlainText -Force
}

function Invoke-RmSetPassword {
    Assert-RmAdmin
    Save-RmAutologonSecret -Password (Read-RmPasswordFromStdin)
}

function Get-RmBuiltGuiExe {
    $root = Get-RmToolRoot
    @(
        (Join-Path $root 'gui\dist\RemoteMode.exe'),
        (Join-Path $root 'gui\RemoteMode.Gui\bin\Release\net8.0-windows\win-x64\publish\RemoteMode.exe'),
        (Join-Path $root 'gui\RemoteMode.Gui\bin\Debug\net8.0-windows\RemoteMode.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Get-RmGuiExeCandidates {
    @(
        (Join-Path $script:RmDataDir 'RemoteMode.exe'),
        (Get-RmBuiltGuiExe)
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
}

function Invoke-RmDoctor {
    Write-Host '=== Remote Mode doctor ===' -ForegroundColor Cyan
    $s = Write-RmStatus
    $s | Format-List | Out-Host

    Write-Host '--- 디스플레이 ---' -ForegroundColor Cyan
    try { Get-RmDisplayList | Format-Table Adapter, Monitor, Kind, Primary, Width, Height -AutoSize | Out-Host }
    catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }

    Write-Host '--- 전원 AC ---' -ForegroundColor Cyan
    $snap = Get-RmPowerSnapshot
    [pscustomobject]@{
        StandbyIdle   = $snap.StandbyIdle
        HibernateIdle = $snap.HibernateIdle
        HybridSleep   = $snap.HybridSleep
        Unattended    = $snap.Unattended
    } | Format-List | Out-Host
    $snap.Nic | Format-Table Name, Description, PnPCapabilities -AutoSize | Out-Host

    Write-Host '--- 모니터 PnP ---' -ForegroundColor Cyan
    Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue |
        Select-Object Status, FriendlyName, InstanceId |
        Format-Table -AutoSize | Out-Host

    $ts = Get-RmTailscaleStatus
    Write-Host '--- Tailscale ---' -ForegroundColor Cyan
    Write-Host ("서비스: {0}" -f $ts.Status)
}

function New-RmScheduledTaskAction {
    param([string]$ArgLine)
    $scriptPath = Join-Path $script:RmDataDir 'remote-mode.ps1'
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $ArgLine"
    New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args
}

function Install-RmScheduledTasks {
    $user = Get-RmCurrentUser
    $hiUser = New-ScheduledTaskPrincipal -UserId $user.FullName -LogonType Interactive -RunLevel Highest
    $hiSys = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

    $boot = New-ScheduledTask -Action (New-RmScheduledTaskAction 'apply-boot') `
        -Principal $hiSys `
        -Trigger (New-ScheduledTaskTrigger -AtStartup) `
        -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable)
    Register-ScheduledTask -TaskName 'RemoteMode-Boot' -InputObject $boot -Force | Out-Null

    $logon = New-ScheduledTask -Action (New-RmScheduledTaskAction 'watch -FromLogon') `
        -Principal $hiUser `
        -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user.FullName) `
        -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable)
    Register-ScheduledTask -TaskName 'RemoteMode-Logon' -InputObject $logon -Force | Out-Null

    $pulseTrigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
        -RepetitionInterval (New-TimeSpan -Minutes 2) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    $pulse = New-ScheduledTask -Action (New-RmScheduledTaskAction 'watch -Once') `
        -Principal $hiUser `
        -Trigger $pulseTrigger `
        -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew)
    Register-ScheduledTask -TaskName 'RemoteMode-WatchPulse' -InputObject $pulse -Force | Out-Null

    $onTask = New-ScheduledTask -Action (New-RmScheduledTaskAction 'on') `
        -Principal $hiUser `
        -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries)
    Register-ScheduledTask -TaskName 'RemoteMode-On' -InputObject $onTask -Force | Out-Null

    $offTask = New-ScheduledTask -Action (New-RmScheduledTaskAction 'off') `
        -Principal $hiUser `
        -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries)
    Register-ScheduledTask -TaskName 'RemoteMode-Off' -InputObject $offTask -Force | Out-Null

    Write-RmLog ("스케줄 작업 등록 완료 (사용자 {0})" -f $user.FullName)
}

function Set-RmShortcutRunAsAdmin {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 0x15) {
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [IO.File]::WriteAllBytes($Path, $bytes)
    }
}

function Install-RmShortcuts {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $w = New-Object -ComObject WScript.Shell

    $exe = $null
    $built = Get-RmBuiltGuiExe
    $destExe = Join-Path $script:RmDataDir 'RemoteMode.exe'
    if ($built) {
        Copy-Item -LiteralPath $built -Destination $destExe -Force
        $exe = $destExe
        Write-RmLog "GUI 복사: $built -> $destExe"
    }
    elseif (Test-Path -LiteralPath $destExe) {
        $exe = $destExe
    }
    if ($exe) {
        $guiLnk = Join-Path $desktop 'Remote Mode.lnk'
        $sc = $w.CreateShortcut($guiLnk)
        $sc.TargetPath = $destExe
        $sc.WorkingDirectory = $script:RmDataDir
        $sc.WindowStyle = 1
        $sc.Description = 'Remote Mode GUI (Administrator)'
        $sc.Save()
        Set-RmShortcutRunAsAdmin $guiLnk
        Write-RmLog "바로가기: $guiLnk -> $destExe"
    }
    else {
        Write-RmLog 'RemoteMode.exe가 없어 GUI 바로가기를 건너뜁니다. gui 폴더에서 dotnet publish 후 install을 다시 실행하세요.' 'WARN'
    }

    foreach ($pair in @(
            @{ Name = 'Remote ON.lnk'; Task = 'RemoteMode-On' },
            @{ Name = 'Remote OFF.lnk'; Task = 'RemoteMode-Off' }
        )) {
        $path = Join-Path $desktop $pair.Name
        $sc = $w.CreateShortcut($path)
        $sc.TargetPath = "$env:SystemRoot\System32\schtasks.exe"
        $sc.Arguments = "/Run /TN `"$($pair.Task)`""
        $sc.WorkingDirectory = $script:RmDataDir
        $sc.WindowStyle = 7
        $sc.Description = 'Remote Mode'
        $sc.Save()
        Write-RmLog "바로가기: $path"
    }
}

function Invoke-RmInstall {
    Assert-RmAdmin
    Initialize-RmDataDir
    $already = [bool](Get-ScheduledTask -TaskName 'RemoteMode-Boot' -ErrorAction SilentlyContinue)
    if ($already) {
        Write-RmLog '이미 설치되어 있습니다. 파일과 스케줄을 최신으로 갱신합니다.'
    }
    else {
        Write-RmLog '이 PC에 Remote Mode를 설치합니다. (부팅 복구 스케줄/바로가기)'
    }

    $libDst = Join-Path $script:RmDataDir 'lib'
    New-Item -ItemType Directory -Path $libDst -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RmToolRoot 'remote-mode.ps1') -Destination $script:RmDataDir -Force
    Copy-Item -LiteralPath (Join-Path $script:RmToolRoot 'config.json') -Destination $script:RmDataDir -Force
    Copy-Item -Path (Join-Path $script:RmToolRoot 'lib\*.ps1') -Destination $libDst -Force
    Write-RmLog "파일을 $script:RmDataDir 에 복사했습니다."

    Backup-RmSunshinePrep

    if (-not (Test-RmAutologonSecret)) {
        if ($PasswordFromStdin) {
            Save-RmAutologonSecret -Password (Read-RmPasswordFromStdin)
        }
        else {
            Save-RmAutologonSecret
        }
    }

    Install-RmScheduledTasks
    Install-RmShortcuts
    if ($already) {
        Write-RmLog '설치 갱신 완료. Remote ON/OFF 상태는 그대로입니다.'
    }
    else {
        Write-RmLog '설치 완료. 바탕화면 Remote Mode GUI 또는 Remote ON / OFF 를 사용하세요.'
    }
}

function Invoke-RmUninstall {
    Assert-RmAdmin
    $state = Get-RmState
    if ($state.desired -eq 'on') {
        Write-RmLog 'uninstall 전에 Remote OFF를 적용합니다.'
        Invoke-RmOff
    }
    foreach ($n in Get-RmTaskNames) {
        Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue
    }
    $desktop = [Environment]::GetFolderPath('Desktop')
    Remove-Item -LiteralPath (Join-Path $desktop 'Remote ON.lnk') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $desktop 'Remote OFF.lnk') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $desktop 'Remote Mode.lnk') -Force -ErrorAction SilentlyContinue
    Write-RmLog '스케줄과 바로가기를 제거했습니다. ProgramData 상태 파일은 남겼습니다.'
}

function Invoke-RmLaunchGui {
    $exe = Get-RmGuiExeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $exe) { throw 'RemoteMode.exe를 찾을 수 없습니다. gui 프로젝트에서 dotnet publish 하세요.' }
    Start-Process -FilePath $exe | Out-Null
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-RmSelfElevate
        switch ($Action) {
            'on' { Invoke-RmOn }
            'off' { Invoke-RmOff }
            'status' {
                if ($Json) { Write-RmStatusJson }
                else { Write-RmStatus | Format-List | Out-Host }
            }
            'doctor' { Invoke-RmDoctor }
            'install' { Invoke-RmInstall }
            'uninstall' { Invoke-RmUninstall }
            'watch' { Invoke-RmWatch }
            'apply-boot' { Invoke-RmApplyBoot }
            'gui' { Invoke-RmLaunchGui }
            'set-password' { Invoke-RmSetPassword }
        }
    }
    catch {
        try { Write-RmLog $_ 'ERROR' } catch { Write-Host $_ -ForegroundColor Red }
        exit 1
    }
}
