using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using WinSetup.Pro.UI.Models;
using WinSetup.Pro.UI.Mvvm;

namespace WinSetup.Pro.UI.ViewModels;

public sealed class ComponentRow : ObservableObject
{
    public required ComponentInfo Info { get; init; }
    private bool _selected;
    public bool Selected { get => _selected; set => SetProperty(ref _selected, value); }

    public string Id => Info.Id;
    public string Name => Info.Name;
    public string? Description => Info.Description;
    public bool RequiresAdmin => Info.RequiresAdmin;
    public string StateLabel => Info.State switch
    {
        "Installed" => "Installed",
        "NeedsConfiguration" => "Needs configuration",
        "RequiresAdministrator" => "Requires administrator",
        "Missing" => "Missing",
        _ => "Unknown",
    };
    public string StateGlyph => Info.State switch
    {
        "Installed" => "✓",
        "NeedsConfiguration" => "⚠",
        "RequiresAdministrator" => "⚡",
        "Missing" => "→",
        _ => "—",
    };
}

public sealed class CategoryGroup
{
    public string Name { get; init; } = "";
    public ObservableCollection<ComponentRow> Rows { get; } = new();
}

public sealed class ComponentsViewModel : ViewModelBase
{
    private readonly MainViewModel _main;

    public ComponentsViewModel(MainViewModel main)
    {
        _main = main;
        BackCommand = new RelayCommand(() =>
            _ = _main.GoAsync(_main.Session.Profile is null ? Page.Dashboard : Page.Profiles));
        ContinueCommand = new RelayCommand(Continue, () => SelectedCount > 0);
    }

    public ObservableCollection<CategoryGroup> Groups { get; } = new();
    public string Title => _main.Session.Profile is { } p ? $"{p} - customise components" : "Custom workstation";
    public int SelectedCount => Groups.SelectMany(g => g.Rows).Count(r => r.Selected);

    public RelayCommand BackCommand { get; }
    public RelayCommand ContinueCommand { get; }

    public override async Task OnActivatedAsync()
    {
        IsBusy = true; Error = null;
        try
        {
            Groups.Clear();
            object? payload = _main.Session.Profile is { } p ? new { profile = p } : null;
            var list = await _main.Engine.GetDataAsync<ComponentInfo[]>("components", payload)
                       ?? System.Array.Empty<ComponentInfo>();

            var priorSelection = _main.Session.SelectedComponentIds.Count > 0
                ? new HashSet<string>(_main.Session.SelectedComponentIds)
                : null;

            foreach (var byCat in list.GroupBy(c => c.Category).OrderBy(g => g.Key))
            {
                var group = new CategoryGroup { Name = byCat.Key };
                foreach (var c in byCat.OrderBy(c => c.Name))
                {
                    var row = new ComponentRow
                    {
                        Info = c,
                        Selected = priorSelection?.Contains(c.Id) ?? c.Selected,
                    };
                    row.PropertyChanged += (_, e) =>
                    {
                        if (e.PropertyName == nameof(ComponentRow.Selected))
                        {
                            OnPropertyChanged(nameof(SelectedCount));
                            ContinueCommand.RaiseCanExecuteChanged();
                        }
                    };
                    group.Rows.Add(row);
                }
                Groups.Add(group);
            }
            OnPropertyChanged(nameof(Title));
            OnPropertyChanged(nameof(SelectedCount));
            ContinueCommand.RaiseCanExecuteChanged();
        }
        catch (System.Exception ex) { Error = ex.Message; }
        finally { IsBusy = false; }
    }

    private void Continue()
    {
        _main.Session.SelectedComponentIds = Groups.SelectMany(g => g.Rows)
            .Where(r => r.Selected).Select(r => r.Id).ToList();
        _ = _main.GoAsync(Page.Review);
    }
}
