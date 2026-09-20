# Enable / disable MikeTheTech Virtual Display Driver.

function Get-RmVddDevice {
    $cfg = Get-RmConfig
    $dev = Get-PnpDevice -InstanceId $cfg.vddInstanceId -ErrorAction SilentlyContinue
    if ($dev) { return $dev }
    return Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -eq $cfg.vddFriendlyName } |
        Select-Object -First 1
}

function Get-RmVddStatus {
    $dev = Get-RmVddDevice
    if (-not $dev) {
        return [pscustomobject]@{ Present = $false; Enabled = $false; Status = 'Missing'; InstanceId = $null }
    }
    $enabled = ($dev.Status -eq 'OK') -and ($dev.Problem -ne 'CM_PROB_DISABLED')
    if ($dev.Problem -eq 'CM_PROB_DISABLED') { $enabled = $false }
    $status = $dev.Status
    if ($dev.Problem -eq 'CM_PROB_DISABLED') { $status = 'Disabled' }
    return [pscustomobject]@{
        Present    = $true
        Enabled    = $enabled
        Status     = $status
        Problem    = $dev.Problem
        InstanceId = $dev.InstanceId
        Name       = $dev.FriendlyName
    }
}

function Get-RmMonitorByHardwareId {
    param([Parameter(Mandatory)][string]$HardwareId)
    Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like "$HardwareId*" }
}

function Test-RmVddMonitorReady {
    $cfg = Get-RmConfig
    $mons = @(Get-RmMonitorByHardwareId -HardwareId $cfg.vddMonitorHardwareId)
    return ($mons | Where-Object { $_.Status -eq 'OK' }).Count -gt 0
}

function Enable-RmVdd {
    Assert-RmAdmin
    $dev = Get-RmVddDevice
    if (-not $dev) { throw 'Virtual Display Driver 장치를 찾을 수 없습니다.' }
    $st = Get-RmVddStatus
    if ($st.Enabled) {
        Write-RmLog 'VDD는 이미 켜져 있습니다.'
        return
    }
    Write-RmLog ("VDD 사용 설정: {0}" -f $dev.InstanceId)
    Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
}

function Disable-RmVdd {
    Assert-RmAdmin
    $dev = Get-RmVddDevice
    if (-not $dev) {
        Write-RmLog 'VDD 장치가 없어 끄기를 건너뜁니다.' 'WARN'
        return
    }
    $st = Get-RmVddStatus
    if (-not $st.Enabled) {
        Write-RmLog 'VDD는 이미 꺼져 있습니다.'
        return
    }
    Write-RmLog ("VDD 사용 안 함: {0}" -f $dev.InstanceId)
    Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
}

function Wait-RmVddReady {
    param([int]$TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-RmVddMonitorReady) { return $true }
        Start-Sleep -Milliseconds 500
    }
    Write-RmLog 'VDD 모니터(MTT1337)가 제한 시간 안에 준비되지 않았습니다.' 'WARN'
    return $false
}
