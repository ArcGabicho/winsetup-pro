using System.Threading.Tasks;
using WinSetup.Pro.UI.Models;
using WinSetup.Pro.UI.Mvvm;

namespace WinSetup.Pro.UI.ViewModels;

public sealed class ResultViewModel : ViewModelBase
{
    private readonly MainViewModel _main;

    public ResultViewModel(MainViewModel main)
    {
        _main = main;
        DoneCommand = new RelayCommand(() => { _main.Session.Plan = null; _ = _main.GoAsync(Page.Dashboard); });
        RetryCommand = new RelayCommand(() => _ = _main.GoAsync(Page.Run), () => HasFailures);
        ResumeLaterCommand = new RelayCommand(() => _ = _main.GoAsync(Page.Dashboard), () => HasFailures);
        OpenLogsCommand = new RelayCommand(OpenLogs);
    }

    public RunEvent? Summary => _main.Session.LastSummary;
    public bool HasFailures => Summary is { Failed: > 0 };
    public bool DryRun => _main.Session.DryRun;

    public string Headline => Summary switch
    {
        null => "Done",
        { Aborted: true } => "Configuration stopped",
        { Failed: > 0 } => "Configuration completed with warnings",
        _ when DryRun => "Preview complete - no changes were made",
        _ => "Workstation configured",
    };

    public RelayCommand DoneCommand { get; }
    public RelayCommand RetryCommand { get; }
    public RelayCommand ResumeLaterCommand { get; }
    public RelayCommand OpenLogsCommand { get; }

    public override Task OnActivatedAsync()
    {
        OnPropertyChanged(nameof(Summary));
        OnPropertyChanged(nameof(Headline));
        OnPropertyChanged(nameof(HasFailures));
        OnPropertyChanged(nameof(DryRun));
        RetryCommand.RaiseCanExecuteChanged();
        ResumeLaterCommand.RaiseCanExecuteChanged();
        return Task.CompletedTask;
    }

    private void OpenLogs()
    {
        var logs = System.IO.Path.Combine(_main.Engine.RepoRoot, "logs");
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(logs) { UseShellExecute = true }); }
        catch { /* ignore */ }
    }
}
