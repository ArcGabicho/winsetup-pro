using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using WinSetup.Pro.UI.Models;
using WinSetup.Pro.UI.Mvvm;

namespace WinSetup.Pro.UI.ViewModels;

public sealed class HistoryItem
{
    public string When { get; init; } = "";
    public string Title { get; init; } = "";
    public string Detail { get; init; } = "";
}

public sealed class HistoryViewModel : ViewModelBase
{
    private readonly MainViewModel _main;

    public HistoryViewModel(MainViewModel main)
    {
        _main = main;
        OpenLogsCommand = new RelayCommand(() =>
        {
            var logs = Path.Combine(_main.Engine.RepoRoot, "logs");
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(logs) { UseShellExecute = true }); }
            catch { }
        });
    }

    public ObservableCollection<HistoryItem> Items { get; } = new();
    public RelayCommand OpenLogsCommand { get; }

    public override async Task OnActivatedAsync()
    {
        IsBusy = true; Error = null;
        try
        {
            Items.Clear();

            var journal = await _main.Engine.GetDataAsync<JournalInfo>("journal");
            if (journal is not null)
            {
                var status = journal.Completed
                    ? (journal.Counts.Failed > 0 ? "Completed with warnings" : "Completed")
                    : "Incomplete";
                Items.Add(new HistoryItem
                {
                    When = FormatUtc(journal.UpdatedUtc),
                    Title = $"{journal.Profile ?? "Custom"} - {status}",
                    Detail = $"{journal.Counts.Completed} done, {journal.Counts.Pending} pending, {journal.Counts.Failed} failed",
                });
            }

            var logsDir = Path.Combine(_main.Engine.RepoRoot, "logs");
            if (Directory.Exists(logsDir))
            {
                foreach (var f in new DirectoryInfo(logsDir).GetFiles("*.log")
                             .OrderByDescending(f => f.LastWriteTime).Take(20))
                {
                    Items.Add(new HistoryItem
                    {
                        When = f.LastWriteTime.ToString("g"),
                        Title = f.Name,
                        Detail = $"{f.Length / 1024.0:0.#} KB",
                    });
                }
            }
        }
        catch (Exception ex) { Error = ex.Message; }
        finally { IsBusy = false; }
    }

    private static string FormatUtc(string? iso)
        => DateTime.TryParse(iso, out var dt) ? dt.ToLocalTime().ToString("g") : (iso ?? "");
}
