using WinSetup.Pro.UI.Mvvm;
using WinSetup.Pro.UI.Services;

namespace WinSetup.Pro.UI.ViewModels;

public sealed class SettingsViewModel : ViewModelBase
{
    private readonly MainViewModel _main;
    private readonly AppSettings _s;

    public SettingsViewModel(MainViewModel main)
    {
        _main = main;
        _s = main.Settings.Current;
    }

    public string[] LogLevels { get; } = { "DEBUG", "INFO", "SUCCESS", "WARNING", "ERROR" };
    public string[] Appearances { get; } = { "System", "Light", "Dark" };

    public bool ConfirmBeforeChanges
    {
        get => _s.ConfirmBeforeChanges;
        set { _s.ConfirmBeforeChanges = value; OnPropertyChanged(); _main.Settings.Save(); }
    }
    public bool CreateBackups
    {
        get => _s.CreateBackups;
        set { _s.CreateBackups = value; OnPropertyChanged(); _main.Settings.Save(); }
    }
    public bool CheckForUpdates
    {
        get => _s.CheckForUpdates;
        set { _s.CheckForUpdates = value; OnPropertyChanged(); _main.Settings.Save(); }
    }
    public bool DeveloperDiagnostics
    {
        get => _s.DeveloperDiagnostics;
        set { _s.DeveloperDiagnostics = value; OnPropertyChanged(); _main.Settings.Save(); }
    }
    public string LogLevel
    {
        get => _s.LogLevel;
        set { _s.LogLevel = value; OnPropertyChanged(); _main.Settings.Save(); }
    }
    public string Appearance
    {
        get => _s.Appearance;
        set { _s.Appearance = value; OnPropertyChanged(); _main.Settings.Save(); ThemeManager.Apply(value); }
    }

    public string RepoRoot => _main.Engine.RepoRoot;
    public string PwshPath => _main.Engine.PwshPath;
}
