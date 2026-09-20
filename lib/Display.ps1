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

    public static List<RmDisplayDeviceInfo> ListDisplays() {
        var result = new List<RmDisplayDeviceInfo>();
        uint i = 0;
        while (true) {
            var adapter = new DISPLAY_DEVICE();
            adapter.cb = Marshal.SizeOf(adapter);
            if (!EnumDisplayDevices(null, i, ref adapter, 0)) break;
            i++;
            if ((adapter.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) == 0) continue;

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
            info.AdapterAttached = true;
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
}
'@
}

function Get-RmDisplayList {
    Initialize-RmDisplayInterop
    $cfg = Get-RmConfig
    $phys = $cfg.physicalMonitorHardwareId
    $vdd = $cfg.vddMonitorHardwareId
    [RmDisplayNative]::ListDisplays() | ForEach-Object {
        $kind = 'Other'
        if ($_.MonitorId -like "*$($phys.Replace('\','*'))*" -or $_.MonitorId -match 'SAM7058') { $kind = 'Physical' }
        elseif ($_.MonitorId -like "*$($vdd.Replace('\','*'))*" -or $_.MonitorId -match 'MTT1337') { $kind = 'Vdd' }
        [pscustomobject]@{
            Adapter    = $_.AdapterName
            AdapterStr = $_.AdapterString
            Monitor    = $_.MonitorName
            MonitorId  = $_.MonitorId
            Kind       = $kind
            Primary    = $_.AdapterPrimary
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
    Initialize-RmDisplayInterop
    $list = @(Get-RmDisplayList)
    $phys = $list | Where-Object { $_.Kind -eq 'Physical' } | Select-Object -First 1
    if (-not $phys) {
        return 'physical-not-present'
    }
    if ($phys.Primary) {
        return 'already-primary'
    }
    $rc = [RmDisplayNative]::SetPrimary($phys.Adapter)
    Write-RmLog ("물리 모니터를 메인으로 전환: {0} ({1})" -f $phys.Monitor, $rc)
    return $rc
}
