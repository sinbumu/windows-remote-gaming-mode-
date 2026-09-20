namespace RemoteMode.Gui;

public sealed class MainForm : Form
{
    private readonly Label _mode = new();
    private readonly Label _sub = new();
    private readonly DataGridView _grid = new();
    private readonly Button _on = new();
    private readonly Button _off = new();
    private readonly Button _refresh = new();
    private readonly Button _install = new();
    private readonly Label _busy = new();
    private readonly TextBox _log = new();
    private readonly FileSystemWatcher _watcher = new();
    private long _logOffset;
    private bool _working;

    public MainForm()
    {
        Text = "Remote Mode";
        Font = new Font("Segoe UI", 9.5f);
        MinimumSize = new Size(860, 640);
        Size = new Size(980, 740);
        StartPosition = FormStartPosition.CenterScreen;

        _mode.AutoSize = true;
        _mode.Font = new Font("Segoe UI", 28f, FontStyle.Bold);
        _mode.Location = new Point(20, 12);
        _mode.Text = "...";

        _sub.AutoSize = false;
        _sub.Location = new Point(24, 64);
        _sub.Size = new Size(920, 24);
        _sub.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _sub.ForeColor = Color.DimGray;
        _sub.Text = "실상태를 읽는 중";

        _grid.Location = new Point(20, 96);
        _grid.Size = new Size(920, 210);
        _grid.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _grid.ReadOnly = true;
        _grid.AllowUserToAddRows = false;
        _grid.AllowUserToDeleteRows = false;
        _grid.AllowUserToResizeRows = false;
        _grid.RowHeadersVisible = false;
        _grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        _grid.MultiSelect = false;
        _grid.BackgroundColor = Color.White;
        _grid.BorderStyle = BorderStyle.FixedSingle;
        _grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        _grid.ColumnCount = 3;
        _grid.Columns[0].Name = "항목";
        _grid.Columns[1].Name = "실제 값";
        _grid.Columns[2].Name = "Remote ON 기대";
        _grid.Columns[0].FillWeight = 28;
        _grid.Columns[1].FillWeight = 36;
        _grid.Columns[2].FillWeight = 36;

        _on.Text = "Remote ON";
        _on.Size = new Size(140, 36);
        _on.Location = new Point(20, 318);
        _off.Text = "Remote OFF";
        _off.Size = new Size(140, 36);
        _off.Location = new Point(170, 318);
        _refresh.Text = "다시 확인";
        _refresh.Size = new Size(140, 36);
        _refresh.Location = new Point(320, 318);
        _install.Text = "설치";
        _install.Size = new Size(100, 36);
        _install.Location = new Point(470, 318);
        _busy.AutoSize = true;
        _busy.Location = new Point(590, 326);
        _busy.ForeColor = Color.DimGray;

        var logLabel = new Label { Text = "로그", Location = new Point(20, 366), AutoSize = true };
        _log.Multiline = true;
        _log.ScrollBars = ScrollBars.Both;
        _log.ReadOnly = true;
        _log.WordWrap = false;
        _log.Font = new Font("Consolas", 9f);
        _log.Location = new Point(20, 388);
        _log.Size = new Size(920, 280);
        _log.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _log.BackColor = Color.FromArgb(30, 30, 30);
        _log.ForeColor = Color.FromArgb(220, 220, 220);

        Controls.AddRange(new Control[] { _mode, _sub, _grid, _on, _off, _refresh, _install, _busy, logLabel, _log });

        _on.Click += async (_, _) => await RunActionAsync("on");
        _off.Click += async (_, _) => await RunActionAsync("off");
        _refresh.Click += async (_, _) => await RefreshAsync();
        _install.Click += async (_, _) => await RunActionAsync("install");
        Load += async (_, _) =>
        {
            LoadLogTail();
            StartLogWatch();
            AppendLog($"----- {DateTime.Now:yyyy-MM-dd HH:mm:ss} GUI 시작 -----");
            await RefreshAsync();
        };
        FormClosed += (_, _) => _watcher.Dispose();
    }

    private void SetBusy(bool busy, string text = "")
    {
        _working = busy;
        _on.Enabled = !busy;
        _off.Enabled = !busy;
        _refresh.Enabled = !busy;
        _install.Enabled = !busy;
        _busy.Text = text;
    }

    private void AppendLog(string line)
    {
        if (IsDisposed) return;
        if (InvokeRequired)
        {
            BeginInvoke(() => AppendLog(line));
            return;
        }
        _log.AppendText(line + Environment.NewLine);
    }

    private void LoadLogTail()
    {
        try
        {
            if (!File.Exists(Engine.LogPath)) return;
            var lines = File.ReadAllLines(Engine.LogPath);
            var take = lines.Skip(Math.Max(0, lines.Length - 200));
            foreach (var line in take) _log.AppendText(line + Environment.NewLine);
            _logOffset = new FileInfo(Engine.LogPath).Length;
        }
        catch (Exception ex)
        {
            AppendLog("[WARN] 로그 파일을 읽지 못했습니다: " + ex.Message);
        }
    }

    private void StartLogWatch()
    {
        try
        {
            var dir = Path.GetDirectoryName(Engine.LogPath)!;
            Directory.CreateDirectory(dir);
            _watcher.Path = dir;
            _watcher.Filter = Path.GetFileName(Engine.LogPath);
            _watcher.NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size;
            _watcher.Changed += (_, _) => DrainLogFile();
            _watcher.EnableRaisingEvents = true;
        }
        catch
        {
            // log file may not exist yet
        }
    }

    private void DrainLogFile()
    {
        try
        {
            if (!File.Exists(Engine.LogPath)) return;
            using var fs = new FileStream(Engine.LogPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            if (fs.Length < _logOffset) _logOffset = 0;
            fs.Seek(_logOffset, SeekOrigin.Begin);
            using var reader = new StreamReader(fs);
            var chunk = reader.ReadToEnd();
            _logOffset = fs.Position;
            if (string.IsNullOrEmpty(chunk)) return;
            foreach (var line in chunk.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
            {
                if (line.Length > 0) AppendLog(line);
            }
        }
        catch
        {
            // ignore torn reads
        }
    }

    private async Task RefreshAsync()
    {
        if (_working) return;
        SetBusy(true, "상태 확인 중...");
        try
        {
            AppendLog("GUI: 실제 장치/서비스 상태를 다시 조회합니다.");
            var snap = await Task.Run(() => Engine.ReadStatus());
            ApplySnapshot(snap);
            AppendLog("GUI: 실상태 재확인 완료.");
        }
        catch (Exception ex)
        {
            AppendLog("[ERROR] " + ex.Message);
            _mode.Text = "오류";
            _mode.ForeColor = Color.Firebrick;
            _sub.Text = ex.Message;
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void ApplySnapshot(LiveSnapshot snap)
    {
        switch (snap.Mode)
        {
            case "ON":
                _mode.Text = "ON";
                _mode.ForeColor = Color.ForestGreen;
                _sub.Text = $"기록 desired=on 과 VDD/Sunshine 실상태가 일치합니다.  {snap.CheckedAt}";
                break;
            case "OFF":
                _mode.Text = "OFF";
                _mode.ForeColor = Color.DimGray;
                _sub.Text = $"기록 desired=off 과 VDD/Sunshine 실상태가 일치합니다.  {snap.CheckedAt}";
                break;
            default:
                _mode.Text = "불일치";
                _mode.ForeColor = Color.DarkGoldenrod;
                var why = snap.Issues.Count > 0 ? string.Join(", ", snap.Issues) : "부분 적용";
                _sub.Text = $"창을 다시 열 때마다 실상태를 읽습니다. 지금: {why}  ({snap.CheckedAt})";
                break;
        }

        _grid.Rows.Clear();
        _grid.Rows.Add("기록 desired", snap.Desired, "on 이면 Remote 유지");
        _grid.Rows.Add("Tailscale", $"{snap.Tailscale} / {snap.TailscaleStart}", "Running (상시, 토글 아님)");
        _grid.Rows.Add("VDD", $"{snap.VddEnabled} ({snap.VddStatus})", "True (Enabled)");
        _grid.Rows.Add("Sunshine", $"{snap.Sunshine} / {snap.SunshineStart}", "Running / Automatic");
        _grid.Rows.Add("자동 로그인", snap.AutologonArmed.ToString(), "True");
        _grid.Rows.Add("메인 디스플레이", snap.PrimaryKind, "Physical (모니터 켜져 있을 때)");
        _grid.Rows.Add("물리 모니터", snap.PhysicalActive.ToString(), "True");
        _grid.Rows.Add("Watchdog", snap.Watchdog.ToString(), "True");
        if (!string.IsNullOrWhiteSpace(snap.PendingReboot))
            _grid.Rows.Add("재시작 대기", snap.PendingReboot, "없음");
    }

    private async Task RunActionAsync(string action)
    {
        if (_working) return;
        SetBusy(true, action + " 실행 중...");
        try
        {
            LiveSnapshot? before = null;
            try { before = await Task.Run(() => Engine.ReadStatus()); }
            catch { /* first-run */ }

            if (action is "on" or "install")
            {
                var needPw = before == null || !before.AutologonSecret;
                if (needPw)
                {
                    using var dlg = new PasswordForm();
                    if (dlg.ShowDialog(this) != DialogResult.OK || string.IsNullOrWhiteSpace(dlg.Password))
                    {
                        if (action == "on")
                            throw new InvalidOperationException("자동 로그인 비밀번호가 필요합니다.");
                    }
                    else
                    {
                        var pw = dlg.Password;
                        await Task.Run(() =>
                        {
                            var r = Engine.Run("set-password", extraArgs: "-PasswordFromStdin", stdin: pw, onLine: AppendLog);
                            if (r.ExitCode != 0)
                                throw new InvalidOperationException(r.Error.Length > 0 ? r.Error : r.Output);
                        });
                    }
                }
            }

            await Task.Run(() =>
            {
                var r = Engine.Run(action, onLine: AppendLog);
                if (r.ExitCode != 0)
                    throw new InvalidOperationException(string.IsNullOrWhiteSpace(r.Error) ? r.Output : r.Error);
            });

            DrainLogFile();
            var snap = await Task.Run(() => Engine.ReadStatus());
            ApplySnapshot(snap);
            AppendLog("GUI: 조작 후 실상태 재확인 완료.");
        }
        catch (Exception ex)
        {
            AppendLog("[ERROR] " + ex.Message);
            MessageBox.Show(this, ex.Message, "Remote Mode", MessageBoxButtons.OK, MessageBoxIcon.Error);
            try
            {
                var snap = await Task.Run(() => Engine.ReadStatus());
                ApplySnapshot(snap);
            }
            catch { /* ignore */ }
        }
        finally
        {
            SetBusy(false);
        }
    }
}
