namespace RemoteMode.Gui;

public sealed class PasswordForm : Form
{
    private readonly TextBox _box;

    public PasswordForm()
    {
        Text = "자동 로그인 비밀번호";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MinimizeBox = false;
        MaximizeBox = false;
        ClientSize = new Size(420, 140);
        Font = new Font("Segoe UI", 9.5f);

        var lbl = new Label
        {
            AutoSize = true,
            Location = new Point(16, 16),
            MaximumSize = new Size(390, 0),
            Text = "Remote ON 재부팅 복구에 씁니다. 이 PC Windows 사용자 비밀번호."
        };
        _box = new TextBox
        {
            UseSystemPasswordChar = true,
            Location = new Point(16, 52),
            Width = 388
        };
        var ok = new Button { Text = "저장", DialogResult = DialogResult.OK, Location = new Point(228, 96) };
        var cancel = new Button { Text = "취소", DialogResult = DialogResult.Cancel, Location = new Point(314, 96) };
        AcceptButton = ok;
        CancelButton = cancel;
        Controls.AddRange(new Control[] { lbl, _box, ok, cancel });
    }

    public string Password { get; private set; } = "";

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (DialogResult == DialogResult.OK)
            Password = _box.Text;
        _box.Text = "";
        base.OnFormClosing(e);
    }
}
