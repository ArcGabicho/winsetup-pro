using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinSetup.Pro.UI.Services;

public sealed class AppSettings
{
    [JsonPropertyName("confirmBeforeChanges")] public bool ConfirmBeforeChanges { get; set; } = true;
    [JsonPropertyName("createBackups")] public bool CreateBackups { get; set; } = true;
    [JsonPropertyName("checkForUpdates")] public bool CheckForUpdates { get; set; } = true;
    [JsonPropertyName("logLevel")] public string LogLevel { get; set; } = "INFO";
    [JsonPropertyName("appearance")] public string Appearance { get; set; } = "System";
    [JsonPropertyName("developerDiagnostics")] public bool DeveloperDiagnostics { get; set; }
}

public sealed class SettingsService
{
    private static readonly string Dir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WinSetupPro");
    private static readonly string File_ = Path.Combine(Dir, "settings.json");

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public AppSettings Current { get; private set; } = Load();

    private static AppSettings Load()
    {
        try
        {
            if (File.Exists(File_))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(File_)) ?? new AppSettings();
        }
        catch { /* corrupt / unreadable - fall back to defaults */ }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(File_, JsonSerializer.Serialize(Current, Json));
        }
        catch { /* best effort */ }
    }
}
