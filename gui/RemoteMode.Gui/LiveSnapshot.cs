using System.Text.Json.Serialization;

namespace RemoteMode.Gui;

public sealed class LiveSnapshot
{
    [JsonPropertyName("Mode")] public string Mode { get; set; } = "PARTIAL";
    [JsonPropertyName("Desired")] public string Desired { get; set; } = "off";
    [JsonPropertyName("PayloadOn")] public bool PayloadOn { get; set; }
    [JsonPropertyName("Tailscale")] public string Tailscale { get; set; } = "";
    [JsonPropertyName("TailscaleStart")] public string TailscaleStart { get; set; } = "";
    [JsonPropertyName("VddEnabled")] public bool VddEnabled { get; set; }
    [JsonPropertyName("VddStatus")] public string VddStatus { get; set; } = "";
    [JsonPropertyName("Sunshine")] public string Sunshine { get; set; } = "";
    [JsonPropertyName("SunshineStart")] public string SunshineStart { get; set; } = "";
    [JsonPropertyName("AutologonArmed")] public bool AutologonArmed { get; set; }
    [JsonPropertyName("AutologonSecret")] public bool AutologonSecret { get; set; }
    [JsonPropertyName("PrimaryKind")] public string PrimaryKind { get; set; } = "";
    [JsonPropertyName("PhysicalActive")] public bool PhysicalActive { get; set; }
    [JsonPropertyName("Watchdog")] public bool Watchdog { get; set; }
    [JsonPropertyName("PendingReboot")] public string PendingReboot { get; set; } = "";
    [JsonPropertyName("LastOn")] public string LastOn { get; set; } = "";
    [JsonPropertyName("LastOff")] public string LastOff { get; set; } = "";
    [JsonPropertyName("Issues")] public List<string> Issues { get; set; } = new();
    [JsonPropertyName("PhysicalMonitor")] public string PhysicalMonitor { get; set; } = "";
    [JsonPropertyName("VddInstanceId")] public string VddInstanceId { get; set; } = "";
    [JsonPropertyName("CheckedAt")] public string CheckedAt { get; set; } = "";
}
