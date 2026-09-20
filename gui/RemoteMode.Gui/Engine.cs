using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace RemoteMode.Gui;

public static class Engine
{
    public static readonly string LogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "RemoteMode",
        "remote-mode.log");

    public static string FindScript()
    {
        var names = new List<string>();
        void Add(string? p)
        {
            if (string.IsNullOrWhiteSpace(p)) return;
            var full = Path.GetFullPath(p);
            if (!names.Contains(full, StringComparer.OrdinalIgnoreCase))
                names.Add(full);
        }

        Add(Path.Combine(AppContext.BaseDirectory, "remote-mode.ps1"));
        Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "RemoteMode", "remote-mode.ps1"));
        Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RemoteMode", "remote-mode.ps1"));
        Add(Path.Combine(Directory.GetCurrentDirectory(), "remote-mode.ps1"));

        var github = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "Documents", "GitHub");
        if (Directory.Exists(github))
        {
            foreach (var d in Directory.GetDirectories(github))
                Add(Path.Combine(d, "remote-mode.ps1"));
        }

        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        for (var i = 0; i < 8 && dir != null; i++, dir = dir.Parent)
            Add(Path.Combine(dir.FullName, "remote-mode.ps1"));

        var existing = names.Where(File.Exists).ToList();
        if (existing.Count == 0)
            throw new FileNotFoundException("remote-mode.ps1을 찾을 수 없습니다.");

        // ProgramData 복사가 관리자 소유라 저장소 수정이 안 들어갈 수 있다. 더 새 스크립트를 쓴다.
        return existing
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .First();
    }

    public static LiveSnapshot ReadStatus()
    {
        var result = Run("status", extraArgs: "-Json", timeoutMs: 60_000);
        if (result.ExitCode != 0)
            throw new InvalidOperationException("상태 조회 실패. 아래 로그를 확인하세요.");

        var json = ExtractJson(result.Output);
        var snap = JsonSerializer.Deserialize<LiveSnapshot>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        });
        return snap ?? throw new InvalidOperationException("상태 JSON을 해석하지 못했습니다.");
    }

    public static EngineResult Run(
        string action,
        string extraArgs = "",
        string? stdin = null,
        int timeoutMs = 180_000,
        Action<string>? onLine = null)
    {
        var script = FindScript();
        var psi = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\" {action} {extraArgs}".Trim(),
            WorkingDirectory = Path.GetDirectoryName(script)!,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = stdin != null,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var output = new StringBuilder();
        var error = new StringBuilder();

        proc.OutputDataReceived += (_, e) =>
        {
            if (e.Data == null) return;
            output.AppendLine(e.Data);
            onLine?.Invoke(e.Data);
        };
        proc.ErrorDataReceived += (_, e) =>
        {
            if (e.Data == null) return;
            error.AppendLine(e.Data);
            onLine?.Invoke(e.Data);
        };

        proc.Start();
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();
        if (stdin != null)
        {
            proc.StandardInput.WriteLine(stdin);
            proc.StandardInput.Close();
        }

        if (!proc.WaitForExit(timeoutMs))
        {
            try { proc.Kill(entireProcessTree: true); } catch { /* ignore */ }
            throw new TimeoutException($"{action} 제한 시간을 초과했습니다.");
        }

        proc.WaitForExit();
        return new EngineResult(proc.ExitCode, output.ToString(), error.ToString());
    }

    private static string ExtractJson(string raw)
    {
        foreach (var line in raw.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries).Reverse())
        {
            var t = line.Trim();
            if (t.StartsWith("{", StringComparison.Ordinal) && t.EndsWith("}", StringComparison.Ordinal))
                return t;
        }
        throw new InvalidOperationException("상태 JSON을 읽지 못했습니다. 아래 로그를 확인하세요.");
    }
}

public readonly record struct EngineResult(int ExitCode, string Output, string Error);
