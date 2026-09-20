# Pause Windows Update reboots while Remote Mode is on. Restore on OFF.

function Get-RmUpdateKey {
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
}

function Get-RmUpdateUxKey {
    'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
}

function Get-RmPendingReboot {
    $hints = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $hints += 'CBS RebootPending'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $hints += 'WU RebootRequired'
    }
    return $hints
}

function Enable-RmUpdateHold {
    Assert-RmAdmin
    $state = Get-RmState
    $au = Get-RmUpdateKey
    $ux = Get-RmUpdateUxKey
    if (-not (Test-Path $au)) { New-Item -Path $au -Force | Out-Null }

    if (-not $state.updateBackup) {
        $auProps = Get-ItemProperty $au -ErrorAction SilentlyContinue
        $uxProps = Get-ItemProperty $ux -ErrorAction SilentlyContinue
        $state.updateBackup = [pscustomobject]@{
            NoAutoRebootWithLoggedOnUsers = $auProps.NoAutoRebootWithLoggedOnUsers
            AUOptions                     = $auProps.AUOptions
            PauseUpdatesExpiryTime        = $uxProps.PauseUpdatesExpiryTime
        }
        Save-RmState $state
        Write-RmLog 'Windows Update 정책을 백업했습니다.'
    }

    New-ItemProperty -Path $au -Name NoAutoRebootWithLoggedOnUsers -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $au -Name AUOptions -PropertyType DWord -Value 3 -Force | Out-Null

    $expiry = (Get-Date).ToUniversalTime().AddDays(7).ToString('o')
    if (Test-Path $ux) {
        New-ItemProperty -Path $ux -Name PauseUpdatesExpiryTime -PropertyType String -Value $expiry -Force | Out-Null
        New-ItemProperty -Path $ux -Name PauseFeatureUpdatesStartTime -PropertyType String -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force | Out-Null
        New-ItemProperty -Path $ux -Name PauseQualityUpdatesStartTime -PropertyType String -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force | Out-Null
        New-ItemProperty -Path $ux -Name PauseFeatureUpdatesEndTime -PropertyType String -Value $expiry -Force | Out-Null
        New-ItemProperty -Path $ux -Name PauseQualityUpdatesEndTime -PropertyType String -Value $expiry -Force | Out-Null
    }
    Write-RmLog 'Windows Update 자동 재시작을 억제하고 업데이트를 일시 중지했습니다.'
}

function Disable-RmUpdateHold {
    Assert-RmAdmin
    $state = Get-RmState
    $au = Get-RmUpdateKey
    $ux = Get-RmUpdateUxKey
    $bak = $state.updateBackup
    if (-not $bak) {
        Write-RmLog '업데이트 백업이 없어 기본 억제만 해제합니다.' 'WARN'
        Remove-ItemProperty -Path $au -Name NoAutoRebootWithLoggedOnUsers -ErrorAction SilentlyContinue
        return
    }

    if ($null -ne $bak.NoAutoRebootWithLoggedOnUsers) {
        New-ItemProperty -Path $au -Name NoAutoRebootWithLoggedOnUsers -PropertyType DWord -Value ([int]$bak.NoAutoRebootWithLoggedOnUsers) -Force | Out-Null
    }
    else {
        Remove-ItemProperty -Path $au -Name NoAutoRebootWithLoggedOnUsers -ErrorAction SilentlyContinue
    }
    if ($null -ne $bak.AUOptions) {
        New-ItemProperty -Path $au -Name AUOptions -PropertyType DWord -Value ([int]$bak.AUOptions) -Force | Out-Null
    }
    else {
        Remove-ItemProperty -Path $au -Name AUOptions -ErrorAction SilentlyContinue
    }
    if (Test-Path $ux) {
        foreach ($n in @('PauseUpdatesExpiryTime', 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime')) {
            Remove-ItemProperty -Path $ux -Name $n -ErrorAction SilentlyContinue
        }
    }
    $state.updateBackup = $null
    Save-RmState $state
    Write-RmLog 'Windows Update 정책을 복원했습니다.'
}
