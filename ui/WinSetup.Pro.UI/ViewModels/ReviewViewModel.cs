using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using WinSetup.Pro.UI.Models;
using WinSetup.Pro.UI.Mvvm;

namespace WinSetup.Pro.UI.ViewModels;

public sealed class ReviewViewModel : ViewModelBase
{
    private readonly MainViewModel _main;

    public ReviewViewModel(MainViewModel main)
    {
        _main = main;
        BackCommand = new RelayCommand(() => _ = _main.GoAsync(Page.Components));
        ApplyCommand = new RelayCommand(Apply, () => Plan is not null);
        RestartElevatedCommand = new RelayCommand(() => _main.Elevation.RestartElevated(BuildForwardArgs()));
    }

    public PlanResult? Plan { get; private set; }
    public ObservableCollection<PlanChange> Installs { get; } = new();
    public ObservableCollection<PlanChange> Configures { get; } = new();
    public ObservableCollection<PlanChange> Skips { get; } = new();
    public ObservableCollection<PlanBackup> Backups { get; } = new();
    public ObservableCollection<string> Preserve { get; } = new();
    public ObservableCollection<string> AdminNeeded { get; } = new();

    public int ChangeCount => Installs.Count + Configures.Count;
    public bool NeedsElevation => AdminNeeded.Count > 0 && !_main.Elevation.IsElevated;
    public bool DryRun
    {
        get => _main.Session.DryRun;
        set { _main.Session.DryRun = value; OnPropertyChanged(); }
    }

    public RelayCommand BackCommand { get; }
    public RelayCommand ApplyCommand { get; }
    public RelayCommand RestartElevatedCommand { get; }

    public override async Task OnActivatedAsync()
    {
        IsBusy = true; Error = null;
        try
        {
            Installs.Clear(); Configures.Clear(); Skips.Clear();
            Backups.Clear(); Preserve.Clear(); AdminNeeded.Clear();

            Plan = await _main.Engine.GetDataAsync<PlanResult>("plan", _main.Session.BuildPlanPayload());
            _main.Session.Plan = Plan;
            if (Plan is null) return;

            foreach (var c in Plan.Changes)
            {
                if (c.Action.Contains("install")) Installs.Add(c);
                else if (c.Action.Contains("configure")) Configures.Add(c);
                else Skips.Add(c);
            }
            foreach (var b in Plan.Backups) Backups.Add(b);
            foreach (var s in Plan.Preserve) Preserve.Add(s);
            foreach (var a in Plan.RequiresAdmin) AdminNeeded.Add(a);

            OnPropertyChanged(nameof(Plan));
            OnPropertyChanged(nameof(ChangeCount));
            OnPropertyChanged(nameof(NeedsElevation));
            OnPropertyChanged(nameof(DryRun));
            ApplyCommand.RaiseCanExecuteChanged();
        }
        catch (System.Exception ex) { Error = ex.Message; }
        finally { IsBusy = false; }
    }

    private void Apply()
    {
        if (_main.Settings.Current.ConfirmBeforeChanges && !_main.Session.DryRun)
        {
            var msg = $"{ChangeCount} change(s) will be applied.\n\n" +
                      (Backups.Count > 0 ? "Existing configuration files will be backed up first.\n" : "") +
                      "No passwords or secrets are stored by WinSetup Pro.\n\nContinue?";
            if (MessageBox.Show(msg, "Configure workstation", MessageBoxButton.OKCancel,
                    MessageBoxImage.Question) != MessageBoxResult.OK)
                return;
        }
        _ = _main.GoAsync(Page.Run);
    }

    private string[] BuildForwardArgs()
    {
        var args = new System.Collections.Generic.List<string> { "--gui" };
        if (_main.Session.Profile is { } p) { args.Add("--profile"); args.Add(p); }
        if (_main.Session.DryRun) args.Add("--dry-run");
        return args.ToArray();
    }
}
