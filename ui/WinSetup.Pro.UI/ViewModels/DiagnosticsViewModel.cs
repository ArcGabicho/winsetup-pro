using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using WinSetup.Pro.UI.Models;
using WinSetup.Pro.UI.Mvvm;

namespace WinSetup.Pro.UI.ViewModels;

public sealed class DiagnosticsViewModel : ViewModelBase
{
    private readonly MainViewModel _main;

    public DiagnosticsViewModel(MainViewModel main)
    {
        _main = main;
        RefreshCommand = new RelayCommand(() => _ = OnActivatedAsync());
    }

    public ObservableCollection<DiagnosticCheck> Checks { get; } = new();
    public int Failing => Checks.Count(c => !c.Ok);
    public RelayCommand RefreshCommand { get; }

    public override async Task OnActivatedAsync()
    {
        IsBusy = true; Error = null;
        try
        {
            Checks.Clear();
            var list = await _main.Engine.GetDataAsync<DiagnosticCheck[]>("diagnose")
                       ?? System.Array.Empty<DiagnosticCheck>();
            foreach (var c in list) Checks.Add(c);
            OnPropertyChanged(nameof(Failing));
        }
        catch (System.Exception ex) { Error = ex.Message; }
        finally { IsBusy = false; }
    }
}
