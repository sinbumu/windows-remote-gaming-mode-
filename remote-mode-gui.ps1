#Requires -Version 5.1
# Administrator WinForms GUI. Always re-queries live device/service state on open and after actions.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Test-RmGuiAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isSta = [Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA'
$isAdmin = Test-RmGuiAdmin
if (-not ($isSta -and $isAdmin)) {
    $argList = @(
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath
    )
    if ($isAdmin) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList | Out-Null
    }
    else {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
    }
    exit
}

$script:RmToolRoot = $PSScriptRoot
. (Join-Path $PSScriptRoot 'remote-mode.ps1')

$script:RmGuiBusy = $false

function Read-RmLogTail {
    param([int]$Lines = 200)
    if (-not (Test-Path -LiteralPath $script:RmLogPath)) { return @() }
    return Get-Content -LiteralPath $script:RmLogPath -Tail $Lines -ErrorAction SilentlyContinue
}

function Show-RmPasswordPrompt {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = '자동 로그인 비밀번호'
    $dlg.Size = New-Object System.Drawing.Size(420, 160)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Remote ON 시 재부팅 복구에 씁니다. 이 PC 사용자 비밀번호.'
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(16, 16)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.UseSystemPasswordChar = $true
    $tb.Location = New-Object System.Drawing.Point(16, 48)
    $tb.Width = 370
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = '저장'
    $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(210, 82)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = '취소'
    $cancel.DialogResult = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(300, 82)
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel
    $dlg.Controls.AddRange(@($lbl, $tb, $ok, $cancel))
    if ($dlg.ShowDialog() -ne 'OK') { return $null }
    if ([string]::IsNullOrWhiteSpace($tb.Text)) { return $null }
    $sec = ConvertTo-SecureString $tb.Text -AsPlainText -Force
    $tb.Text = ''
    return $sec
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Remote Mode'
$form.Size = New-Object System.Drawing.Size(960, 720)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(820, 600)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Font = New-Object System.Drawing.Font('Segoe UI', 28, [System.Drawing.FontStyle]::Bold)
$lblMode.AutoSize = $true
$lblMode.Location = New-Object System.Drawing.Point(20, 16)
$lblMode.Text = '확인 중'

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.AutoSize = $false
$lblSub.Location = New-Object System.Drawing.Point(24, 68)
$lblSub.Size = New-Object System.Drawing.Size(900, 22)
$lblSub.ForeColor = [System.Drawing.Color]::DimGray
$lblSub.Text = '장치를 다시 읽고 있습니다.'

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(20, 98)
$grid.Size = New-Object System.Drawing.Size(900, 196)
$grid.Anchor = 'Top,Left,Right'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.BorderStyle = 'FixedSingle'
$grid.AutoSizeColumnsMode = 'Fill'
$grid.ColumnCount = 3
$grid.Columns[0].Name = '항목'
$grid.Columns[1].Name = '실제 값'
$grid.Columns[2].Name = '기대 (Remote ON)'
$grid.Columns[0].FillWeight = 28
$grid.Columns[1].FillWeight = 36
$grid.Columns[2].FillWeight = 36

$btnOn = New-Object System.Windows.Forms.Button
$btnOn.Text = 'Remote ON'
$btnOn.Size = New-Object System.Drawing.Size(140, 36)
$btnOn.Location = New-Object System.Drawing.Point(20, 306)

$btnOff = New-Object System.Windows.Forms.Button
$btnOff.Text = 'Remote OFF'
$btnOff.Size = New-Object System.Drawing.Size(140, 36)
$btnOff.Location = New-Object System.Drawing.Point(170, 306)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = '다시 확인'
$btnRefresh.Size = New-Object System.Drawing.Size(140, 36)
$btnRefresh.Location = New-Object System.Drawing.Point(320, 306)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = '설치'
$btnInstall.Size = New-Object System.Drawing.Size(100, 36)
$btnInstall.Location = New-Object System.Drawing.Point(470, 306)

$lblBusy = New-Object System.Windows.Forms.Label
$lblBusy.AutoSize = $true
$lblBusy.Location = New-Object System.Drawing.Point(590, 314)
$lblBusy.ForeColor = [System.Drawing.Color]::DimGray
$lblBusy.Text = ''

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = '로그'
$lblLog.Location = New-Object System.Drawing.Point(20, 356)
$lblLog.AutoSize = $true
$lblLog.Anchor = 'Top,Left'

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Both'
$txtLog.ReadOnly = $true
$txtLog.WordWrap = $false
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Location = New-Object System.Drawing.Point(20, 378)
$txtLog.Size = New-Object System.Drawing.Size(900, 270)
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)

$form.Controls.AddRange(@(
        $lblMode, $lblSub, $grid,
        $btnOn, $btnOff, $btnRefresh, $btnInstall, $lblBusy,
        $lblLog, $txtLog
    ))

function Append-RmGuiLog {
    param([string]$Line)
    if ($txtLog.IsDisposed) { return }
    $txtLog.AppendText($Line + [Environment]::NewLine)
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-RmGuiBusy {
    param([bool]$Busy, [string]$Text = '')
    $script:RmGuiBusy = $Busy
    $btnOn.Enabled = -not $Busy
    $btnOff.Enabled = -not $Busy
    $btnRefresh.Enabled = -not $Busy
    $btnInstall.Enabled = -not $Busy
    $lblBusy.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-RmGuiStatus {
    Write-RmLog 'GUI: 실제 장치/서비스 상태를 다시 조회합니다.'
    $snap = Get-RmLiveSnapshot
    switch ($snap.Mode) {
        'ON' {
            $lblMode.Text = 'ON'
            $lblMode.ForeColor = [System.Drawing.Color]::ForestGreen
            $lblSub.Text = '기록 desired=on 과 VDD/Sunshine 실상태가 일치합니다.  {0}' -f $snap.CheckedAt.ToString('HH:mm:ss')
        }
        'OFF' {
            $lblMode.Text = 'OFF'
            $lblMode.ForeColor = [System.Drawing.Color]::DimGray
            $lblSub.Text = '기록 desired=off 과 VDD/Sunshine 실상태가 일치합니다.  {0}' -f $snap.CheckedAt.ToString('HH:mm:ss')
        }
        default {
            $lblMode.Text = '불일치'
            $lblMode.ForeColor = [System.Drawing.Color]::DarkGoldenrod
            $why = if ($snap.Issues.Count) { $snap.Issues -join ', ' } else { '부분 적용' }
            $lblSub.Text = '창을 다시 열 때마다 실상태를 읽습니다. 지금: {0}  ({1})' -f $why, $snap.CheckedAt.ToString('HH:mm:ss')
        }
    }

    $grid.Rows.Clear()
    [void]$grid.Rows.Add('기록 desired', $snap.Desired, 'on 이면 Remote 유지')
    [void]$grid.Rows.Add('Tailscale', $snap.Tailscale, 'Running (상시, 토글 아님)')
    [void]$grid.Rows.Add('VDD', ('{0} ({1})' -f $snap.VddEnabled, $snap.VddStatus), 'Enabled')
    [void]$grid.Rows.Add('Sunshine', ('{0} / {1}' -f $snap.Sunshine, $snap.SunshineStart), 'Running / Automatic')
    [void]$grid.Rows.Add('자동 로그인', $snap.AutologonArmed, 'Armed')
    [void]$grid.Rows.Add('메인 디스플레이', $snap.PrimaryKind, 'Physical (모니터 켜져 있을 때)')
    [void]$grid.Rows.Add('물리 모니터', $snap.PhysicalActive, '켜져 있으면 True')
    [void]$grid.Rows.Add('Watchdog', $snap.Watchdog, 'Running')
    if ($snap.PendingReboot) {
        [void]$grid.Rows.Add('재시작 대기', $snap.PendingReboot, '없음')
    }
    return $snap
}

function Invoke-RmGuiAction {
    param([ValidateSet('on', 'off', 'install', 'refresh')][string]$Kind)
    if ($script:RmGuiBusy) { return }
    try {
        Set-RmGuiBusy $true ($Kind + ' 실행 중...')
        switch ($Kind) {
            'refresh' { }
            'install' {
                if (-not (Test-RmAutologonSecret)) {
                    $sec = Show-RmPasswordPrompt
                    if ($sec) { Save-RmAutologonSecret -Password $sec }
                    else { Write-RmLog '비밀번호 입력을 건너뛰었습니다. 설치는 계속합니다.' 'WARN' }
                }
                Invoke-RmInstall
            }
            'on' {
                if (-not (Test-RmAutologonSecret)) {
                    $sec = Show-RmPasswordPrompt
                    if (-not $sec) { throw '자동 로그인 비밀번호가 필요합니다.' }
                    Save-RmAutologonSecret -Password $sec
                }
                Invoke-RmOn
            }
            'off' { Invoke-RmOff }
        }
        [void](Update-RmGuiStatus)
        Write-RmLog 'GUI: 조작 후 실상태 재확인 완료.'
    }
    catch {
        Write-RmLog "$_" 'ERROR'
        try { [void](Update-RmGuiStatus) } catch { }
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Remote Mode', 'OK', 'Error') | Out-Null
    }
    finally {
        Set-RmGuiBusy $false
    }
}

$script:RmLogCallback = {
    param($Line, $Level)
    Append-RmGuiLog $Line
}

$btnOn.Add_Click({ Invoke-RmGuiAction 'on' })
$btnOff.Add_Click({ Invoke-RmGuiAction 'off' })
$btnRefresh.Add_Click({ Invoke-RmGuiAction 'refresh' })
$btnInstall.Add_Click({ Invoke-RmGuiAction 'install' })

$form.Add_Shown({
        foreach ($line in (Read-RmLogTail)) { Append-RmGuiLog $line }
        Append-RmGuiLog ('----- {0} GUI 시작, 실상태 조회 -----' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        try { [void](Update-RmGuiStatus) }
        catch { Write-RmLog "$_" 'ERROR' }
    })

$form.Add_FormClosed({
        $script:RmLogCallback = $null
    })

[System.Windows.Forms.Application]::Run($form)
