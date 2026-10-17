using System.Reflection;
using System.Text;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Otonotana.Editor;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        // Self-tests always use a caller-specified isolated profile, never personal drafts.
        var testRoot = args.Length == 2 && args[0] == "--self-test" ? Path.GetFullPath(args[1]) : null;
        var dataRoot = testRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Otonotana", "LyricsEditor");
        Directory.CreateDirectory(dataRoot);
        using var gate = new Mutex(true, "Local\\OtonotanaEditor-" + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(dataRoot)))[..20], out var first);
        if (!first)
        {
            MessageBox.Show("歌詞エディターはすでに開いています。タスクバーから開いている画面を選んでください。", "音の棚");
            return;
        }
        using var form = new EditorWindow(dataRoot, testRoot != null);
        Application.Run(form);
    }
}

internal sealed class EditorWindow : Form
{
    internal const string Origin = "https://editor.otonotana.local/";
    private readonly WebView2 browser = new() { Dock = DockStyle.Fill };
    private readonly string dataRoot;
    private readonly bool selfTest;
    private bool ready, saving;
    private readonly ToolStripStatusLabel status = new("起動しています…");
    private readonly MenuStrip menus = new();
    private readonly NativeAudio nativeAudio = new();
    private readonly System.Windows.Forms.Timer audioTimer = new() { Interval = 50 };
    private string? selectedAudioPath;
    private string? selectedAudioToken;

    internal EditorWindow(string dataRoot, bool selfTest)
    {
        this.dataRoot = dataRoot; this.selfTest = selfTest;
        Text = "音の棚 · 歌詞エディター";
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(1180, 880); MinimumSize = new Size(820, 600);
        BackColor = Color.FromArgb(243, 244, 249);
        Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!);
        var footer = new StatusStrip(); footer.Items.Add(status);
        var file = new ToolStripMenuItem("ファイル(&F)");
        AddCommand(file, "音楽を開く…", "audioFile", Keys.Control | Keys.O);
        AddCommand(file, "歌詞・下書きを開く…", "lrcFile", Keys.Control | Keys.Shift | Keys.O);
        file.DropDownItems.Add(new ToolStripSeparator());
        AddCommand(file, "LRCを保存…", "export", Keys.Control | Keys.S);
        AddCommand(file, "この曲の下書きを保存…", "draft", Keys.Control | Keys.Shift | Keys.S);
        AddCommand(file, "全下書きを保存…", "exportProjects", Keys.Control | Keys.Alt | Keys.S);
        file.DropDownItems.Add(new ToolStripSeparator());
        AddCommand(file, "新しい曲", "newProject", Keys.Control | Keys.N);
        file.DropDownItems.Add("終了", null, (_, _) => Close());
        var help = new ToolStripMenuItem("ヘルプ(&H)");
        help.DropDownItems.Add("ブラウザー版の下書きを引き継ぐ", null, (_, _) => MessageBox.Show(this,
            "① ブラウザー版で「全下書きを保存」を押します。\n② このアプリで「保存済みの歌詞を開く」を押します。\n③ ①で保存したJSONファイルを選びます。\n\n音楽ファイルはコピーしません。曲を切り替えたら対応する音楽を選んでください。", "下書きの引き継ぎ"));
        help.DropDownItems.Add("このアプリについて", null, (_, _) => MessageBox.Show(this,
            "音の棚 · 歌詞エディター 0.4.4\n\n下書きはこのPCに自動保存します。\n大切な編集内容は「全下書きを保存」で別途保存できます。\n\nLRCを音楽と一緒にiPhoneへ転送して使います。", "音の棚"));
        menus.Items.AddRange([file, help]); menus.Enabled = false;
        MainMenuStrip = menus;
        Controls.Add(browser); Controls.Add(footer); Controls.Add(menus);
        Shown += async (_, _) => await InitializeAsync();
        audioTimer.Tick += (_, _) => { if (ready) SendAudioState(); };
        FormClosed += (_, _) => { audioTimer.Stop(); audioTimer.Dispose(); nativeAudio.Dispose(); browser.Dispose(); };
        if (selfTest) { ShowInTaskbar = false; Opacity = 0; }
    }

    private void AddCommand(ToolStripMenuItem menu, string label, string id, Keys shortcut)
    {
        menu.DropDownItems.Add(new ToolStripMenuItem(label, null, async (_, _) => {
            if (ready) await browser.CoreWebView2.CallDevToolsProtocolMethodAsync("Runtime.evaluate", JsonSerializer.Serialize(new {
                expression = $"document.getElementById({JsonSerializer.Serialize(id)}).click()", userGesture = true
            }));
        }) { ShortcutKeys = shortcut });
    }

    private static string Resource(string name)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name) ?? throw new FileNotFoundException(name);
        using var reader = new StreamReader(stream, Encoding.UTF8); return reader.ReadToEnd();
    }

    private async Task InitializeAsync()
    {
        try
        {
            var assets = Path.Combine(dataRoot, "Assets", "0.4.4"); Directory.CreateDirectory(assets);
            foreach (var file in new[] { "index.html", "editor.js", "editor-state.js", "lyrics-core.js" })
                File.WriteAllText(Path.Combine(assets, file), Resource("EditorAssets." + file), new UTF8Encoding(false));
            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: Path.Combine(dataRoot, "Profile"));
            await browser.EnsureCoreWebView2Async(environment);
            var core = browser.CoreWebView2;
            core.SetVirtualHostNameToFolderMapping("editor.otonotana.local", assets, CoreWebView2HostResourceAccessKind.DenyCors);
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsPasswordAutosaveEnabled = false;
            core.Settings.IsGeneralAutofillEnabled = false;
            core.Settings.IsWebMessageEnabled = true;
            core.Settings.AreDefaultScriptDialogsEnabled = !selfTest;
            core.NavigationStarting += (_, e) => { if (e.Uri != Origin + "index.html") e.Cancel = true; };
            core.NewWindowRequested += (_, e) => e.Handled = true;
            core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
            core.DownloadStarting += (_, e) => e.Cancel = true; // Files are saved only by the narrow native bridge below.
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += (_, e) => {
                if (Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var uri) && (uri.Scheme == "https" || uri.Scheme == "http") && uri.Host != "editor.otonotana.local")
                    e.Response = environment.CreateWebResourceResponse(null, 403, "Offline editor", "Content-Type: text/plain");
            };
            core.WebMessageReceived += (_, e) => {
                // Native modal dialogs must open after the WebView2 event callback returns.
                var source = e.Source; var json = e.WebMessageAsJson;
                BeginInvoke(new Action(async () => await ReceiveMessageAsync(source, json)));
            };
            await core.AddScriptToExecuteOnDocumentCreatedAsync(Resource("DesktopBridge.js"));
            core.NavigationCompleted += async (_, e) => {
                if (!e.IsSuccess) { status.Text = "画面を読み込めませんでした。アプリを開き直してください。"; return; }
                ready = true; menus.Enabled = true; status.Text = "PC内で編集 · 下書きは自動保存されます";
                audioTimer.Start();
                if (selfTest) await RunSelfTestAsync();
            };
            core.Navigate(Origin + "index.html");
        }
        catch (Exception error)
        {
            if (selfTest) { FailTest(error); return; }
            MessageBox.Show(this, "アプリを起動できませんでした。\nMicrosoft Edge WebView2 Runtimeが入っていることを確認してください。\n\n" + error.Message, "音の棚", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Close();
        }
    }

    private async Task ReceiveMessageAsync(string source, string json)
    {
        if (source != Origin + "index.html") return;
        int id = 0; bool ownsSave = false;
        try
        {
            using var doc = JsonDocument.Parse(json);
            var message = doc.RootElement;
            id = message.GetProperty("id").GetInt32();
            if (message.GetProperty("kind").GetString() != "save") { await AudioCommandAsync(message, id); return; }
            if (saving) throw new InvalidOperationException("先に開いている保存画面を閉じてください。");
            var content = message.GetProperty("content").GetString() ?? "";
            if (content.Length > 16 * 1024 * 1024) throw new InvalidOperationException("保存する歌詞が大きすぎます。");
            var filename = Path.GetFileName(message.GetProperty("filename").GetString() ?? "lyrics.lrc");
            if (Path.GetExtension(filename).ToLowerInvariant() is not (".lrc" or ".json")) throw new InvalidOperationException("LRCまたは下書きJSONを保存できます。");
            saving = true; ownsSave = true;
            string? destination;
            if (selfTest) destination = filename.StartsWith("cancel-") ? null : Path.Combine(dataRoot, "Saved", filename);
            else
            {
                using var dialog = new SaveFileDialog {
                    Title = Path.GetExtension(filename) == ".lrc" ? "LRCを保存" : "下書きを保存",
                    FileName = filename, DefaultExt = Path.GetExtension(filename).TrimStart('.'),
                    Filter = Path.GetExtension(filename) == ".lrc" ? "時刻付き歌詞 (*.lrc)|*.lrc" : "編集用下書き (*.json)|*.json",
                    AddExtension = true, OverwritePrompt = true, RestoreDirectory = true
                };
                destination = dialog.ShowDialog(this) == DialogResult.OK ? dialog.FileName : null;
            }
            if (destination != null)
            {
                await SaveTextAsync(destination, content);
                status.Text = "保存しました：" + Path.GetFileName(destination);
            }
            else status.Text = "保存をキャンセルしました";
            browser.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { kind = "save-result", id, saved = destination != null }));
        }
        catch (Exception error)
        {
            status.Text = "保存できませんでした";
            browser.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { kind = "save-result", id, error = "保存できませんでした。保存先の空き容量とアクセス権を確認してください。\n" + error.Message }));
        }
        finally { if (ownsSave) saving = false; }
    }

    private void SendAudioState() => browser.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { kind = "audio-state", value = nativeAudio.State }));

    private async Task AudioCommandAsync(JsonElement message, int id)
    {
        try
        {
            object? result = null;
            switch (message.GetProperty("kind").GetString())
            {
                case "choose-audio":
                    string? path;
                    if (selfTest) path = Path.Combine(dataRoot, message.GetProperty("fixture").GetString() switch {
                        "alac" => "alac.m4a", "aac" => "sample.m4a", _ => "sample.wav"
                    });
                    else
                    {
                        using var dialog = new OpenFileDialog { Title = "音楽を開く", Filter = "音楽ファイル|*.m4a;*.mp3;*.wav;*.flac;*.aac;*.wma;*.aiff;*.aif|すべてのファイル|*.*", CheckFileExists = true, Multiselect = false, RestoreDirectory = true };
                        path = dialog.ShowDialog(this) == DialogResult.OK ? dialog.FileName : null;
                    }
                    if (path != null) { selectedAudioPath = path; selectedAudioToken = Guid.NewGuid().ToString("N"); result = new { filename = Path.GetFileName(path), token = selectedAudioToken }; }
                    break;
                case "load-audio":
                    if (selectedAudioPath == null || message.GetProperty("token").GetString() != selectedAudioToken) throw new InvalidDataException("音楽ファイルを選び直してください。");
                    await nativeAudio.OpenAsync(selectedAudioPath); result = nativeAudio.State; break;
                case "play-audio": nativeAudio.Play(); result = nativeAudio.State; break;
                case "pause-audio": nativeAudio.Pause(); result = nativeAudio.State; break;
                case "seek-audio": nativeAudio.Seek(message.GetProperty("seconds").GetDouble()); result = nativeAudio.State; break;
                case "volume-audio": nativeAudio.SetVolume(message.GetProperty("volume").GetDouble()); result = nativeAudio.State; break;
                case "close-audio": nativeAudio.Dispose(); result = nativeAudio.State; break;
                default: throw new InvalidDataException("この操作には対応していません。");
            }
            SendAudioState();
            browser.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { kind = "audio-result", id, value = result }));
        }
        catch (Exception error)
        {
            browser.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { kind = "audio-result", id, error = "音楽を開く／再生する操作に失敗しました：" + error.Message }));
        }
    }

    internal static async Task SaveTextAsync(string destination, string content)
    {
        var folder = Path.GetDirectoryName(destination)!; Directory.CreateDirectory(folder);
        var temp = Path.Combine(folder, ".otonotana-" + Guid.NewGuid().ToString("N") + ".tmp");
        try { await File.WriteAllTextAsync(temp, content, new UTF8Encoding(false)); File.Move(temp, destination, overwrite: true); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }

    private void FailTest(Exception error)
    {
        File.WriteAllText(Path.Combine(dataRoot, "test-error.txt"), error.ToString()); Environment.ExitCode = 1; Close();
    }

    private async Task RunSelfTestAsync()
    {
        try { await DesktopChecks.RunAsync(browser.CoreWebView2, dataRoot); }
        catch (Exception error) { FailTest(error); return; }
        Close();
    }
}
