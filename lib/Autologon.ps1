# Winlogon autologon. Password stored DPAPI LocalMachine in ProgramData.

function Get-RmAutologonWinlogonPath {
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
}

function Get-RmAutologonTargetUser {
    if (Test-Path -LiteralPath $script:RmAutologonUserPath) {
        return Get-Content -LiteralPath $script:RmAutologonUserPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $u = Get-RmCurrentUser
    if ($u.User -in @('SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE')) {
        throw '자동 로그인 대상 사용자가 없습니다. 일반 계정에서 install 또는 on을 한 번 실행하세요.'
    }
    return $u
}

function Save-RmAutologonTargetUser {
    $u = Get-RmCurrentUser
    if ($u.User -in @('SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE')) { return }
    Initialize-RmDataDir
    $json = @{ Domain = $u.Domain; User = $u.User; FullName = $u.FullName } | ConvertTo-Json
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:RmAutologonUserPath, $json, $utf8)
}

function Test-RmAutologonSecret {
    Test-Path -LiteralPath $script:RmAutologonPath
}

function Protect-RmPassword {
    param([Parameter(Mandatory)][string]$Plain)
    Add-Type -AssemblyName System.Security
    $bytes = [Text.Encoding]::UTF8.GetBytes($Plain)
    $prot = [Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $script:RmEntropy,
        [Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    Initialize-RmDataDir
    [IO.File]::WriteAllBytes($script:RmAutologonPath, $prot)
    try {
        $acl = Get-Acl $script:RmAutologonPath
        $acl.SetAccessRuleProtection($true, $false)
        $admins = New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators', 'FullControl', 'Allow')
        $sys = New-Object System.Security.AccessControl.FileSystemAccessRule('NT AUTHORITY\SYSTEM', 'FullControl', 'Allow')
        $acl.AddAccessRule($admins)
        $acl.AddAccessRule($sys)
        Set-Acl $script:RmAutologonPath $acl
    }
    catch {
        Write-RmLog ("autologon.bin ACL 설정 실패: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Unprotect-RmPassword {
    if (-not (Test-RmAutologonSecret)) { return $null }
    Add-Type -AssemblyName System.Security
    $prot = [IO.File]::ReadAllBytes($script:RmAutologonPath)
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect(
        $prot,
        $script:RmEntropy,
        [Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    return [Text.Encoding]::UTF8.GetString($bytes)
}

function Save-RmAutologonSecret {
    param([System.Security.SecureString]$Password)
    if (-not $Password) {
        $Password = Read-Host '자동 로그인에 쓸 Windows 비밀번호' -AsSecureString
    }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        if ([string]::IsNullOrWhiteSpace($plain)) {
            throw '비밀번호가 비어 있습니다.'
        }
        Protect-RmPassword $plain
        Save-RmAutologonTargetUser
        Write-RmLog '자동 로그인 비밀번호를 DPAPI로 저장했습니다.'
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Enable-RmAutologon {
    Assert-RmAdmin
    if (-not (Test-RmAutologonSecret)) {
        Write-RmLog '저장된 비밀번호가 없습니다. 지금 입력하세요.' 'WARN'
        Save-RmAutologonSecret
    }
    Save-RmAutologonTargetUser
    $plain = Unprotect-RmPassword
    if (-not $plain) { throw '자동 로그인 비밀번호를 읽을 수 없습니다.' }

    $user = Get-RmAutologonTargetUser
    $key = Get-RmAutologonWinlogonPath
    New-ItemProperty -Path $key -Name AutoAdminLogon -Value '1' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name DefaultUserName -Value $user.User -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name DefaultDomainName -Value $user.Domain -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name DefaultPassword -Value $plain -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name ForceAutoLogon -Value '1' -PropertyType String -Force | Out-Null
    Write-RmLog ("자동 로그인 무장: {0}" -f $user.FullName)
}

function Disable-RmAutologon {
    Assert-RmAdmin
    $key = Get-RmAutologonWinlogonPath
    New-ItemProperty -Path $key -Name AutoAdminLogon -Value '0' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name ForceAutoLogon -Value '0' -PropertyType String -Force | Out-Null
    Remove-ItemProperty -Path $key -Name DefaultPassword -ErrorAction SilentlyContinue
    Write-RmLog '자동 로그인을 해제했습니다.'
}

function Get-RmAutologonStatus {
    $key = Get-RmAutologonWinlogonPath
    $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ArmedInRegistry = ($props.AutoAdminLogon -eq '1')
        SecretOnDisk    = (Test-RmAutologonSecret)
        User            = $props.DefaultUserName
        Domain          = $props.DefaultDomainName
    }
}
