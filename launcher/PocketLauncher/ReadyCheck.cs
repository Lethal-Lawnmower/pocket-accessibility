using System.Diagnostics;

namespace PocketLauncher;

/// <summary>Whether a game can be started.</summary>
internal enum ImportState
{
    /// <summary>The game's own check passes: Play starts it.</summary>
    Ready,
    /// <summary>No import yet.</summary>
    NotImported,
    /// <summary>Imported by an older build: the game would refuse it and
    /// fall back to upstream's launcher, so it must be imported again.</summary>
    NeedsReimport,
}

/// <summary>
/// Asks the game's own import check which games are ready, by running
/// launcher/ReadyCheck (a windowless LÖVE program that loads the game's
/// src/import/CacheContract.lua against the same save folder).  The cheap
/// marker check in GamePaths only tells "never imported" apart from "imported
/// at some point"; an import from an older build passes it but fails the
/// game's check, and the game then opens upstream's launcher instead.
/// </summary>
internal static class ReadyCheck
{
    /// <summary>Each game's state, or null when the check could not run.</summary>
    public static async Task<IReadOnlyDictionary<string, ImportState>?> RunAsync(GamePaths paths)
    {
        if (paths.LoveExe == null || paths.GameDir == null || paths.ReadyCheckDir == null) return null;
        string output = Path.Combine(Path.GetTempPath(), $"pocket-ready-{Environment.ProcessId}.txt");
        File.Delete(output);
        var info = new ProcessStartInfo(paths.LoveExe)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = paths.ReadyCheckDir,
        };
        info.ArgumentList.Add(paths.ReadyCheckDir);
        info.Environment["POCKET_GAME_DIR"] = paths.GameDir;
        info.Environment["POCKET_READY_OUT"] = output;
        try
        {
            using var process = Process.Start(info);
            if (process == null) return null;
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
            await process.WaitForExitAsync(timeout.Token);
            if (!File.Exists(output)) return null;
            var states = new Dictionary<string, ImportState>();
            foreach (string line in await File.ReadAllLinesAsync(output))
            {
                int equals = line.IndexOf('=');
                if (equals <= 0) continue;
                string id = line[..equals];
                string verdict = line[(equals + 1)..];
                if (verdict == "ready") states[id] = ImportState.Ready;
                else if (verdict == "missing") states[id] = ImportState.NotImported;
            }
            return states.Count == GameCatalog.All.Count ? states : null;
        }
        catch (Exception error) when (error is OperationCanceledException or System.ComponentModel.Win32Exception or IOException)
        {
            return null;
        }
        finally
        {
            try { File.Delete(output); } catch (IOException) { }
        }
    }
}
