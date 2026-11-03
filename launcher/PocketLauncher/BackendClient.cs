using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace PocketLauncher;

/// <summary>
/// Talks to a windowless LÖVE program holding upstream's logic (launcher/SaveBackend,
/// launcher/ModBackend): one JSON request per line on its stdin, one answer per line
/// on its stdout.  Requests run strictly one at a time in the order sent, so a
/// field's edit always lands before a Save pressed right after it.
/// docs/access/save-editor.md holds the save editor's protocol.
/// </summary>
/// <param name="backendDir">The backend's folder, null if it was not found.</param>
/// <param name="displayName">What the backend is called in error messages.</param>
internal sealed class BackendClient(GamePaths paths, string? backendDir, string displayName) : IDisposable
{
    private const string ResponsePrefix = "@@PA ";
    private Process? process;
    private Task tail = Task.CompletedTask;
    private int nextId;

    /// <summary>The console build of LÖVE, whose standard streams work when redirected.</summary>
    private static string ConsoleLove(string loveExe) =>
        Path.Combine(Path.GetDirectoryName(loveExe) ?? "", "lovec.exe");

    public async Task StartAsync()
    {
        if (paths.LoveExe == null || paths.GameDir == null || backendDir == null)
        {
            throw new InvalidOperationException($"The {displayName}'s files were not found.");
        }
        string love = ConsoleLove(paths.LoveExe);
        if (!File.Exists(love)) throw new InvalidOperationException($"{love} was not found.");
        var info = new ProcessStartInfo(love)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = backendDir,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardInputEncoding = new UTF8Encoding(false),
            StandardOutputEncoding = new UTF8Encoding(false),
        };
        info.ArgumentList.Add(backendDir);
        info.Environment["POCKET_GAME_DIR"] = paths.GameDir;
        // upstream's self-updater and our game layer have no place here
        info.Environment["POKEPORT_PORTMASTER_MANAGED"] = "1";
        info.Environment["POKEPORT_ACCESS"] = "0";
        process = Process.Start(info) ?? throw new InvalidOperationException($"The {displayName} did not start.");
        // stderr is upstream's logging; it must be drained or the program blocks
        process.ErrorDataReceived += (_, _) => { };
        process.BeginErrorReadLine();
        await ReadResponseAsync();
    }

    private async Task<JsonObject> ReadResponseAsync()
    {
        while (true)
        {
            string? line = await process!.StandardOutput.ReadLineAsync();
            if (line == null) throw new InvalidOperationException($"The {displayName} stopped unexpectedly.");
            if (line.StartsWith(ResponsePrefix, StringComparison.Ordinal))
            {
                return JsonNode.Parse(line[ResponsePrefix.Length..])!.AsObject();
            }
        }
    }

    /// <summary>Sends one command; the answer's "ok" and "error" are left to the caller.</summary>
    public Task<JsonObject> SendAsync(string command, JsonObject? arguments = null)
    {
        var request = arguments ?? [];
        request["cmd"] = command;
        request["id"] = ++nextId;
        var finished = new TaskCompletionSource<JsonObject>();
        tail = tail.ContinueWith(async _ =>
        {
            try
            {
                await process!.StandardInput.WriteLineAsync(request.ToJsonString(WireFormat));
                await process.StandardInput.FlushAsync();
                finished.SetResult(await ReadResponseAsync());
            }
            catch (Exception error)
            {
                finished.SetException(error);
            }
        }, TaskScheduler.Default).Unwrap();
        return finished.Task;
    }

    /// <summary>Non-ASCII names go as themselves; the backend's decoder keeps bytes.</summary>
    private static readonly JsonSerializerOptions WireFormat = new()
    {
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public void Dispose()
    {
        if (process == null) return;
        try
        {
            process.StandardInput.Close();
            if (!process.WaitForExit(3000)) process.Kill();
        }
        catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception or IOException)
        {
            // already gone
        }
        process.Dispose();
        process = null;
    }
}
