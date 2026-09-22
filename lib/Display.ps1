# GDI/CCD helpers: list displays and set the physical monitor as primary.
# Does not enable or disable VDD.

function Initialize-RmDisplayInterop {
    if ('RmDisplayNative' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class RmDisplayDeviceInfo {
    public string AdapterName;
    public string AdapterString;
    public string MonitorName;
    public string MonitorId;
    public bool AdapterPrimary;
    public bool AdapterAttached;
    public int PositionX;
    public int PositionY;
    public int Width;
    public int Height;
}

public static class RmDisplayNative {
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const uint CDS_UPDATEREGISTRY = 0x00000001;
    public const uint CDS_NORESET = 0x10000000;
    public const uint CDS_SET_PRIMARY = 0x00000010;
    public const uint DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x00000001;
    public const uint DISPLAY_DEVICE_PRIMARY_DEVICE = 0x00000004;
    public const int DISP_CHANGE_SUCCESSFUL = 0;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public uint StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        private const int CCHDEVICENAME = 32;
        private const int CCHFORMNAME = 32;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHDEVICENAME)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHFORMNAME)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, IntPtr lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    public const uint SDC_TOPOLOGY_EXTEND = 0x00000004;
    public const uint SDC_APPLY = 0x00000080;
    public const uint SDC_ALLOW_CHANGES = 0x00000400;

    [DllImport("user32.dll")]
    public static extern int SetDisplayConfig(uint numPathArrayElements, IntPtr pathArray, uint numModeInfoArrayElements, IntPtr modeInfoArray, uint flags);

    public static string ApplyExtendTopology() {
        int rc = SetDisplayConfig(0, IntPtr.Zero, 0, IntPtr.Zero, SDC_APPLY | SDC_TOPOLOGY_EXTEND);
        if (rc == 0) return "ok";
        rc = SetDisplayConfig(0, IntPtr.Zero, 0, IntPtr.Zero, SDC_APPLY | SDC_TOPOLOGY_EXTEND | SDC_ALLOW_CHANGES);
        return rc == 0 ? "ok" : "SetDisplayConfig extend failed: " + rc;
    }

    public static List<RmDisplayDeviceInfo> ListDisplays() {
        var result = new List<RmDisplayDeviceInfo>();
        uint i = 0;
        while (true) {
            var adapter = new DISPLAY_DEVICE();
            adapter.cb = Marshal.SizeOf(adapter);
            if (!EnumDisplayDevices(null, i, ref adapter, 0)) break;
            i++;

            var mon = new DISPLAY_DEVICE();
            mon.cb = Marshal.SizeOf(mon);
            string monitorName = "";
            string monitorId = "";
            if (EnumDisplayDevices(adapter.DeviceName, 0, ref mon, 0)) {
                monitorName = mon.DeviceString;
                monitorId = mon.DeviceID;
            }

            var mode = new DEVMODE();
            mode.dmSize = (short)Marshal.SizeOf(mode);
            int px = 0, py = 0, w = 0, h = 0;
            if (EnumDisplaySettings(adapter.DeviceName, ENUM_CURRENT_SETTINGS, ref mode)) {
                px = mode.dmPositionX;
                py = mode.dmPositionY;
                w = mode.dmPelsWidth;
                h = mode.dmPelsHeight;
            }

            var info = new RmDisplayDeviceInfo();
            info.AdapterName = adapter.DeviceName;
            info.AdapterString = adapter.DeviceString;
            info.MonitorName = monitorName;
            info.MonitorId = monitorId;
            info.AdapterPrimary = (adapter.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0;
            info.AdapterAttached = (adapter.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) != 0;
            info.PositionX = px;
            info.PositionY = py;
            info.Width = w;
            info.Height = h;
            result.Add(info);
        }
        return result;
    }

    public static string SetPrimary(string adapterName) {
        var displays = ListDisplays();
        RmDisplayDeviceInfo target = null;
        foreach (var d in displays) {
            if (string.Equals(d.AdapterName, adapterName, StringComparison.OrdinalIgnoreCase)) {
                target = d;
                break;
            }
        }
        if (target == null) return "target adapter not attached";
        if (target.AdapterPrimary) return "already primary";

        int offsetX = target.PositionX;
        int offsetY = target.PositionY;

        foreach (var d in displays) {
            var mode = new DEVMODE();
            mode.dmSize = (short)Marshal.SizeOf(mode);
            if (!EnumDisplaySettings(d.AdapterName, ENUM_CURRENT_SETTINGS, ref mode)) continue;
            mode.dmFields = 0x00000020; // DM_POSITION
            mode.dmPositionX = d.PositionX - offsetX;
            mode.dmPositionY = d.PositionY - offsetY;
            uint flags = CDS_UPDATEREGISTRY | CDS_NORESET;
            if (d.AdapterName == target.AdapterName) flags |= CDS_SET_PRIMARY;
            int rc = ChangeDisplaySettingsEx(d.AdapterName, ref mode, IntPtr.Zero, flags, IntPtr.Zero);
            if (rc != DISP_CHANGE_SUCCESSFUL) return "ChangeDisplaySettingsEx failed: " + rc;
        }
        int apply = ChangeDisplaySettingsEx(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        if (apply != DISP_CHANGE_SUCCESSFUL) return "apply failed: " + apply;
        return "ok";
    }

    public static string AttachAdapter(string adapterName, int x, int y) {
        var mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(mode);
        if (!EnumDisplaySettings(adapterName, ENUM_CURRENT_SETTINGS, ref mode)) {
            if (!EnumDisplaySettings(adapterName, -2, ref mode)) { // ENUM_REGISTRY_SETTINGS
                if (!EnumDisplaySettings(adapterName, 0, ref mode)) {
                    return "no mode for " + adapterName;
                }
            }
        }
        mode.dmPositionX = x;
        mode.dmPositionY = y;
        mode.dmFields = 0x00000020 | 0x00080000 | 0x00100000 | 0x00040000 | 0x00400000;
        int rc = ChangeDisplaySettingsEx(adapterName, ref mode, IntPtr.Zero, CDS_UPDATEREGISTRY | CDS_NORESET, IntPtr.Zero);
        if (rc != DISP_CHANGE_SUCCESSFUL) return "attach failed: " + rc;
        int apply = ChangeDisplaySettingsEx(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        if (apply != DISP_CHANGE_SUCCESSFUL) return "apply failed: " + apply;
        return "ok";
    }

    public static string SetAdapterMode(string adapterName, int width, int height) {
        var mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(mode);
        if (!EnumDisplaySettings(adapterName, ENUM_CURRENT_SETTINGS, ref mode)) {
            return "no current mode for " + adapterName;
        }
        mode.dmPelsWidth = width;
        mode.dmPelsHeight = height;
        mode.dmFields = 0x00080000 | 0x00100000;
        int rc = ChangeDisplaySettingsEx(adapterName, ref mode, IntPtr.Zero, CDS_UPDATEREGISTRY | CDS_NORESET, IntPtr.Zero);
        if (rc != DISP_CHANGE_SUCCESSFUL) return "mode failed: " + rc;
        int apply = ChangeDisplaySettingsEx(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        if (apply != DISP_CHANGE_SUCCESSFUL) return "apply failed: " + apply;
        return "ok";
    }
}
'@
}

function Get-RmDisplayList {
    Initialize-RmDisplayInterop
    $cfg = Get-RmConfig
    $physId = $cfg.physicalMonitorHardwareId
    $physName = $cfg.physicalMonitorName
    $vddId = $cfg.vddMonitorHardwareId
    [RmDisplayNative]::ListDisplays() | ForEach-Object {
        $id = [string]$_.MonitorId
        $mon = [string]$_.MonitorName
        $adp = [string]$_.AdapterString
        $kind = 'Other'
        if ($id -match 'MTT1337' -or $mon -match 'VDD by MTT' -or $adp -match 'Virtual Display') {
            $kind = 'Vdd'
        }
        elseif (
            $id -match 'SAM7058' -or
            $mon -match 'SAM7058' -or
            ($physName -and $mon -like "*$physName*") -or
            ($physId -and ($id -match [regex]::Escape(($physId -split '\\')[-1])))
        ) {
            $kind = 'Physical'
        }
        [pscustomobject]@{
            Adapter    = $_.AdapterName
            AdapterStr = $_.AdapterString
            Monitor    = $_.MonitorName
            MonitorId  = $_.MonitorId
            Kind       = $kind
            Primary    = $_.AdapterPrimary
            Attached   = $_.AdapterAttached
            X          = $_.PositionX
            Y          = $_.PositionY
            Width      = $_.Width
            Height     = $_.Height
        }
    }
}

function Get-RmPrimaryKind {
    $list = @(Get-RmDisplayList)
    $p = $list | Where-Object Primary | Select-Object -First 1
    if ($p) { return $p.Kind }
    return 'Unknown'
}

function Test-RmPhysicalMonitorActive {
    $cfg = Get-RmConfig
    $fromGdi = @(Get-RmDisplayList | Where-Object { $_.Kind -eq 'Physical' })
    if ($fromGdi.Count -gt 0) { return $true }
    $pnp = @(Get-RmMonitorByHardwareId -HardwareId $cfg.physicalMonitorHardwareId | Where-Object { $_.Status -eq 'OK' })
    return $pnp.Count -gt 0
}

function Set-RmPhysicalPrimary {
    Restore-RmDeskPrimary
}

function Get-RmDeskTarget {
    param(
        [string]$PreferredAdapter,
        $List
    )
    $target = $List | Where-Object { $_.Kind -eq 'Physical' } | Select-Object -First 1
    if (-not $target -and $PreferredAdapter) {
        $target = $List | Where-Object { $_.Adapter -eq $PreferredAdapter -and $_.Kind -ne 'Vdd' } | Select-Object -First 1
    }
    $primary = $List | Where-Object Primary | Select-Object -First 1
    if (-not $target -and $primary -and $primary.Kind -eq 'Vdd') {
        $target = $List | Where-Object { $_.Kind -ne 'Vdd' } | Select-Object -First 1
    }
    [pscustomobject]@{ Target = $target; Primary = $primary; List = $List }
}

function Restore-RmDeskPrimary {
    param([string]$PreferredAdapter)
    Initialize-RmDisplayInterop

    $found = Get-RmDeskTarget -PreferredAdapter $PreferredAdapter -List @(Get-RmDisplayList | Where-Object Attached)
    if (-not $found.Target) {
        $cfg = Get-RmConfig
        $pnpOk = @(Get-RmMonitorByHardwareId -HardwareId $cfg.physicalMonitorHardwareId | Where-Object { $_.Status -eq 'OK' })
        $detached = @(Get-RmDisplayList | Where-Object { -not $_.Attached -and $_.Kind -eq 'Physical' } | Select-Object -First 1)
        if ($pnpOk.Count -gt 0 -or $detached.Count -gt 0) {
            $ext = [RmDisplayNative]::ApplyExtendTopology()
            Write-RmLog ("물리 모니터는 연결되어 있는데 데스크톱에서 빠져 있습니다. 확장으로 복구: {0}" -f $ext)
            foreach ($d in $detached) {
                $att = [RmDisplayNative]::AttachAdapter($d.Adapter, 2560, 0)
                Write-RmLog ("분리된 어댑터 재연결: {0} / {1} ({2})" -f $d.Adapter, $d.Monitor, $att)
            }
            Start-Sleep -Milliseconds 500
            $found = Get-RmDeskTarget -PreferredAdapter $PreferredAdapter -List @(Get-RmDisplayList | Where-Object Attached)
            if (-not $found.Target) {
                $ds = Join-Path $env:SystemRoot 'System32\DisplaySwitch.exe'
                if (Test-Path -LiteralPath $ds) {
                    Start-Process -FilePath $ds -ArgumentList '/extend' -WindowStyle Hidden -Wait | Out-Null
                    Write-RmLog 'DisplaySwitch /extend 로 다시 시도했습니다.'
                    Start-Sleep -Milliseconds 800
                    $found = Get-RmDeskTarget -PreferredAdapter $PreferredAdapter -List @(Get-RmDisplayList | Where-Object Attached)
                }
            }
        }
    }

    $list = @($found.List)
    $target = $found.Target
    $primary = $found.Primary
    if ($list.Count -eq 0) { return 'no-displays' }
    if (-not $target) {
        if ($primary -and $primary.Kind -ne 'Vdd') { return 'already-primary' }
        return 'vdd-only'
    }

    $rc = 'already-primary'
    if (-not $target.Primary) {
        $rc = [RmDisplayNative]::SetPrimary($target.Adapter)
        Write-RmLog ("책상 모니터를 메인으로 유지: {0} / {1} ({2})" -f $target.Adapter, $target.Monitor, $rc)
    }
    $vdd = Get-RmDisplayList | Where-Object { $_.Kind -eq 'Vdd' -and $_.Attached } | Select-Object -First 1
    if ($vdd -and $vdd.Width -gt 0 -and $vdd.Width -lt 1280) {
        $vr = [RmDisplayNative]::SetAdapterMode($vdd.Adapter, 2560, 1440)
        Write-RmLog ("VDD 해상도 복구 2560x1440: {0}" -f $vr)
    }
    return $rc
}

function Reset-RmPhysicalMonitorOutput {
    $cfg = Get-RmConfig
    $mons = @(Get-RmMonitorByHardwareId -HardwareId $cfg.physicalMonitorHardwareId | Where-Object { $_.Status -eq 'OK' })
    if ($mons.Count -eq 0) { return 'no-physical' }

    foreach ($m in $mons) {
        try {
            Write-RmLog ("물리 모니터 출력을 잠시 끊습니다: {0}" -f $m.FriendlyName)
            Disable-PnpDevice -InstanceId $m.InstanceId -Confirm:$false
        }
        catch {
            Write-RmLog ("물리 모니터 끄기 실패: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
    Start-Sleep -Seconds 2
    foreach ($m in $mons) {
        try {
            Enable-PnpDevice -InstanceId $m.InstanceId -Confirm:$false
        }
        catch {
            Write-RmLog ("물리 모니터 켜기 실패: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
    Start-Sleep -Seconds 2
    return 'ok'
}

function Complete-RmDeskAfterOff {
    [void](Wait-RmVddDisabled -TimeoutSeconds 8)
    Write-RmLog 'VDD를 끈 뒤 물리 모니터가 붙을 시간을 둡니다.'
    Start-Sleep -Seconds 2

    $reset = Reset-RmPhysicalMonitorOutput
    if ($reset -eq 'no-physical') {
        Write-RmLog '물리 모니터가 아직 감지되지 않습니다. 데스크톱 확장만 시도합니다.'
    }

    for ($i = 0; $i -lt 8; $i++) {
        $rc = Restore-RmDeskPrimary
        $p = Get-RmDisplayList |
            Where-Object { $_.Kind -eq 'Physical' -and $_.Attached -and $_.Width -ge 1280 } |
            Select-Object -First 1
        if ($p) {
            Write-RmLog ("물리 모니터 화면: {0} {1}x{2} ({3})" -f $p.Adapter, $p.Width, $p.Height, $rc)
            return
        }
        Start-Sleep -Milliseconds 750
    }
    Write-RmLog '물리 모니터 화면이 아직 안 붙었습니다. 모니터 전원을 한 번 껐다 켜 보세요.' 'WARN'
}
