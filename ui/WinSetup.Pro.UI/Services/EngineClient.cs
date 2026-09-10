using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using WinSetup.Pro.UI.Models;

namespace WinSetup.Pro.UI.Services;

/// <summary>
/// The only bridge to the engine. Spawns `pwsh -File scripts\winsetup-api.ps1`
/// and parses its JSON. Contains NO setup logic of its own.
/// </summary>
public sealed class EngineClient
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
    };

    public string RepoRoot { get; }
    public string PwshPath { get; }
    private string ApiScript => Path.Combine(RepoRoot, "scripts", "winsetup-api.ps1");

    public EngineClient(string? repoRoot = null, string? pwshPath = null)
    {
        RepoRoot = repoRoot ?? LocateRepoRoot();
        PwshPath = pwshPath ?? LocatePwsh();
    }

    // ---- discovery -------------------------------------------------------

    private static string LocateRepoRoot()
    {
        var env = Environment.GetEnvironmentVariable("WINSETUP_HOME");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(Path.Combine(env, "WinSetup.ps1")))
            return Path.GetFullPath(env);

        var dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8 && dir is not null; i++)
        {
            if (File.Exists(Path.Combine(dir, "WinSetup.ps1")) &&
                Directory.Exists(Path.Combine(dir, "modules", "Core")))
                return dir;
            dir = Path.GetDirectoryName(dir.TrimEnd(Path.DirectorySeparatorChar));
        }
        throw new InvalidOperationException(
            "Could not find the WinSetup Pro repository. Set WINSETUP_HOME to the checkout path.");
    }

    private static string LocatePwsh()
    {
        foreach (var candidate in new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe"),
            @"C:\Program Files\PowerShell\7\pwsh.exe",
        })
            if (File.Exists(candidate)) return candidate;

        foreach (var p in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
        {
            try
            {
                if (string.IsNullOrWhiteSpace(p)) continue;
                var exe = Path.Combine(p.Trim(), "pwsh.exe");
                if (File.Exists(exe)) return exe;
            }
            catch { /* malformed PATH entry */ }
        }
        return "powershell.exe"; // last resort (5.1)
    }

    // ---- read verbs ---------------------------------------------------

    public async Task<ApiEnvelope> InvokeAsync(string verb, object? payload = null, string? path = null,
        CancellationToken ct = default)
    {
        string? payloadFile = null;
        var args = new List<string> { "-NoLogo", "-NoProfile", "-File", ApiScript, "-Verb", verb, "-Root", RepoRoot };
        if (payload is not null)
        {
            payloadFile = Path.Combine(Path.GetTempPath(), $"wsapi-{Guid.NewGuid():N}.json");
            await File.WriteAllTextAsync(payloadFile, JsonSerializer.Serialize(payload), ct);
            args.Add("-JsonFile"); args.Add(payloadFile);
        }
        if (path is not null) { args.Add("-Path"); args.Add(path); }

        try
        {
            var (stdout, _, _) = await RunAsync(args, ct);
            var line = LastJsonLine(stdout);
            var env = JsonSerializer.Deserialize<ApiEnvelope>(line, Json)
                      ?? throw new InvalidOperationException("Empty response from the engine.");
            return env;
        }
        finally
        {
            if (payloadFile is not null) TryDelete(payloadFile);
        }
    }

    public async Task<T?> GetDataAsync<T>(string verb, object? payload = null, string? path = null,
        CancellationToken ct = default)
    {
        var env = await InvokeAsync(verb, payload, path, ct);
        if (!env.Ok) throw new EngineException(env.Error ?? "The engine reported an error.");
        if (env.Data.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return default;
        return env.Data.Deserialize<T>(Json);
    }

    // ---- apply / resume (streaming) ---------------------------------------

    public async IAsyncEnumerable<RunEvent> ApplyAsync(string verb, object? payload,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        string? payloadFile = null;
        var args = new List<string> { "-NoLogo", "-NoProfile", "-File", ApiScript, "-Verb", verb, "-Root", RepoRoot };
        if (payload is not null)
        {
            payloadFile = Path.Combine(Path.GetTempPath(), $"wsapi-{Guid.NewGuid():N}.json");
            await File.WriteAllTextAsync(payloadFile, JsonSerializer.Serialize(payload), ct);
            args.Add("-JsonFile"); args.Add(payloadFile);
        }

        var psi = NewStartInfo(args);
        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        proc.Start();

        try
        {
            string? line;
            while ((line = await proc.StandardOutput.ReadLineAsync(ct)) is not null)
            {
                line = line.Trim();
                if (line.Length == 0 || line[0] != '{') continue;
                RunEvent? evt = null;
                try { evt = JsonSerializer.Deserialize<RunEvent>(line, Json); }
                catch (JsonException) { /* not an event line - ignore */ }
                if (evt is not null && !string.IsNullOrEmpty(evt.Type)) yield return evt;
            }
            await proc.WaitForExitAsync(ct);
        }
        finally
        {
            if (!proc.HasExited) { try { proc.Kill(true); } catch { } }
            if (payloadFile is not null) TryDelete(payloadFile);
        }
    }

    // ---- process plumbing ---------------------------------------------

    private ProcessStartInfo NewStartInfo(IEnumerable<string> args)
    {
        var psi = new ProcessStartInfo
        {
            FileName = PwshPath,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = RepoRoot,
            StandardOutputEncoding = new UTF8Encoding(false),
            StandardErrorEncoding = new UTF8Encoding(false),
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        return psi;
    }

    private async Task<(string stdout, string stderr, int exit)> RunAsync(
        IEnumerable<string> args, CancellationToken ct)
    {
        var psi = NewStartInfo(args);
        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var outBuf = new StringBuilder();
        var errBuf = new StringBuilder();
        proc.OutputDataReceived += (_, e) => { if (e.Data is not null) outBuf.AppendLine(e.Data); };
        proc.ErrorDataReceived += (_, e) => { if (e.Data is not null) errBuf.AppendLine(e.Data); };
        proc.Start();
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();
        try
        {
            await proc.WaitForExitAsync(ct);
        }
        catch (OperationCanceledException)
        {
            try { proc.Kill(true); } catch { }
            throw;
        }
        return (outBuf.ToString(), errBuf.ToString(), proc.ExitCode);
    }

    private static string LastJsonLine(string stdout)
    {
        var lines = stdout.Split('\n');
        for (int i = lines.Length - 1; i >= 0; i--)
        {
            var t = lines[i].Trim();
            if (t.Length > 1 && t[0] == '{') return t;
        }
        throw new InvalidOperationException("The engine produced no JSON output.");
    }

    private static void TryDelete(string file)
    {
        try { if (File.Exists(file)) File.Delete(file); } catch { }
    }
}

public sealed class EngineException(string message) : Exception(message);
