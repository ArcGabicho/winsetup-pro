using System.Threading.Tasks;
using WinSetup.Pro.UI.Models;
using WinSetup.Pro.UI.Mvvm;

namespace WinSetup.Pro.UI.ViewModels;

public sealed class DashboardViewModel : ViewModelBase
{
    private readonly MainViewModel _main;

    public DashboardViewModel(MainViewModel main)
    {
        _main = main;
        StartCommand = new RelayCommand(() => _ = _main.GoAsync(Page.Profiles));
        CustomCommand = new RelayCommand(() => { _main.Session.Profile = null; _ = _main.GoAsync(Page.Components); });
        ResumeCommand = new RelayCommand(() => _ = _main.GoAsync(Page.Run), () => Journal is { Resumable: true });
        DismissResumeCommand = new RelayCommand(() => { ShowResume = false; OnPropertyChanged(nameof(ShowResume)); });
    }

    public SystemInfo? System { get; private set; }
    public JournalInfo? Journal { get; private set; }
    public bool ShowResume { get; private set; }

    public RelayCommand StartCommand { get; }
    public RelayCommand CustomCommand { get; }
    public RelayCommand ResumeCommand { get; }
    public RelayCommand DismissResumeCommand { get; }

    public override async Task OnActivatedAsync()
    {
        IsBusy = true; Error = null;
        try
        {
            System = await _main.Engine.GetDataAsync<SystemInfo>("system");
            Journal = await _main.Engine.GetDataAsync<JournalInfo>("journal");
            ShowResume = Journal is { Resumable: true };
            OnPropertyChanged(nameof(System));
            OnPropertyChanged(nameof(Journal));
            OnPropertyChanged(nameof(ShowResume));
            ResumeCommand.RaiseCanExecuteChanged();
        }
        catch (System.Exception ex) { Error = ex.Message; }
        finally { IsBusy = false; }
    }
}
