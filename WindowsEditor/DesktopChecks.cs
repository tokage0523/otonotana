using System.Text;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;

namespace Otonotana.Editor;

internal static class DesktopChecks
{
    internal static async Task RunAsync(CoreWebView2 core, string root)
    {
        var log = new List<string>();
        async Task<JsonElement> Evaluate(string expression)
        {
            var response = await core.CallDevToolsProtocolMethodAsync("Runtime.evaluate", JsonSerializer.Serialize(new { expression, awaitPromise = true, returnByValue = true, userGesture = true })).WaitAsync(TimeSpan.FromSeconds(25));
            using var doc = JsonDocument.Parse(response);
            if (doc.RootElement.TryGetProperty("exceptionDetails", out var error)) throw new Exception(error.ToString());
            return doc.RootElement.GetProperty("result").Clone();
        }
        async Task Assert(string expression, string name)
        {
            var result = await Evaluate(expression);
            if (!result.TryGetProperty("value", out var value) || value.ValueKind != JsonValueKind.True) throw new Exception("Failed: " + name + "\n" + result);
            log.Add("PASS " + name);
        }
        async Task Wait(string expression)
        {
            for (var i = 0; i < 100; i++)
            {
                var result = await Evaluate(expression);
                if (result.TryGetProperty("value", out var value) && value.ValueKind == JsonValueKind.True) return;
                await Task.Delay(100);
            }
            throw new Exception("Timed out: " + expression);
        }
        async Task SelectFile(string selector, string path)
        {
            using var doc = JsonDocument.Parse(await core.CallDevToolsProtocolMethodAsync("DOM.getDocument", "{}"));
            var rootNode = doc.RootElement.GetProperty("root").GetProperty("nodeId").GetInt32();
            using var node = JsonDocument.Parse(await core.CallDevToolsProtocolMethodAsync("DOM.querySelector", JsonSerializer.Serialize(new { nodeId = rootNode, selector })));
            await core.CallDevToolsProtocolMethodAsync("DOM.setFileInputFiles", JsonSerializer.Serialize(new { nodeId = node.RootElement.GetProperty("nodeId").GetInt32(), files = new[] { path } }));
        }
        core.ScriptDialogOpening += (_, e) => e.Accept();
        await Assert("!!window.otonotanaDesktop && !document.querySelector('.hint').textContent.includes('このブラウザに自動保存')", "native bridge and desktop wording");
        if (File.Exists(Path.Combine(root, "phase1.ok")))
        {
            await Assert("document.getElementById('songName').value === '引き継ぎテスト' && document.querySelectorAll('#rows .row').length === 2", "draft restored after closing and reopening the application");
            await Assert("audio.paused && !Number.isFinite(audio.duration)", "restart never plays audio automatically");
            File.WriteAllLines(Path.Combine(root, "phase2.ok"), log);
            return;
        }
        await Evaluate("document.getElementById('songName').value='保存テスト'; document.getElementById('paste').value='最初の一節\\n次の一節'; document.getElementById('append').click(); document.querySelectorAll('#rows input[type=number]').forEach((e,i)=>{e.value=String(1.25+i);e.dispatchEvent(new Event('change'))}); true");
        await Evaluate("document.querySelector('#rows .row [data-adjust=\"0.001\"]').click()");
        await Evaluate("document.getElementById('export').onclick()");
        var saved = Path.Combine(root, "Saved", "保存テスト.lrc");
        if (!File.ReadAllText(saved).Contains("[00:01.251]最初の一節")) throw new Exception("Native LRC save lost the 0.001 second button adjustment: " + File.ReadAllText(saved));
        if (File.ReadAllBytes(saved).Take(3).SequenceEqual(new byte[] { 239, 187, 191 })) throw new Exception("Unexpected UTF-8 BOM");
        log.Add("PASS native save writes Japanese LRC as UTF-8 without BOM");
        await Evaluate("document.querySelector('#rows .row [data-adjust=\"-0.001\"]').click()");
        await Evaluate("document.getElementById('draft').onclick()");
        using (var draft = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "Saved", "保存テスト.json"))))
            if (draft.RootElement.GetProperty("rows").GetArrayLength() != 2) throw new Exception("Native draft export lost rows");
        log.Add("PASS native single-draft JSON save");
        await Evaluate("document.getElementById('shiftSeconds').value='1'; document.getElementById('shift').click(); document.getElementById('undo').click(); true");
        await Assert("Number(document.querySelector('#rows input[type=number]').value)===1.25", "undo remains functional in desktop host");
        await Assert("(async()=>!(await window.otonotanaDesktop.save('cancelled','cancel-check.lrc')))()", "save cancellation is returned without a file");
        await Assert("(async()=>{try{await window.otonotanaDesktop.save('invalid','bad.exe');return false}catch{return true}})()", "native bridge rejects unexpected file types");
        if (File.Exists(Path.Combine(root, "Saved", "cancel-check.lrc")) || File.Exists(Path.Combine(root, "Saved", "bad.exe"))) throw new Exception("Cancelled or invalid save created a file");
        var imported = Path.Combine(root, "browser-drafts.json");
        File.WriteAllText(imported, """
            {"version":2,"activeID":"browser-old","drafts":[{"id":"browser-old","version":1,"name":"引き継ぎテスト","rows":[{"text":"一行目","seconds":null},{"text":"二行目","seconds":null}],"selected":0,"audioFilename":""}]}
            """, new UTF8Encoding(false));
        await SelectFile("#lrcFile", imported);
        await Wait("document.getElementById('songName').value==='引き継ぎテスト'");
        await Assert("document.querySelectorAll('#projects option').length===2 && document.querySelectorAll('#rows .row').length===2", "browser multi-draft JSON imports without replacing existing drafts");
        var wav = Path.Combine(root, "sample.wav"); WriteWave(wav);
        await Assert("openDesktopAudio('wav')", "native file picker loads WAV through the Windows audio engine");
        await Wait("Number.isFinite(audio.duration) && audio.duration>4");
        await Assert("(async()=>{audio.currentTime=1.5;await audio.play();return !audio.paused})()", "native seek starts playback at the requested position");
        await Wait("audio.currentTime>1.6");
        await Evaluate("audio.pause(); document.getElementById('stamp').click(); true");
        await Assert("Number(document.querySelector('#rows input[type=number]').value)>=1.5 && Number(document.querySelector('#rows input[type=number]').value)<3", "lyric stamping uses the native playback clock");
        await Evaluate("preview(0)");
        await Wait("!audio.paused");
        await Evaluate("[...document.querySelector('#rows .row').querySelectorAll('button')].find(b=>b.textContent==='停止').click()");
        await Wait("audio.paused");
        await Task.Delay(150);
        var stoppedAt = (await Evaluate("audio.currentTime")).GetProperty("value").GetDouble();
        await Task.Delay(250);
        var stoppedLater = (await Evaluate("audio.currentTime")).GetProperty("value").GetDouble();
        if (stoppedAt < 1.4 || Math.Abs(stoppedLater - stoppedAt) >= 0.02) throw new Exception("Row stop reset or failed to pause the native playback clock");
        log.Add("PASS lyric-row stop pauses native playback without resetting position");
        if (File.Exists(Path.Combine(root, "sample.m4a")))
        {
            await Assert("openDesktopAudio('aac')", "native AAC M4A load");
            await Assert("(async()=>{await audio.play();return !audio.error && !audio.paused})()", "M4A AAC playback in the real Windows host");
            await Wait("audio.currentTime>0.1");
            await Evaluate("audio.pause(); true");
        }
        if (File.Exists(Path.Combine(root, "alac.m4a")))
        {
            await Assert("openDesktopAudio('alac')", "ALAC M4A opens without transcoding");
            await Assert("(async()=>{await audio.play();return !audio.error && !audio.paused})()", "ALAC M4A starts native playback");
            await Wait("audio.currentTime>0.15");
            await Evaluate("audio.pause(); audio.currentTime=2; true");
            await Wait("audio.paused && audio.currentTime>=1.95 && audio.currentTime<2.2");
            await Assert("(async()=>{await audio.play();return !audio.paused})()", "ALAC can resume after seeking while paused");
            await Wait("audio.currentTime>2.2");
            await Evaluate("audio.pause(); audio.volume=0.4; true");
            await Wait("audio.paused && audio.volume===0.4");
            await Assert("(async()=>{let a=await window.otonotanaDesktop.chooseAudio('alac');try{await window.otonotanaDesktop.loadAudio(a.token+'bad');return false}catch{return true}})()", "audio access requires the native picker token");
        }
        await Evaluate("document.getElementById('exportProjects').onclick()");
        using (var book = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "Saved", "引き継ぎテスト.json"))))
            if (book.RootElement.GetProperty("drafts").GetArrayLength() != 2) throw new Exception("Full export lost a draft");
        log.Add("PASS native full-draft backup");
        core.Navigate("https://example.com/");
        await Task.Delay(100);
        await Assert("location.href === 'https://editor.otonotana.local/index.html'", "external page navigation blocked");
        await Evaluate("window.scrollTo(0,0)");
        using (var screenshot = File.Create(Path.Combine(root, "desktop-preview.png"))) await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, screenshot);
        await Evaluate("closeAudio(); true");
        await Wait("audio.paused && !Number.isFinite(audio.duration)");
        File.WriteAllLines(Path.Combine(root, "phase1.ok"), log);
    }

    private static void WriteWave(string path)
    {
        const int sampleRate = 16000, count = sampleRate * 5;
        using var writer = new BinaryWriter(File.Create(path));
        writer.Write(Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + count * 2); writer.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
        writer.Write(16); writer.Write((short)1); writer.Write((short)1); writer.Write(sampleRate); writer.Write(sampleRate * 2); writer.Write((short)2); writer.Write((short)16);
        writer.Write(Encoding.ASCII.GetBytes("data")); writer.Write(count * 2);
        for (var i = 0; i < count; i++) writer.Write((short)(Math.Sin(i * Math.PI * 2 * 440 / sampleRate) * 600));
    }
}
