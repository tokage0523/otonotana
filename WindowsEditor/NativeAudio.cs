global using System.IO;
using System.Windows.Media;

namespace Otonotana.Editor;

// Windows decodes the original file directly; no transcoded or temporary audio files.
internal sealed class NativeAudio : IDisposable
{
    private MediaPlayer? player;
    private bool ended;
    private bool paused = true;
    private double volume = 1;
    private string filename = "";
    private string? error;
    private int generation;
    internal double Duration => player?.NaturalDuration.HasTimeSpan == true ? player.NaturalDuration.TimeSpan.TotalSeconds : 0;
    internal double Position => ended ? Duration : Math.Clamp(player?.Position.TotalSeconds ?? 0, 0, Duration);
    internal object State => new { duration = Duration, position = Position, paused, ended, volume, filename, error };

    internal async Task OpenAsync(string path)
    {
        var openingGeneration = ++generation;
        var next = new MediaPlayer { Volume = volume };
        var opened = new TaskCompletionSource();
        next.MediaOpened += (_, _) => opened.TrySetResult();
        next.MediaFailed += (_, e) => {
            opened.TrySetException(e.ErrorException);
            if (player == next) { error = "音楽を再生できませんでした。"; paused = true; }
        };
        next.MediaEnded += (_, _) => { if (player == next) { ended = true; paused = true; } };
        try
        {
            next.Open(new Uri(Path.GetFullPath(path)));
            await opened.Task.WaitAsync(TimeSpan.FromSeconds(15));
            if (openingGeneration != generation) throw new OperationCanceledException("音楽の読み込みをキャンセルしました。");
            if (!next.HasAudio || !next.NaturalDuration.HasTimeSpan || next.NaturalDuration.TimeSpan.TotalSeconds <= 0)
                throw new InvalidDataException("再生できる音声が見つかりません。");
            player?.Close(); player = next; ended = false; paused = true; error = null;
            filename = Path.GetFileName(path);
        }
        catch { next.Close(); throw; }
    }
    internal void Play()
    {
        if (player == null) throw new InvalidOperationException("先に音楽ファイルを選んでください。");
        if (ended) Seek(0);
        player.Play(); paused = false;
    }
    internal void Pause() { player?.Pause(); paused = true; }
    internal void Seek(double seconds)
    {
        if (!double.IsFinite(seconds)) throw new InvalidDataException("再生位置が正しくありません。");
        if (player == null) return;
        player.Position = TimeSpan.FromSeconds(Math.Clamp(seconds, 0, Duration)); ended = false;
    }
    internal void SetVolume(double value)
    {
        if (!double.IsFinite(value)) throw new InvalidDataException("音量が正しくありません。");
        volume = Math.Clamp(value, 0, 1); if (player != null) player.Volume = volume;
    }
    public void Dispose() { generation++; player?.Close(); player = null; paused = true; ended = false; filename = ""; error = null; }
}
