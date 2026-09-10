using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows;

namespace WinSetup.Pro.UI.Services;

public sealed class ElevationService
{
    public bool IsElevated { get; } = ComputeElevated();

    private static bool ComputeElevated()
    {
        try
        {
            using var id = WindowsIdentity.GetCurrent();
            return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch { return false; }
    }

    /// <summary>Relaunch this exe elevated (UAC prompt) and shut the current instance down.</summary>
    public void RestartElevated(string[]? forwardArgs = null)
    {
        var exe = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName;
        if (exe is null) return;

        var psi = new ProcessStartInfo
        {
            FileName = exe,
            UseShellExecute = true,
            Verb = "runas",
            WorkingDirectory = AppContext.BaseDirectory,
        };
        if (forwardArgs is not null)
            foreach (var a in forwardArgs) psi.ArgumentList.Add(a);

        try
        {
            Process.Start(psi);
            Application.Current.Shutdown();
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // user declined the UAC prompt - stay where we are
        }
    }
}
