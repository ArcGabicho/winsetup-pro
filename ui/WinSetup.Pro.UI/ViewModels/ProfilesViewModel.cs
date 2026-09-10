using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using WinSetup.Pro.UI.Models;
using WinSetup.Pro.UI.Mvvm;

namespace WinSetup.Pro.UI.ViewModels;

public sealed class ProfilesViewModel : ViewModelBase
{
    private readonly MainViewModel _main;

    public ProfilesViewModel(MainViewModel main)
    {
        _main = main;
        BackCommand = new RelayCommand(() => _ = _main.GoAsync(Page.Dashboard));
        ContinueCommand = new RelayCommand(Continue, () => Selected is not null);
    }

    public ObservableCollection<ProfileInfo> Profiles { get; } = new();

    private ProfileInfo? _selected;
    public ProfileInfo? Selected
    {
        get => _selected;
        set { if (SetProperty(ref _selected, value)) ContinueCommand.RaiseCanExecuteChanged(); }
    }

    public RelayCommand BackCommand { get; }
    public RelayCommand ContinueCommand { get; }

    public override async Task OnActivatedAsync()
    {
        IsBusy = true; Error = null;
        try
        {
            Profiles.Clear();
            var list = await _main.Engine.GetDataAsync<ProfileInfo[]>("profiles") ?? System.Array.Empty<ProfileInfo>();
            foreach (var p in list) Profiles.Add(p);
            Selected = Profiles.FirstOrDefault(p => p.Name == _main.Session.Profile) ?? Profiles.FirstOrDefault();
        }
        catch (System.Exception ex) { Error = ex.Message; }
        finally { IsBusy = false; }
    }

    private void Continue()
    {
        if (Selected is null) return;
        _main.Session.Profile = Selected.Name;
        _main.Session.SelectedComponentIds.Clear();
        _ = _main.GoAsync(Page.Components);
    }
}
