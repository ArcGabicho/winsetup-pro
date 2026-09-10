using System;
using System.Threading.Tasks;
using WinSetup.Pro.UI.Mvvm;
using WinSetup.Pro.UI.Services;

namespace WinSetup.Pro.UI.ViewModels;

public enum Page { Dashboard, Profiles, Components, Review, Run, Result, Diagnostics, History, Settings }

public sealed class MainViewModel : ObservableObject
{
    public EngineClient Engine { get; }
    public ElevationService Elevation { get; }
    public SettingsService Settings { get; }
    public SessionState Session { get; } = new();

    public DashboardViewModel Dashboard { get; }
    public ProfilesViewModel Profiles { get; }
    public ComponentsViewModel Components { get; }
    public ReviewViewModel Review { get; }
    public RunViewModel Run { get; }
    public ResultViewModel Result { get; }
    public DiagnosticsViewModel Diagnostics { get; }
    public HistoryViewModel History { get; }
    public SettingsViewModel SettingsPage { get; }

    private ViewModelBase _current = null!;
    public ViewModelBase Current { get => _current; private set => SetProperty(ref _current, value); }

    private Page _page;
    public Page CurrentPage { get => _page; private set { if (SetProperty(ref _page, value)) OnPropertyChanged(nameof(IsWizard)); } }
    public bool IsWizard => _page is Page.Profiles or Page.Components or Page.Review or Page.Run or Page.Result;

    public string HostBadge { get; }

    public RelayCommand<Page> NavigateCommand { get; }

    public MainViewModel(EngineClient engine, ElevationService elevation, SettingsService settings,
        string? preselectProfile, bool preselectDryRun)
    {
        Engine = engine;
        Elevation = elevation;
        Settings = settings;
        HostBadge = elevation.IsElevated ? "Administrator" : "Standard user";

        Dashboard = new DashboardViewModel(this);
        Profiles = new ProfilesViewModel(this);
        Components = new ComponentsViewModel(this);
        Review = new ReviewViewModel(this);
        Run = new RunViewModel(this);
        Result = new ResultViewModel(this);
        Diagnostics = new DiagnosticsViewModel(this);
        History = new HistoryViewModel(this);
        SettingsPage = new SettingsViewModel(this);

        NavigateCommand = new RelayCommand<Page>(p => _ = GoAsync(p));

        Session.DryRun = preselectDryRun;
        if (!string.IsNullOrWhiteSpace(preselectProfile))
        {
            Session.Profile = preselectProfile;
            _ = GoAsync(Page.Components);
        }
        else
        {
            _ = GoAsync(Page.Dashboard);
        }
    }

    public async Task GoAsync(Page page)
    {
        Current = page switch
        {
            Page.Dashboard => Dashboard,
            Page.Profiles => Profiles,
            Page.Components => Components,
            Page.Review => Review,
            Page.Run => Run,
            Page.Result => Result,
            Page.Diagnostics => Diagnostics,
            Page.History => History,
            Page.Settings => SettingsPage,
            _ => Dashboard,
        };
        CurrentPage = page;
        try { await Current.OnActivatedAsync(); }
        catch (Exception ex) { Current.Error = ex.Message; }
    }
}

public sealed class RelayCommand<T> : System.Windows.Input.ICommand
{
    private readonly Action<T> _execute;
    public RelayCommand(Action<T> execute) => _execute = execute;
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter)
    {
        if (parameter is T t) _execute(t);
        else if (parameter is string s && Enum.TryParse(typeof(T), s, out var v)) _execute((T)v!);
    }
    public event EventHandler? CanExecuteChanged { add { } remove { } }
}
