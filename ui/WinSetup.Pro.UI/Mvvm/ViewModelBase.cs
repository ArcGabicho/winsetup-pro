using System.Threading.Tasks;

namespace WinSetup.Pro.UI.Mvvm;

public abstract class ViewModelBase : ObservableObject
{
    private bool _isBusy;
    public bool IsBusy { get => _isBusy; set => SetProperty(ref _isBusy, value); }

    private string? _error;
    public string? Error { get => _error; set => SetProperty(ref _error, value); }

    /// <summary>Called by the shell each time this VM becomes the active page.</summary>
    public virtual Task OnActivatedAsync() => Task.CompletedTask;
}
