using System;
using System.Windows;
using System.Windows.Threading;
using WinSetup.Pro.UI.Services;
using WinSetup.Pro.UI.ViewModels;

namespace WinSetup.Pro.UI;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        string? profile = null;
        bool dryRun = false;
        for (int i = 0; i < e.Args.Length; i++)
        {
            var a = e.Args[i].ToLowerInvariant();
            if (a is "--profile" or "-profile" && i + 1 < e.Args.Length) profile = e.Args[++i];
            else if (a is "--dry-run" or "--dryrun") dryRun = true;
        }

        var settings = new SettingsService();
        ThemeManager.Apply(settings.Current.Appearance);

        DispatcherUnhandledException += OnUnhandled;

        try
        {
            var engine = new EngineClient();
            var elevation = new ElevationService();
            var vm = new MainViewModel(engine, elevation, settings, profile, dryRun);
            var window = new MainWindow { DataContext = vm };
            window.Show();
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                ex.Message + "\n\nWinSetup Pro could not locate the engine. Run it via `winsetup`, " +
                "or set the WINSETUP_HOME environment variable to your checkout.",
                "WinSetup Pro", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(2);
        }
    }

    private void OnUnhandled(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        MessageBox.Show(e.Exception.Message, "WinSetup Pro - unexpected error",
            MessageBoxButton.OK, MessageBoxImage.Warning);
        e.Handled = true;
    }
}
