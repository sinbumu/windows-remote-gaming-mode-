# Sleep / unattended sleep / hybrid sleep / NIC power saving. Backup and restore.

function Get-RmPowerAcIndex {
    param(
        [Parameter(Mandatory)][string]$Sub,
        [Parameter(Mandatory)][string]$Setting
    )
    $raw = powercfg /query SCHEME_CURRENT $Sub $Setting 2>&1 | Out-String
    $ac = $null
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -notmatch '0x[0-9A-Fa-f]+') { continue }
        if ($line -match 'DC') { continue }
        if ($line -match '(0x[0-9A-Fa-f]+)') {
            $ac = [Convert]::ToInt64($Matches[1], 16)
        }
    }
    return $ac
}

function Set-RmPowerAcIndex {
    param(
        [Parameter(Mandatory)][string]$Sub,
        [Parameter(Mandatory)][string]$Setting,
        [Parameter(Mandatory)][int64]$Value
    )
    powercfg /setacvalueindex SCHEME_CURRENT $Sub $Setting $Value | Out-Null
}

function Get-RmNicAdapters {
    $cfg = Get-RmConfig
    @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -like "*$($cfg.nicDescriptionPattern)*" })
}

function Get-RmNicPnpCapabilities {
    param($Adapter)
    $classPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
    foreach ($key in Get-ChildItem $classPath -ErrorAction SilentlyContinue) {
        $desc = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DriverDesc
        if (-not $desc -or -not $Adapter.InterfaceDescription) { continue }
        if ($Adapter.InterfaceDescription -like "$desc*" -or $desc -eq $Adapter.InterfaceDescription) {
            $pnp = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).PnPCapabilities
            return [pscustomobject]@{ Path = $key.PSPath; PnPCapabilities = $pnp }
        }
    }
    return $null
}

function Get-RmPowerSnapshot {
    $nics = @()
    foreach ($a in Get-RmNicAdapters) {
        $reg = @(Get-RmNicPnpCapabilities $a) | Select-Object -First 1
        $nics += [pscustomobject]@{
            Name            = $a.Name
            Description     = $a.InterfaceDescription
            Mac             = $a.MacAddress
            PnPCapabilities = if ($reg) { $reg.PnPCapabilities } else { $null }
            RegPath         = if ($reg) { $reg.Path } else { $null }
        }
    }
    return [pscustomobject]@{
        StandbyIdle    = Get-RmPowerAcIndex SUB_SLEEP 29f6c1db-86da-48c5-9fdb-f2b67b1f44da
        HibernateIdle  = Get-RmPowerAcIndex SUB_SLEEP 9d7815a6-7ee4-497e-8888-515a05f02364
        HybridSleep    = Get-RmPowerAcIndex SUB_SLEEP 94ac6d29-73ce-41a6-809f-6363ba21b47e
        Unattended     = Get-RmPowerAcIndex SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0
        Nic            = $nics
    }
}

function Enable-RmStayAwake {
    Assert-RmAdmin
    $state = Get-RmState
    if (-not $state.powerBackup) {
        $state.powerBackup = Get-RmPowerSnapshot
        Save-RmState $state
        Write-RmLog '전원/NIC 설정을 백업했습니다.'
    }

    Set-RmPowerAcIndex SUB_SLEEP 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0
    Set-RmPowerAcIndex SUB_SLEEP 9d7815a6-7ee4-497e-8888-515a05f02364 0
    Set-RmPowerAcIndex SUB_SLEEP 94ac6d29-73ce-41a6-809f-6363ba21b47e 0
    Set-RmPowerAcIndex SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 0
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    Write-RmLog '슬립/최대절전/하이브리드/무인 슬립을 0으로 잠갔습니다.'

    Disable-RmNicPowerSaving
}

function Disable-RmStayAwake {
    Assert-RmAdmin
    $state = Get-RmState
    $bak = $state.powerBackup
    if (-not $bak) {
        Write-RmLog '전원 백업이 없어 복원을 건너뜁니다.' 'WARN'
        return
    }
    if ($null -ne $bak.StandbyIdle) { Set-RmPowerAcIndex SUB_SLEEP 29f6c1db-86da-48c5-9fdb-f2b67b1f44da ([int64]$bak.StandbyIdle) }
    if ($null -ne $bak.HibernateIdle) { Set-RmPowerAcIndex SUB_SLEEP 9d7815a6-7ee4-497e-8888-515a05f02364 ([int64]$bak.HibernateIdle) }
    if ($null -ne $bak.HybridSleep) { Set-RmPowerAcIndex SUB_SLEEP 94ac6d29-73ce-41a6-809f-6363ba21b47e ([int64]$bak.HybridSleep) }
    if ($null -ne $bak.Unattended) { Set-RmPowerAcIndex SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 ([int64]$bak.Unattended) }
    powercfg /setactive SCHEME_CURRENT | Out-Null
    Restore-RmNicPowerSaving $bak
    $state.powerBackup = $null
    Save-RmState $state
    Write-RmLog '전원/NIC 설정을 복원했습니다.'
}

function Disable-RmNicPowerSaving {
    $allowOffBit = 24  # don't allow computer to turn off this device
    foreach ($a in Get-RmNicAdapters) {
        try {
            Disable-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop
            Write-RmLog ("NIC 절전 해제 (PowerManagement): {0}" -f $a.InterfaceDescription)
        }
        catch {
            Write-RmLog ("Disable-NetAdapterPowerManagement 실패 ({0}): {1}" -f $a.Name, $_.Exception.Message) 'WARN'
        }
        $reg = @(Get-RmNicPnpCapabilities $a) | Select-Object -First 1
        if ($reg -and $reg.Path) {
            $cur = 0
            if ($null -ne $reg.PnPCapabilities) { $cur = [int]$reg.PnPCapabilities }
            $next = $cur -bor $allowOffBit
            if ($next -ne $cur) {
                Set-ItemProperty -Path $reg.Path -Name PnPCapabilities -Value $next -Type DWord
                Write-RmLog ("NIC PnPCapabilities {0} -> {1} ({2})" -f $cur, $next, $a.Name)
            }
        }
    }
}

function Restore-RmNicPowerSaving {
    param($Backup)
    if (-not $Backup -or -not $Backup.Nic) { return }
    foreach ($n in @($Backup.Nic)) {
        if ($n.RegPath -and (Test-Path -LiteralPath $n.RegPath)) {
            if ($null -ne $n.PnPCapabilities) {
                Set-ItemProperty -Path $n.RegPath -Name PnPCapabilities -Value ([int]$n.PnPCapabilities) -Type DWord
            }
            else {
                Remove-ItemProperty -Path $n.RegPath -Name PnPCapabilities -ErrorAction SilentlyContinue
            }
        }
    }
}

function Initialize-RmExecutionState {
    if ('RmSleepUtil' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RmSleepUtil {
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
    public const uint ES_AWAYMODE_REQUIRED = 0x00000040;
    public const uint ES_CONTINUOUS = 0x80000000;
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
'@
}

function Enter-RmExecutionState {
    Initialize-RmExecutionState
    [void][RmSleepUtil]::SetThreadExecutionState(
        [RmSleepUtil]::ES_CONTINUOUS -bor [RmSleepUtil]::ES_SYSTEM_REQUIRED -bor [RmSleepUtil]::ES_AWAYMODE_REQUIRED
    )
}

function Exit-RmExecutionState {
    if ('RmSleepUtil' -as [type]) {
        [void][RmSleepUtil]::SetThreadExecutionState([RmSleepUtil]::ES_CONTINUOUS)
    }
}
