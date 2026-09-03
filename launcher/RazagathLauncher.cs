// RazagathWoW Launcher
// -----------------------------------------------------------------------------
// A tiny self-updating launcher for the RazagathWoW (AzerothCore / ChromieCraft
// 3.3.5a) client. Lives in the client root next to the patched game exe.
//
// On start it pulls manifest.json from GitHub, checks the SHA-256 of every
// managed file (the custom MPQ, mandatory addon, optionally the game exe),
// downloads whatever drifted, then launches the game. A Changelog tab renders
// the human-readable patch notes carried in the same manifest.
//
// Targets .NET Framework 4.8 (ships with every Win10 1903+/Win11) so the built
// exe needs no runtime install. Compile with build.ps1 (Roslyn csc).
// -----------------------------------------------------------------------------
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("RazagathWoW Launcher")]
[assembly: AssemblyProduct("RazagathWoW")]
[assembly: AssemblyCompany("Razagath")]

namespace RazagathWoW
{
    internal static class Program
    {
        // Fallback manifest URL, used when launcher.cfg is absent. Overwritten
        // by tools\build-release.ps1 at packaging time with the real repo slug.
        public const string DefaultManifestUrl =
            "https://raw.githubusercontent.com/RAZAGATH_OWNER/RazagathWoW/main/manifest.json";

        [STAThread]
        private static void Main(string[] args)
        {
            if (args != null && args.Length > 0 &&
                (args[0] == "--selftest" || args[0] == "/selftest"))
            {
                Environment.Exit(SelfTest.Run(args.Length > 1 ? args[1] : null));
                return;
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            ServicePointManager.SecurityProtocol =
                SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;
            ServicePointManager.DefaultConnectionLimit = 8;
            Application.Run(new MainForm());
        }
    }

    // ---- headless self-test: `RazagathWoW.exe --selftest <manifestUrl>` ------
    internal static class SelfTest
    {
        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        private static extern bool AttachConsole(int pid);

        private static StreamWriter _log;
        private static void W(string s) { Console.WriteLine(s); if (_log != null) { _log.WriteLine(s); _log.Flush(); } }

        public static int Run(string url)
        {
            AttachConsole(-1); // ATTACH_PARENT_PROCESS
            try { _log = new StreamWriter(Path.Combine(Path.GetTempPath(), "razagath_selftest.log"), false); } catch { }
            try
            {
                ServicePointManager.SecurityProtocol =
                    SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;
                if (string.IsNullOrEmpty(url)) url = Program.DefaultManifestUrl;
                W("manifest: " + url);
                string json;
                using (var wc = new WebClient())
                {
                    wc.Headers[HttpRequestHeader.UserAgent] = "RazagathLauncher-selftest";
                    json = wc.DownloadString(url);
                }
                var m = new JavaScriptSerializer { MaxJsonLength = 8 * 1024 * 1024 }.Deserialize<Manifest>(json);
                W("clientVersion : " + m.clientVersion);
                W("gameExe       : " + m.gameExe);
                W("realmlist     : " + m.realmlist);
                W("launcher      : " + (m.launcher != null ? m.launcher.version : "(none)"));
                W("files         : " + (m.files != null ? m.files.Count : 0));
                foreach (var f in m.files ?? new List<FileEntry>())
                    W("   - " + f.path + "  sha256=" + Trunc(f.sha256) + "  size=" + f.size + "  url=" + (string.IsNullOrEmpty(f.url) ? "(unset)" : "ok"));
                W("changelog     : " + (m.changelog != null ? m.changelog.Count : 0) + " entries");
                foreach (var c in m.changelog ?? new List<ChangeEntry>())
                    W("   * " + c.version + "  \"" + c.title + "\"  (" + (c.notes != null ? c.notes.Count : 0) + " notes)");
                W("OK");
                return 0;
            }
            catch (Exception ex)
            {
                W("FAIL: " + ex.Message);
                return 1;
            }
        }
        private static string Trunc(string s) { return string.IsNullOrEmpty(s) ? "(unset)" : (s.Length > 12 ? s.Substring(0, 12) + "..." : s); }
    }

    // ---- manifest model (JavaScriptSerializer maps JSON onto these) ----------
    public sealed class Manifest
    {
        public int schema { get; set; }
        public string clientVersion { get; set; }
        public string gameExe { get; set; }
        public string realmlist { get; set; }
        public LauncherInfo launcher { get; set; }
        public List<FileEntry> files { get; set; }
        public List<ChangeEntry> changelog { get; set; }
    }
    public sealed class LauncherInfo
    {
        public string version { get; set; }
        public string url { get; set; }
        public string sha256 { get; set; }
    }
    public sealed class FileEntry
    {
        public string path { get; set; }   // client-relative, forward slashes
        public string sha256 { get; set; }
        public long size { get; set; }
        public string url { get; set; }
        public bool optional { get; set; } // skip if the local file is absent
    }
    public sealed class ChangeEntry
    {
        public string version { get; set; }
        public string date { get; set; }
        public string title { get; set; }
        public List<string> notes { get; set; }
    }

    internal sealed class MainForm : Form
    {
        private readonly string _root;
        private readonly string _cfgPath;
        private string _manifestUrl;

        private Manifest _manifest;
        private readonly Button _playButton = new Button();
        private readonly Label _statusLabel = new Label();
        private readonly ProgressBar _progress = new ProgressBar();
        private readonly TabControl _tabs = new TabControl();
        private readonly RichTextBox _news = new RichTextBox();
        private readonly RichTextBox _changelog = new RichTextBox();
        private TextBox _realmBox;
        private CheckBox _windowedBox;
        private bool _busy;

        public MainForm()
        {
            _root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
            _cfgPath = Path.Combine(_root, "launcher.cfg");
            _manifestUrl = ReadConfiguredManifestUrl();

            Text = "RazagathWoW";
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            ClientSize = new Size(720, 480);
            BackColor = Color.FromArgb(24, 20, 32);
            Font = new Font("Segoe UI", 9f);
            try { this.Icon = System.Drawing.Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location); } catch { }

            BuildUi();
            Shown += async (s, e) => await RefreshAsync();
        }

        // ---------------------------------------------------------------- UI --
        private void BuildUi()
        {
            var header = new Panel { Dock = DockStyle.Top, Height = 92, BackColor = Color.FromArgb(18, 15, 24) };
            var title = new Label
            {
                Text = "RAZAGATH  WoW",
                ForeColor = Color.FromArgb(196, 150, 255),
                Font = new Font("Segoe UI", 20f, FontStyle.Bold),
                AutoSize = true,
                Location = new Point(24, 20)
            };
            var sub = new Label
            {
                Text = "Wrath of the Lich King  -  3.3.5a",
                ForeColor = Color.FromArgb(120, 110, 140),
                AutoSize = true,
                Location = new Point(27, 60)
            };
            header.Controls.Add(title);
            header.Controls.Add(sub);

            _tabs.Dock = DockStyle.Fill;
            _tabs.Padding = new Point(14, 6);

            // ---- Play tab ----
            var playTab = new TabPage("  Play  ") { BackColor = BackColor };
            _news.Dock = DockStyle.Fill;
            _news.BorderStyle = BorderStyle.None;
            _news.BackColor = Color.FromArgb(30, 25, 40);
            _news.ForeColor = Color.Gainsboro;
            _news.ReadOnly = true;
            _news.Margin = new Padding(12);
            var newsHost = new Panel { Dock = DockStyle.Fill, Padding = new Padding(12, 12, 12, 12), BackColor = BackColor };
            newsHost.Controls.Add(_news);
            playTab.Controls.Add(newsHost);

            // ---- Changelog tab ----
            var clTab = new TabPage("  Changelog  ") { BackColor = BackColor };
            _changelog.Dock = DockStyle.Fill;
            _changelog.BorderStyle = BorderStyle.None;
            _changelog.BackColor = Color.FromArgb(30, 25, 40);
            _changelog.ForeColor = Color.Gainsboro;
            _changelog.ReadOnly = true;
            var clHost = new Panel { Dock = DockStyle.Fill, Padding = new Padding(12), BackColor = BackColor };
            clHost.Controls.Add(_changelog);
            clTab.Controls.Add(clHost);

            // ---- Settings tab ----
            var setTab = new TabPage("  Settings  ") { BackColor = BackColor };
            setTab.Controls.Add(BuildSettingsPanel());

            _tabs.TabPages.Add(playTab);
            _tabs.TabPages.Add(clTab);
            _tabs.TabPages.Add(setTab);

            var footer = new Panel { Dock = DockStyle.Bottom, Height = 84, BackColor = Color.FromArgb(18, 15, 24) };
            _statusLabel.Text = "Starting...";
            _statusLabel.ForeColor = Color.Gainsboro;
            _statusLabel.AutoSize = false;
            _statusLabel.Location = new Point(24, 12);
            _statusLabel.Size = new Size(430, 20);
            _progress.Location = new Point(24, 38);
            _progress.Size = new Size(430, 18);
            _progress.Style = ProgressBarStyle.Continuous;

            _playButton.Text = "PLAY";
            _playButton.Size = new Size(210, 56);
            _playButton.Location = new Point(480, 14);
            _playButton.FlatStyle = FlatStyle.Flat;
            _playButton.FlatAppearance.BorderSize = 0;
            _playButton.BackColor = Color.FromArgb(96, 40, 168);
            _playButton.ForeColor = Color.White;
            _playButton.Font = new Font("Segoe UI", 13f, FontStyle.Bold);
            _playButton.Enabled = false;
            _playButton.Click += async (s, e) => await OnPlayClicked();

            footer.Controls.Add(_statusLabel);
            footer.Controls.Add(_progress);
            footer.Controls.Add(_playButton);

            Controls.Add(_tabs);
            Controls.Add(footer);
            Controls.Add(header);
        }

        private Control BuildSettingsPanel()
        {
            var p = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                Padding = new Padding(24, 20, 24, 20),
                ColumnCount = 2,
                BackColor = BackColor
            };
            p.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
            p.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

            Label L(string t) => new Label { Text = t, ForeColor = Color.Gainsboro, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 8, 0, 8) };

            _realmBox = new TextBox { Width = 460, Anchor = AnchorStyles.Left, Margin = new Padding(0, 5, 0, 5) };
            _realmBox.Text = ReadRealmlist();

            var saveRealm = new Button { Text = "Save realmlist", AutoSize = true, Anchor = AnchorStyles.Left };
            saveRealm.Click += (s, e) => { WriteRealmlist(_realmBox.Text.Trim()); SetStatus("realmlist.wtf saved."); };

            _windowedBox = new CheckBox { Text = "Launch in windowed mode", ForeColor = Color.Gainsboro, AutoSize = true, Anchor = AnchorStyles.Left, Checked = ReadWindowed() };
            _windowedBox.CheckedChanged += (s, e) => WriteWindowed(_windowedBox.Checked);

            var verify = new Button { Text = "Verify / repair files", AutoSize = true, Anchor = AnchorStyles.Left };
            verify.Click += async (s, e) => await RefreshAsync(force: true);

            var clearCache = new Button { Text = "Clear cache", AutoSize = true, Anchor = AnchorStyles.Left };
            clearCache.Click += (s, e) => { ClearCache(); SetStatus("Cache folder cleared."); };

            var openFolder = new Button { Text = "Open game folder", AutoSize = true, Anchor = AnchorStyles.Left };
            openFolder.Click += (s, e) => { try { Process.Start("explorer.exe", _root); } catch { } };

            var ver = new Label
            {
                Text = "Launcher " + LauncherVersion() + "   -   client " + (_manifest != null ? _manifest.clientVersion : "?"),
                ForeColor = Color.FromArgb(120, 110, 140),
                AutoSize = true,
                Anchor = AnchorStyles.Left,
                Margin = new Padding(0, 16, 0, 0)
            };
            _versionLabel = ver;

            p.Controls.Add(L("Realm"), 0, 0); p.Controls.Add(_realmBox, 1, 0);
            p.Controls.Add(new Label(), 0, 1); p.Controls.Add(saveRealm, 1, 1);
            p.Controls.Add(new Label(), 0, 2); p.Controls.Add(_windowedBox, 1, 2);
            p.Controls.Add(L("Maintenance"), 0, 3);
            var row = new FlowLayoutPanel { AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0) };
            row.Controls.Add(verify); row.Controls.Add(clearCache); row.Controls.Add(openFolder);
            p.Controls.Add(row, 1, 3);
            p.Controls.Add(ver, 1, 4);
            return p;
        }
        private Label _versionLabel;

        // ----------------------------------------------------------- update --
        private async Task RefreshAsync(bool force = false)
        {
            if (_busy) return;
            _busy = true;
            _playButton.Enabled = false;
            try
            {
                SetStatus("Checking for updates...");
                SetProgress(0);

                _manifest = await Task.Run(() => FetchManifest(_manifestUrl));
                RenderChangelog(_manifest);
                RenderNews(_manifest);
                if (_versionLabel != null)
                    _versionLabel.Text = "Launcher " + LauncherVersion() + "   -   client " + _manifest.clientVersion;

                // launcher self-update first
                if (_manifest.launcher != null && IsNewer(_manifest.launcher.version, LauncherVersion())
                    && !string.IsNullOrEmpty(_manifest.launcher.url))
                {
                    SetStatus("Updating launcher...");
                    await SelfUpdate(_manifest.launcher);
                    return; // process will restart
                }

                var todo = new List<FileEntry>();
                foreach (var f in _manifest.files ?? new List<FileEntry>())
                {
                    var local = Path.Combine(_root, f.path.Replace('/', '\\'));
                    if (f.optional && !File.Exists(local)) continue;
                    if (force || !File.Exists(local) || !HashEquals(local, f.sha256))
                        todo.Add(f);
                }

                if (todo.Count == 0)
                {
                    SetStatus("Up to date  -  client " + _manifest.clientVersion);
                    SetProgress(100);
                }
                else
                {
                    long total = todo.Sum(t => Math.Max(t.size, 1));
                    long done = 0;
                    for (int i = 0; i < todo.Count; i++)
                    {
                        var f = todo[i];
                        SetStatus(string.Format("Downloading {0}  ({1}/{2})", Path.GetFileName(f.path), i + 1, todo.Count));
                        var dest = Path.Combine(_root, f.path.Replace('/', '\\'));
                        Directory.CreateDirectory(Path.GetDirectoryName(dest));
                        long baseDone = done;
                        await Task.Run(() => Download(f.url, dest, (cur, len) =>
                        {
                            long overall = baseDone + cur;
                            SetProgress((int)(overall * 100 / Math.Max(total, 1)));
                        }));
                        if (!string.IsNullOrEmpty(f.sha256) && !HashEquals(dest, f.sha256))
                            throw new Exception("Checksum mismatch after downloading " + f.path);
                        done += Math.Max(f.size, 1);
                    }
                    SetStatus("Update complete  -  client " + _manifest.clientVersion);
                    SetProgress(100);
                }

                if (!string.IsNullOrEmpty(_manifest.realmlist))
                    EnsureRealmlist(_manifest.realmlist);

                _playButton.Enabled = true;
            }
            catch (Exception ex)
            {
                SetStatus("Offline / update failed: " + ex.Message);
                // still allow play so a network blip never blocks login
                _playButton.Enabled = File.Exists(GameExePath());
                _playButton.Text = "PLAY OFFLINE";
            }
            finally { _busy = false; }
        }

        private async Task OnPlayClicked()
        {
            var exe = GameExePath();
            if (!File.Exists(exe))
            {
                MessageBox.Show(this, "Game executable not found:\n" + exe, "RazagathWoW",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            if (_windowedBox != null) WriteWindowed(_windowedBox.Checked);
            try
            {
                Process.Start(new ProcessStartInfo { FileName = exe, WorkingDirectory = _root, UseShellExecute = false });
                await Task.Delay(400);
                Close();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "RazagathWoW", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private string GameExePath()
        {
            var name = (_manifest != null && !string.IsNullOrEmpty(_manifest.gameExe)) ? _manifest.gameExe : "Wow.exe";
            return Path.Combine(_root, name);
        }

        // ---- self update: write new exe beside, swap via cmd on exit --------
        private async Task SelfUpdate(LauncherInfo li)
        {
            var me = Assembly.GetExecutingAssembly().Location;
            var stage = me + ".new";
            await Task.Run(() => Download(li.url, stage, (c, l) => SetProgress(l > 0 ? (int)(c * 100 / l) : 0)));
            if (!string.IsNullOrEmpty(li.sha256) && !HashEquals(stage, li.sha256))
            {
                File.Delete(stage);
                throw new Exception("launcher checksum mismatch");
            }
            var bat = Path.Combine(Path.GetTempPath(), "razagath_selfupdate.bat");
            File.WriteAllText(bat,
                "@echo off\r\n" +
                "ping 127.0.0.1 -n 2 >nul\r\n" +
                "move /y \"" + stage + "\" \"" + me + "\" >nul\r\n" +
                "start \"\" \"" + me + "\"\r\n" +
                "del \"%~f0\"\r\n");
            Process.Start(new ProcessStartInfo { FileName = bat, WindowStyle = ProcessWindowStyle.Hidden, UseShellExecute = true });
            Application.Exit();
        }

        // ------------------------------------------------------- rendering --
        private void RenderNews(Manifest m)
        {
            _news.Clear();
            if (m.changelog == null || m.changelog.Count == 0)
            {
                AppendLine(_news, "Welcome to RazagathWoW.", Color.Gainsboro, 11f, FontStyle.Regular);
                return;
            }
            var latest = m.changelog[0];
            AppendLine(_news, "Latest patch  -  " + latest.version + (string.IsNullOrEmpty(latest.date) ? "" : "  (" + latest.date + ")"),
                Color.FromArgb(196, 150, 255), 13f, FontStyle.Bold);
            if (!string.IsNullOrEmpty(latest.title))
                AppendLine(_news, latest.title, Color.Gainsboro, 10.5f, FontStyle.Italic);
            _news.AppendText("\n");
            foreach (var n in latest.notes ?? new List<string>())
                AppendLine(_news, "  -  " + n, Color.Gainsboro, 10f, FontStyle.Regular);
        }

        private void RenderChangelog(Manifest m)
        {
            _changelog.Clear();
            foreach (var c in m.changelog ?? new List<ChangeEntry>())
            {
                AppendLine(_changelog, c.version + (string.IsNullOrEmpty(c.date) ? "" : "   -   " + c.date),
                    Color.FromArgb(196, 150, 255), 12f, FontStyle.Bold);
                if (!string.IsNullOrEmpty(c.title))
                    AppendLine(_changelog, c.title, Color.FromArgb(170, 160, 190), 10f, FontStyle.Italic);
                foreach (var n in c.notes ?? new List<string>())
                    AppendLine(_changelog, "   -  " + n, Color.Gainsboro, 9.75f, FontStyle.Regular);
                _changelog.AppendText("\n");
            }
            _changelog.SelectionStart = 0;
            _changelog.ScrollToCaret();
        }

        private static void AppendLine(RichTextBox box, string text, Color color, float size, FontStyle style)
        {
            box.SelectionStart = box.TextLength;
            box.SelectionLength = 0;
            box.SelectionColor = color;
            box.SelectionFont = new Font("Segoe UI", size, style);
            box.AppendText(text + "\n");
        }

        // -------------------------------------------------------- helpers ----
        private string ReadConfiguredManifestUrl()
        {
            try
            {
                if (File.Exists(_cfgPath))
                {
                    var j = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(_cfgPath));
                    object v;
                    if (j != null && j.TryGetValue("manifestUrl", out v) && v != null && v.ToString().Length > 0)
                        return v.ToString();
                }
            }
            catch { }
            return Program.DefaultManifestUrl;
        }

        private static Manifest FetchManifest(string url)
        {
            using (var wc = new WebClient())
            {
                wc.Headers[HttpRequestHeader.UserAgent] = "RazagathLauncher";
                wc.Headers[HttpRequestHeader.CacheControl] = "no-cache";
                var isHttp = url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                          || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase);
                var bust = isHttp ? url + (url.Contains("?") ? "&" : "?") + "_=" + DateTime.UtcNow.Ticks : url;
                var json = wc.DownloadString(bust);
                var m = new JavaScriptSerializer { MaxJsonLength = 8 * 1024 * 1024 }.Deserialize<Manifest>(json);
                if (m == null) throw new Exception("empty manifest");
                return m;
            }
        }

        private static void Download(string url, string dest, Action<long, long> onProgress)
        {
            var tmp = dest + ".part";
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.UserAgent = "RazagathLauncher";
            req.AllowAutoRedirect = true;
            req.Timeout = 30000;
            req.ReadWriteTimeout = 120000;
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var src = resp.GetResponseStream())
            using (var dst = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                long len = resp.ContentLength;
                var buf = new byte[131072];
                long got = 0; int n;
                while ((n = src.Read(buf, 0, buf.Length)) > 0)
                {
                    dst.Write(buf, 0, n);
                    got += n;
                    if (onProgress != null) onProgress(got, len);
                }
            }
            if (File.Exists(dest)) File.Delete(dest);
            File.Move(tmp, dest);
        }

        private static bool HashEquals(string file, string expectedHex)
        {
            if (string.IsNullOrEmpty(expectedHex)) return true;
            return string.Equals(Sha256(file), expectedHex.Trim(), StringComparison.OrdinalIgnoreCase);
        }
        private static string Sha256(string file)
        {
            using (var sha = SHA256.Create())
            using (var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read))
                return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "");
        }

        private static string LauncherVersion()
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            return v.Major + "." + v.Minor + "." + v.Build;
        }
        private static bool IsNewer(string a, string b)
        {
            Version va, vb;
            if (Version.TryParse(a, out va) && Version.TryParse(b, out vb)) return va > vb;
            return string.CompareOrdinal(a ?? "", b ?? "") > 0;
        }

        private void SetStatus(string s)
        {
            if (InvokeRequired) { BeginInvoke((Action)(() => _statusLabel.Text = s)); return; }
            _statusLabel.Text = s;
        }
        private void SetProgress(int pct)
        {
            pct = Math.Max(0, Math.Min(100, pct));
            if (InvokeRequired) { BeginInvoke((Action)(() => _progress.Value = pct)); return; }
            _progress.Value = pct;
        }

        // ---- realmlist.wtf --------------------------------------------------
        private string RealmlistPath()
        {
            var enus = Path.Combine(_root, "Data", "enUS", "realmlist.wtf");
            var flat = Path.Combine(_root, "realmlist.wtf");
            if (File.Exists(enus)) return enus;
            return flat;
        }
        private string ReadRealmlist()
        {
            try
            {
                var p = RealmlistPath();
                if (File.Exists(p))
                    foreach (var line in File.ReadAllLines(p))
                        if (line.TrimStart().StartsWith("set realmlist", StringComparison.OrdinalIgnoreCase))
                            return line.Trim();
            }
            catch { }
            return "set realmlist 127.0.0.1";
        }
        private void WriteRealmlist(string line)
        {
            if (!line.StartsWith("set realmlist", StringComparison.OrdinalIgnoreCase))
                line = "set realmlist " + line;
            foreach (var p in new[] { Path.Combine(_root, "realmlist.wtf"), Path.Combine(_root, "Data", "enUS", "realmlist.wtf") })
            {
                try { Directory.CreateDirectory(Path.GetDirectoryName(p)); File.WriteAllText(p, line + "\r\n"); } catch { }
            }
        }
        private void EnsureRealmlist(string line)
        {
            var cur = ReadRealmlist();
            if (!string.Equals(cur, line.Trim(), StringComparison.OrdinalIgnoreCase))
                WriteRealmlist(line.Trim());
            if (_realmBox != null) _realmBox.Text = ReadRealmlist();
        }

        // ---- Config.wtf windowed toggle ----------------------------------
        private string ConfigWtfPath() => Path.Combine(_root, "WTF", "Config.wtf");
        private bool ReadWindowed()
        {
            try
            {
                var p = ConfigWtfPath();
                if (File.Exists(p))
                    foreach (var l in File.ReadAllLines(p))
                        if (l.IndexOf("gxWindow", StringComparison.OrdinalIgnoreCase) >= 0)
                            return l.IndexOf("\"1\"") >= 0;
            }
            catch { }
            return true;
        }
        private void WriteWindowed(bool windowed)
        {
            try
            {
                var p = ConfigWtfPath();
                Directory.CreateDirectory(Path.GetDirectoryName(p));
                var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                if (File.Exists(p))
                {
                    foreach (var l in File.ReadAllLines(p))
                    {
                        var t = l.Trim();
                        if (t.StartsWith("SET ", StringComparison.OrdinalIgnoreCase))
                        {
                            var parts = t.Substring(4).Split(new[] { ' ' }, 2);
                            if (parts.Length == 2) map[parts[0]] = parts[1].Trim().Trim('"');
                        }
                    }
                }
                map["gxWindow"] = windowed ? "1" : "0";
                map["gxMaximize"] = windowed ? "1" : "0";
                if (!map.ContainsKey("gxColorBits")) map["gxColorBits"] = "32";
                if (!map.ContainsKey("gxDepthBits")) map["gxDepthBits"] = "24";
                var sb = new StringBuilder();
                foreach (var kv in map) sb.Append("SET ").Append(kv.Key).Append(" \"").Append(kv.Value).Append("\"\r\n");
                File.WriteAllText(p, sb.ToString());
            }
            catch { }
        }

        private void ClearCache()
        {
            try
            {
                var c = Path.Combine(_root, "Cache");
                if (Directory.Exists(c)) Directory.Delete(c, true);
            }
            catch { }
        }
    }
}
