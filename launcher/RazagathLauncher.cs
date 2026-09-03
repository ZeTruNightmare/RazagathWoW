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
            if (args != null && args.Length > 0 &&
                (args[0] == "--patch-exe" || args[0] == "/patch-exe"))
            {
                var dir = args.Length > 1 ? args[1] : AppDomain.CurrentDomain.BaseDirectory;
                var oc = ExePatcher.Ensure(Path.Combine(dir, "Wow.exe"));
                try { File.WriteAllText(Path.Combine(Path.GetTempPath(), "razagath_patchexe.log"), oc.Status + ": " + oc.Message); } catch { }
                Environment.Exit((oc.Status == ExePatcher.Status.Patched || oc.Status == ExePatcher.Status.AlreadyPatched) ? 0 : 1);
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

    // ---- in-place game-exe patcher -----------------------------------------
    //  The distribution ships NO Blizzard binary - only the list of five byte
    //  offsets we change. The launcher verifies the player's own Wow.exe is the
    //  known-clean 3.3.5a (build 12340) ChromieCraft binary, backs it up to
    //  Wow.exe.orig, and pokes the bytes that let a custom class + custom
    //  GlueXML load.
    internal static class ExePatcher
    {
        public const string CleanSha256   = "aa63a5750d60ef16746c686b3d5e26876d98953eab08b1c026cd0faf78e88cb8";
        public const string PatchedSha256 = "0c540dd96d7dc749501fcb7db2de4285db8662ec035b31aabbc6e53a5dee47fa";
        public const long   ExpectedSize  = 7704216;

        private sealed class Poke
        {
            public readonly long Offset; public readonly byte[] Old; public readonly byte[] New;
            public Poke(long o, string oldHex, string newHex) { Offset = o; Old = Hex(oldHex); New = Hex(newHex); }
        }
        // file offset = virtual address - 0x400C00  (.text: RVA 0x1000 @ raw 0x400)
        private static readonly Poke[] Pokes =
        {
            new Poke(0x4159E0, "558BEC81EC1C01", "B803000000C390"), // VA 0x8165E0  sig check -> return 3 (valid)
            new Poke(0x0D9BBD, "E8CEA51100",     "9090909090"),     // VA 0x4DA7BD  don't rename loose GlueXML/FrameXML to .old
            new Poke(0x0D9CEB, "0F852DFFFFFF",   "909090909090"),   // VA 0x4DA8EB  no GlueXML toc-hash abort
            new Poke(0x12A143, "740A",           "EB0A"),           // VA 0x52AD43  no FrameXML hash abort
            new Poke(0x1F77EC, "740A",           "EB0A"),           // VA 0x5F83EC  no FrameXML manifest abort
        };

        public enum Status { AlreadyPatched, Patched, UnknownExe, NotFound, Failed }

        public struct Outcome
        {
            public Status Status; public string Message;
            public Outcome(Status s, string m) { Status = s; Message = m; }
        }

        public static Outcome Ensure(string exePath)
        {
            if (!File.Exists(exePath))
                return new Outcome(Status.NotFound, "Wow.exe not found at " + exePath);

            var hash = Sha256File(exePath);
            if (string.Equals(hash, PatchedSha256, StringComparison.OrdinalIgnoreCase))
                return new Outcome(Status.AlreadyPatched, "Wow.exe already patched.");
            if (!string.Equals(hash, CleanSha256, StringComparison.OrdinalIgnoreCase))
                return new Outcome(Status.UnknownExe,
                    "Wow.exe is not the recognised clean 3.3.5a (build 12340) client, so it was left untouched.");

            try
            {
                var bak = Path.Combine(Path.GetDirectoryName(exePath), "Wow.exe.orig");
                if (!File.Exists(bak)) File.Copy(exePath, bak);

                var bytes = File.ReadAllBytes(exePath);
                if (bytes.LongLength != ExpectedSize) return new Outcome(Status.Failed, "unexpected size");
                foreach (var p in Pokes)
                {
                    for (int i = 0; i < p.Old.Length; i++)
                        if (bytes[p.Offset + i] != p.Old[i])
                            return new Outcome(Status.Failed, "byte mismatch at 0x" + p.Offset.ToString("X"));
                    for (int i = 0; i < p.New.Length; i++)
                        bytes[p.Offset + i] = p.New[i];
                }
                var tmp = exePath + ".patched";
                File.WriteAllBytes(tmp, bytes);
                if (!string.Equals(Sha256File(tmp), PatchedSha256, StringComparison.OrdinalIgnoreCase))
                { File.Delete(tmp); return new Outcome(Status.Failed, "post-patch checksum mismatch"); }
                File.Delete(exePath);
                File.Move(tmp, exePath);
                return new Outcome(Status.Patched, "Wow.exe patched for RazagathWoW (original saved as Wow.exe.orig).");
            }
            catch (Exception ex) { return new Outcome(Status.Failed, ex.Message); }
        }

        private static byte[] Hex(string h)
        {
            var b = new byte[h.Length / 2];
            for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(h.Substring(i * 2, 2), 16);
            return b;
        }
        private static string Sha256File(string f)
        {
            using (var sha = SHA256.Create())
            using (var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.Read))
                return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "");
        }
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

    // ---- header: blurred photo (cover) + dark scrim + centred logo ----------
    internal sealed class HeaderBanner : Panel
    {
        public Image Background;
        public Image Logo;
        public int ScrimAlpha = 90;
        public Padding LogoPad = new Padding(12, 6, 12, 10);

        public HeaderBanner()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                   | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            BackColor = Color.FromArgb(18, 15, 24);
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            var r = ClientRectangle;
            g.Clear(BackColor);

            if (Background != null)
            {
                // cover: scale to fill, crop the overflow, keep aspect
                float s = Math.Max((float)r.Width / Background.Width, (float)r.Height / Background.Height);
                int dw = (int)Math.Ceiling(Background.Width * s);
                int dh = (int)Math.Ceiling(Background.Height * s);
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.DrawImage(Background, (r.Width - dw) / 2, (r.Height - dh) / 2, dw, dh);
            }

            if (ScrimAlpha > 0)
                using (var b = new SolidBrush(Color.FromArgb(ScrimAlpha, 12, 9, 18)))
                    g.FillRectangle(b, r);

            if (Logo != null)
            {
                int aw = r.Width - LogoPad.Horizontal;
                int ah = r.Height - LogoPad.Vertical;
                float s = Math.Min((float)aw / Logo.Width, (float)ah / Logo.Height);
                int lw = (int)(Logo.Width * s);
                int lh = (int)(Logo.Height * s);
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.DrawImage(Logo, (r.Width - lw) / 2, LogoPad.Top + (ah - lh) / 2, lw, lh);
            }
        }
    }

    // ---- a borderless image button (image carries its own label) -----------
    internal sealed class ImageButton : Control
    {
        private Image _img;
        private bool _hover, _down;

        public ImageButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                   | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        public Image NormalImage { get { return _img; } set { _img = value; Invalidate(); } }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Cursor = Enabled ? Cursors.Hand : Cursors.Default; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; _down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { if (Enabled) { _down = true; Invalidate(); } base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { _down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void OnClick(EventArgs e) { if (Enabled) base.OnClick(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            if (_img == null) return;
            var g = e.Graphics;
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;

            var r = ClientRectangle;
            float s = Math.Min((float)r.Width / _img.Width, (float)r.Height / _img.Height);
            if (_down && Enabled) s *= 0.96f;
            int w = (int)(_img.Width * s), h = (int)(_img.Height * s);
            var dest = new Rectangle((r.Width - w) / 2, (r.Height - h) / 2, w, h);

            if (!Enabled)
                DrawMatrixed(g, dest, new float[] {
                    0.28f, 0.28f, 0.28f, 0, 0,
                    0.28f, 0.28f, 0.28f, 0, 0,
                    0.28f, 0.28f, 0.28f, 0, 0,
                    0,     0,     0,     0.5f, 0,
                    0,     0,     0,     0,  1 });
            else if (_hover)
                DrawMatrixed(g, dest, new float[] {
                    1,0,0,0,0,  0,1,0,0,0,  0,0,1,0,0,  0,0,0,1,0,  0.13f,0.13f,0.13f,0,1 });
            else
                g.DrawImage(_img, dest);
        }

        private void DrawMatrixed(Graphics g, Rectangle dest, float[] m)
        {
            var cm = new System.Drawing.Imaging.ColorMatrix(new float[][] {
                new float[]{m[0],m[1],m[2],m[3],m[4]},
                new float[]{m[5],m[6],m[7],m[8],m[9]},
                new float[]{m[10],m[11],m[12],m[13],m[14]},
                new float[]{m[15],m[16],m[17],m[18],m[19]},
                new float[]{m[20],m[21],m[22],m[23],m[24]} });
            using (var ia = new System.Drawing.Imaging.ImageAttributes())
            {
                ia.SetColorMatrix(cm);
                g.DrawImage(_img, dest, 0, 0, _img.Width, _img.Height, GraphicsUnit.Pixel, ia);
            }
        }
    }

    // ---- TabControl with its native tab strip hidden (driven by TabStrip) ---
    internal sealed class DarkTabControl : TabControl
    {
        public DarkTabControl()
        {
            SizeMode = TabSizeMode.Fixed;
            ItemSize = new Size(0, 1);
            Appearance = TabAppearance.FlatButtons;
        }

        protected override void WndProc(ref Message m)
        {
            // TCM_ADJUSTRECT: make the page area cover the whole control (hide the strip)
            if (m.Msg == 0x1328 && !DesignMode) { m.Result = (IntPtr)1; return; }
            base.WndProc(ref m);
        }
    }

    // ---- a panel that paints an image cover-fit as its background ----------
    internal class TexturePanel : Panel
    {
        public Image Texture;
        public TexturePanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                   | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            BackColor = Color.FromArgb(14, 11, 18);
        }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        protected override void OnPaint(PaintEventArgs e)
        {
            PaintTexture(e.Graphics, ClientRectangle, Texture, BackColor);
            base.OnPaint(e);
        }
        public static void PaintTexture(Graphics g, Rectangle r, Image tex, Color fallback)
        {
            g.Clear(fallback);
            if (tex == null) return;
            float s = Math.Max((float)r.Width / tex.Width, (float)r.Height / tex.Height);
            int dw = (int)Math.Ceiling(tex.Width * s), dh = (int)Math.Ceiling(tex.Height * s);
            g.DrawImage(tex, r.Left + (r.Width - dw) / 2, r.Top + (r.Height - dh) / 2, dw, dh);
        }
    }

    // ---- owner-drawn scrolling rich text on a textured panel --------------
    internal sealed class ChangelogView : TexturePanel
    {
        private struct Run { public string Text; public Color Color; public Font Font; public int Indent; public int GapAbove; public bool Outline; }
        private readonly System.Collections.Generic.List<Run> _runs = new System.Collections.Generic.List<Run>();
        private static readonly Point[] OutlineOffsets =
        {
            new Point(-1,-1), new Point(0,-1), new Point(1,-1),
            new Point(-1, 0),                  new Point(1, 0),
            new Point(-1, 1), new Point(0, 1), new Point(1, 1),
        };
        private int _scroll, _contentH, _viewH;
        public Image Divider;                 // small gold flourish at top + bottom edges
        private const int DivH = 21;          // divider render height
        private const int DivPad = 32;        // text inset that clears the divider

        public ChangelogView()
        {
            Padding = new Padding(22, DivPad, 16, DivPad);
            SetStyle(ControlStyles.Selectable, true);
            TabStop = false;
        }

        public void Clear() { foreach (var r in _runs) r.Font.Dispose(); _runs.Clear(); _scroll = 0; Invalidate(); }
        public void Add(string text, Color c, float size, FontStyle fs, int indent, int gapAbove, bool outline = false)
        {
            _runs.Add(new Run { Text = text ?? "", Color = c, Font = new Font("Segoe UI", size, fs),
                Indent = indent, GapAbove = gapAbove, Outline = outline });
            Invalidate();
        }

        protected override void OnMouseEnter(EventArgs e) { if (CanFocus) Focus(); base.OnMouseEnter(e); }
        protected override void OnMouseWheel(MouseEventArgs e)
        {
            int max = Math.Max(0, _contentH - _viewH);
            _scroll = Math.Max(0, Math.Min(max, _scroll - Math.Sign(e.Delta) * 48));
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e); // texture
            var g = e.Graphics;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            int x0 = Padding.Left;
            int w = ClientSize.Width - Padding.Horizontal;
            _viewH = ClientSize.Height - Padding.Vertical;
            int y = Padding.Top - _scroll;

            g.SetClip(new Rectangle(0, Padding.Top - 2, ClientSize.Width, _viewH + 4));
            foreach (var r in _runs)
            {
                y += r.GapAbove;
                var flags = TextFormatFlags.WordBreak | TextFormatFlags.NoPadding;
                var sz = TextRenderer.MeasureText(g, r.Text, r.Font, new Size(w - r.Indent, 0), flags);
                if (y + sz.Height > Padding.Top - 2 && y < ClientSize.Height)
                {
                    var rect = new Rectangle(x0 + r.Indent, y, w - r.Indent, sz.Height);
                    if (r.Outline)
                    {
                        foreach (var o in OutlineOffsets)
                        {
                            var rr = rect; rr.Offset(o);
                            TextRenderer.DrawText(g, r.Text, r.Font, rr, Color.Black, flags);
                        }
                    }
                    TextRenderer.DrawText(g, r.Text, r.Font, rect, r.Color, flags);
                }
                y += sz.Height;
            }
            g.ResetClip();
            _contentH = y + _scroll - Padding.Top;

            if (_contentH > _viewH)
            {
                int trackH = ClientSize.Height - 8;
                int thumbH = Math.Max(24, (int)((float)_viewH / _contentH * trackH));
                int max = _contentH - _viewH;
                int thumbY = 4 + (max > 0 ? (int)((float)_scroll / max * (trackH - thumbH)) : 0);
                using (var b = new SolidBrush(Color.FromArgb(70, 255, 255, 255)))
                    g.FillRectangle(b, ClientSize.Width - 6, thumbY, 4, thumbH);
            }

            if (Divider != null)
            {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                int dw = (int)((float)Divider.Width / Divider.Height * DivH);
                int maxw = ClientSize.Width - 24;
                if (dw > maxw) dw = maxw;
                int dh = (int)((float)Divider.Height / Divider.Width * dw);
                int dx = (ClientSize.Width - dw) / 2;
                g.DrawImage(Divider, dx, 5, dw, dh);
                g.DrawImage(Divider, dx, ClientSize.Height - dh - 5, dw, dh);
            }
        }
    }

    // ---- our own dark tab buttons, wired to a DarkTabControl ----------------
    internal sealed class TabStrip : Panel
    {
        private readonly DarkTabControl _tabs;
        private readonly string[] _labels;
        private int _hot = -1;
        public Image Texture;
        private const int BtnW = 118;

        public TabStrip(DarkTabControl tabs, params string[] labels)
        {
            _tabs = tabs; _labels = labels;
            Height = 32; BackColor = Color.FromArgb(14, 11, 18);
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                   | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            _tabs.SelectedIndexChanged += (s, e) => Invalidate();
        }

        private int HitTest(int x) { int i = x / BtnW; return (i >= 0 && i < _labels.Length) ? i : -1; }

        protected override void OnMouseMove(MouseEventArgs e) { int h = HitTest(e.X); if (h != _hot) { _hot = h; Invalidate(); } base.OnMouseMove(e); }
        protected override void OnMouseLeave(EventArgs e) { _hot = -1; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            int i = HitTest(e.X);
            if (i >= 0 && i < _tabs.TabCount) _tabs.SelectedIndex = i;
            base.OnMouseDown(e);
        }
        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            TexturePanel.PaintTexture(g, ClientRectangle, Texture, BackColor);
            for (int i = 0; i < _labels.Length; i++)
            {
                var r = new Rectangle(i * BtnW, 0, BtnW, Height);
                bool sel = i == _tabs.SelectedIndex;
                if (sel) using (var b = new SolidBrush(Color.FromArgb(52, 255, 255, 255))) g.FillRectangle(b, r);
                else if (i == _hot) using (var b = new SolidBrush(Color.FromArgb(22, 255, 255, 255))) g.FillRectangle(b, r);
                TextRenderer.DrawText(g, _labels[i], Font, r, sel ? Color.White : Color.FromArgb(165, 160, 178),
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            }
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly string _root;
        private readonly string _cfgPath;
        private string _manifestUrl;

        private Manifest _manifest;
        private readonly ImageButton _playButton = new ImageButton();
        private TexturePanel _footer;
        private readonly Label _statusLabel = new Label();
        private readonly ProgressBar _progress = new ProgressBar();
        private readonly DarkTabControl _tabs = new DarkTabControl();
        private readonly ChangelogView _news = new ChangelogView();
        private readonly ChangelogView _changelog = new ChangelogView();
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
            ClientSize = new Size(720, 588);
            BackColor = Color.FromArgb(24, 20, 32);
            Font = new Font("Segoe UI", 9f);
            try { this.Icon = System.Drawing.Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location); } catch { }

            BuildUi();
            Shown += async (s, e) => await RefreshAsync();
        }

        // ---------------------------------------------------------------- UI --
        private void BuildUi()
        {
            var header = new HeaderBanner
            {
                Dock = DockStyle.Top,
                Height = 168,
                Background = LoadEmbedded("RazagathWoW.header-bg.png"),
                Logo = LoadEmbedded("RazagathWoW.logo.png"),
                ScrimAlpha = 90          // 0-255 dark wash over the photo
            };

            var panelTex   = LoadEmbedded("RazagathWoW.panel-bg.jpg");
            var contentTex = LoadEmbedded("RazagathWoW.content-bg.jpg");
            var dividerImg = LoadEmbedded("RazagathWoW.divider.png");

            _tabs.Dock = DockStyle.Fill;
            _tabs.Padding = new Point(14, 6);

            // ---- Play tab ----
            var playTab = new TabPage("  Play  ") { BackColor = BackColor };
            _news.Dock = DockStyle.Fill;
            _news.Texture = contentTex;
            _news.Divider = dividerImg;
            playTab.Controls.Add(_news);

            // ---- Changelog tab ----
            var clTab = new TabPage("  Changelog  ") { BackColor = BackColor };
            _changelog.Dock = DockStyle.Fill;
            _changelog.Texture = contentTex;
            _changelog.Divider = dividerImg;
            clTab.Controls.Add(_changelog);

            // ---- Settings tab ----
            var setTab = new TabPage("  Settings  ") { BackColor = BackColor };
            setTab.Controls.Add(BuildSettingsPanel());

            _tabs.TabPages.Add(playTab);
            _tabs.TabPages.Add(clTab);
            _tabs.TabPages.Add(setTab);

            const int FooterH = 116;
            _footer = new TexturePanel { Dock = DockStyle.Bottom, Height = FooterH, Texture = panelTex };
            var footer = _footer;
            _statusLabel.Text = "Starting...";
            _statusLabel.ForeColor = Color.Gainsboro;
            _statusLabel.BackColor = Color.Transparent;
            _statusLabel.AutoSize = false;
            _statusLabel.Location = new Point(26, 32);
            _statusLabel.Size = new Size(360, 20);
            _progress.Location = new Point(26, 58);
            _progress.Size = new Size(360, 20);
            _progress.Style = ProgressBarStyle.Continuous;

            _playButton.NormalImage = LoadEmbedded("RazagathWoW.play-button.png");
            _playButton.Size = new Size(288, 108);
            _playButton.Location = new Point(720 - 14 - 288, (FooterH - 108) / 2);
            _playButton.Enabled = false;
            _playButton.Click += async (s, e) => await OnPlayClicked();

            footer.Controls.Add(_statusLabel);
            footer.Controls.Add(_progress);
            footer.Controls.Add(_playButton);

            var tabStrip = new TabStrip(_tabs, "Play", "Changelog", "Settings") { Dock = DockStyle.Top, Texture = panelTex };

            // docking is applied in reverse add-order: _tabs (Fill) added first
            // so it docks last and takes the space left by the others
            Controls.Add(_tabs);
            Controls.Add(footer);
            Controls.Add(tabStrip);
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
                ForeColor = Color.FromArgb(135, 132, 138),
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
                    if (string.IsNullOrEmpty(f.url) || string.IsNullOrEmpty(f.sha256)) continue; // not published yet
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

                // make sure the player's own Wow.exe carries the client patches
                var exe = await Task.Run(() => ExePatcher.Ensure(GameExePath()));
                if (exe.Status == ExePatcher.Status.Patched)
                    SetStatus("Wow.exe patched  -  client " + _manifest.clientVersion + ".  Ready.");
                else if (exe.Status == ExePatcher.Status.UnknownExe)
                    SetStatus("Note: Wow.exe is not a recognised clean 3.3.5a client - launching anyway.");
                else if (exe.Status == ExePatcher.Status.NotFound)
                {
                    SetStatus("Wow.exe not found - put the launcher in your WoW 3.3.5a folder.");
                    _playButton.Enabled = false;
                    return;
                }

                _playButton.Enabled = true;
            }
            catch (Exception ex)
            {
                // still allow play so a network blip never blocks login
                var canPlay = File.Exists(GameExePath());
                SetStatus((canPlay ? "Offline - you can still play.  " : "") + "Update failed: " + ex.Message);
                _playButton.Enabled = canPlay;
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
        private static readonly Color HeadColor = Color.FromArgb(0xA1, 0xFC, 0x03);   // #a1fc03
        private static readonly Color BodyColor = Color.FromArgb(228, 224, 220);
        private static readonly Color SubColor  = Color.FromArgb(182, 178, 172);

        // Show one date only, British style DD.MM.YYYY. version is usually
        // YYYY.MM.DD (build-release default); fall back to the ISO date field.
        private static string PatchDate(string version, string date)
        {
            var m = System.Text.RegularExpressions.Regex.Match(version ?? "", @"^(\d{4})\.(\d{1,2})\.(\d{1,2})$");
            if (!m.Success)
                m = System.Text.RegularExpressions.Regex.Match(date ?? "", @"^(\d{4})-(\d{1,2})-(\d{1,2})$");
            if (m.Success)
                return string.Format("{0:00}.{1:00}.{2}", int.Parse(m.Groups[3].Value),
                    int.Parse(m.Groups[2].Value), m.Groups[1].Value);
            return string.IsNullOrEmpty(version) ? (date ?? "") : version;
        }

        private void RenderNews(Manifest m)
        {
            _news.Clear();
            if (m.changelog == null || m.changelog.Count == 0)
            {
                _news.Add("Welcome to RazagathWoW.", BodyColor, 11f, FontStyle.Regular, 0, 0);
                return;
            }
            var latest = m.changelog[0];
            _news.Add("Latest patch  -  " + PatchDate(latest.version, latest.date),
                HeadColor, 13f, FontStyle.Bold, 0, 0, true);
            if (!string.IsNullOrEmpty(latest.title))
                _news.Add(latest.title, SubColor, 10.5f, FontStyle.Italic, 0, 2);
            foreach (var n in latest.notes ?? new List<string>())
                _news.Add("-   " + n, BodyColor, 10f, FontStyle.Regular, 14, 8);
        }

        private void RenderChangelog(Manifest m)
        {
            _changelog.Clear();
            bool first = true;
            foreach (var c in m.changelog ?? new List<ChangeEntry>())
            {
                _changelog.Add(PatchDate(c.version, c.date), HeadColor, 12f, FontStyle.Bold, 0, first ? 0 : 18, true);
                first = false;
                if (!string.IsNullOrEmpty(c.title))
                    _changelog.Add(c.title, SubColor, 9.75f, FontStyle.Italic, 0, 2);
                foreach (var n in c.notes ?? new List<string>())
                    _changelog.Add("-   " + n, BodyColor, 9.5f, FontStyle.Regular, 14, 6);
            }
        }

        private static Image LoadEmbedded(string name)
        {
            try
            {
                var asm = Assembly.GetExecutingAssembly();
                using (var s = asm.GetManifestResourceStream(name))
                {
                    if (s == null) return null;
                    using (var ms = new MemoryStream())
                    {
                        s.CopyTo(ms);
                        return Image.FromStream(new MemoryStream(ms.ToArray()));
                    }
                }
            }
            catch { return null; }
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
