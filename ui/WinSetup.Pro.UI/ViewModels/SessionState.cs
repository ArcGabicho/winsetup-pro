using System.Collections.Generic;
using WinSetup.Pro.UI.Models;

namespace WinSetup.Pro.UI.ViewModels;

/// <summary>Carries the wizard's choices between pages. Not persisted.</summary>
public sealed class SessionState
{
    public string? Profile { get; set; }
    public List<string> SelectedComponentIds { get; set; } = new();
    public bool DryRun { get; set; }
    public PlanResult? Plan { get; set; }
    public RunEvent? LastSummary { get; set; }

    public object BuildApplyPayload() => Profile is not null && SelectedComponentIds.Count == 0
        ? new { profile = Profile }
        : new { components = SelectedComponentIds };

    public object BuildPlanPayload() => Profile is not null && SelectedComponentIds.Count == 0
        ? new { profile = Profile }
        : new { profile = Profile, components = SelectedComponentIds };
}
