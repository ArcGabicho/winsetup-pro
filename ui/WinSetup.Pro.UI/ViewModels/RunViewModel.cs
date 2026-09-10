using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using WinSetup.Pro.UI.Models;
using WinSetup.Pro.UI.Mvvm;

namespace WinSetup.Pro.UI.ViewModels;

public sealed class RunRow : ObservableObject
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    private string _status = "Pending";
    public string Status { get => _status; set => SetProperty(ref _status, value); }
    private string _glyph = "○";
    public string Glyph { get => _glyph; set => SetProperty(ref _glyph, value); }
}

public sealed class RunViewModel : ViewModelBase
{
    private readonly MainViewModel _main;
    private CancellationTokenSource? _cts;
    private bool _componentInFlight;

    public RunViewModel(MainViewModel main)
    {
        _main = main;
        CancelCommand = new RelayCommand(Cancel, () => _cts is { IsCancellationRequested: false } && !_componentInFlight);
        ViewLogsCommand = new RelayCommand(OpenLogs);
    }

    public ObservableCollection<RunRow> Rows { get; } = new();
    private readonly Dictionary<string, RunRow> _byId = new();

    private double _progress;
    public double Progress { get => _progress; set => SetProperty(ref _progress, value); }

    private string _currentText = "Preparing...";
    public string CurrentText { get => _currentText; set => SetProperty(ref _currentText, value); }

    private string _title = "Configuring workstation...";
    public string Title { get => _title; set => SetProperty(ref _title, value); }

    public RelayCommand CancelCommand { get; }
    public RelayCommand ViewLogsCommand { get; }

    public override async Task OnActivatedAsync()
    {
        Rows.Clear(); _byId.Clear();
        Progress = 0; Error = null;
        IsBusy = true;
        _cts = new CancellationTokenSource();

        var resuming = _main.CurrentPage == Page.Run && _main.Session.Plan is null && DashboardResumable();
        var verb = resuming ? "resume" : "apply";
        Title = _main.Session.DryRun ? "Previewing changes..." : (resuming ? "Resuming configuration..." : "Configuring workstation...");

        int total = 0, done = 0;
        try
        {
            await foreach (var e in _main.Engine.ApplyAsync(verb, resuming ? null : _main.Session.BuildApplyPayload(), _cts.Token))
            {
                switch (e.Type)
                {
                    case "plan_resolved":
                        total = e.Total > 0 ? e.Total : e.Components.Count;
                        foreach (var id in e.Components) AddRow(id, id);
                        break;

                    case "component_started":
                        _componentInFlight = true;
                        CancelCommand.RaiseCanExecuteChanged();
                        var r = AddRow(e.Component ?? "", e.Name ?? e.Component ?? "");
                        r.Status = "Working..."; r.Glyph = "⟳";
                        CurrentText = e.Name ?? e.Component ?? "";
                        break;

                    case "component_completed":
                        _componentInFlight = false;
                        CancelCommand.RaiseCanExecuteChanged();
                        done++;
                        var rc = AddRow(e.Component ?? "", e.Name ?? e.Component ?? "");
                        (rc.Status, rc.Glyph) = (e.Action) switch
                        {
                            "Installed" => ("Installed", "✓"),
                            "Configured" => ("Configured", "✓"),
                            "Skip" => ("Already installed", "↷"),
                            "SkipNoAdmin" => ("Skipped (needs admin)", "⚡"),
                            "AlreadyDone" => ("Already done", "↷"),
                            _ when e.Action?.StartsWith("DryRun:") == true => (e.Detail ?? "Would change", "◇"),
                            _ => (e.Detail ?? "Done", "✓"),
                        };
                        if (total > 0) Progress = 100.0 * done / total;
                        break;

                    case "component_failed":
                        _componentInFlight = false;
                        CancelCommand.RaiseCanExecuteChanged();
                        done++;
                        var rf = AddRow(e.Component ?? "", e.Name ?? e.Component ?? "");
                        rf.Status = e.Error ?? "Failed"; rf.Glyph = "✕";
                        if (total > 0) Progress = 100.0 * done / total;
                        break;

                    case "run_completed":
                        Progress = 100;
                        CurrentText = "Done";
                        _main.Session.LastSummary = e;
                        break;
                }
            }
        }
        catch (OperationCanceledException) { CurrentText = "Cancelled."; }
        catch (Exception ex) { Error = ex.Message; }
        finally
        {
            IsBusy = false;
            _componentInFlight = false;
            CancelCommand.RaiseCanExecuteChanged();
        }

        if (Error is null) await _main.GoAsync(Page.Result);
    }

    private bool DashboardResumable() => _main.Dashboard.Journal is { Resumable: true };

    private RunRow AddRow(string id, string name)
    {
        if (_byId.TryGetValue(id, out var existing)) return existing;
        var row = new RunRow { Id = id, Name = name };
        _byId[id] = row;
        Rows.Add(row);
        return row;
    }

    private void Cancel()
    {
        if (_componentInFlight)
        {
            MessageBox.Show("The current operation cannot be safely cancelled.\nIt will stop after this component finishes.",
                "WinSetup Pro", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        _cts?.Cancel();
    }

    private void OpenLogs()
    {
        var logs = System.IO.Path.Combine(_main.Engine.RepoRoot, "logs");
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(logs) { UseShellExecute = true }); }
        catch { /* ignore */ }
    }
}
