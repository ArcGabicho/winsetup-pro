using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace WinSetup.Pro.UI;

/// <summary>Swaps the palette brushes in Application.Resources. Windows 11 style,
/// light-blue by default.</summary>
public static class ThemeManager
{
    public static void Apply(string mode)
    {
        var dark = mode switch
        {
            "Dark" => true,
            "Light" => false,
            _ => IsSystemDark(),
        };

        var r = Application.Current.Resources;
        void Set(string key, string hex) => r[key] = Freeze(new SolidColorBrush(
            (Color)ColorConverter.ConvertFromString(hex)));

        if (dark)
        {
            Set("Bg", "#1F232B");
            Set("BgAlt", "#262B34");
            Set("Card", "#2A2F39");
            Set("Layer", "#2A2F39");
            Set("LayerHover", "#333945");
            Set("Border", "#3A4150");
            Set("BorderStrong", "#48505F");
            Set("Fg", "#F2F4F8");
            Set("FgMuted", "#A8B0BE");
            Set("FgFaint", "#7B8494");
            Set("Sidebar", "#23272F");
            Set("SidebarFg", "#C6CCD8");
            Set("AccentSubtle", "#1E3A54");
            Set("AccentSubtleHover", "#244566");
            Set("Track", "#3A4150");
        }
        else
        {
            Set("Bg", "#F4F7FB");
            Set("BgAlt", "#EEF3F9");
            Set("Card", "#FFFFFF");
            Set("Layer", "#FFFFFF");
            Set("LayerHover", "#F3F6FA");
            Set("Border", "#E4E9F1");
            Set("BorderStrong", "#CED6E2");
            Set("Fg", "#1A1F29");
            Set("FgMuted", "#5B6472");
            Set("FgFaint", "#8A93A3");
            Set("Sidebar", "#FFFFFF");
            Set("SidebarFg", "#3A4251");
            Set("AccentSubtle", "#E9F2FB");
            Set("AccentSubtleHover", "#DCEBF8");
            Set("Track", "#E6ECF4");
        }

        // Blue accent - Windows 11 default.
        Set("Accent", "#0067C0");
        Set("AccentHover", "#1A78C8");
        Set("AccentPressed", "#005BA6");
        Set("AccentFg", "#FFFFFF");
        Set("Ok", dark ? "#4CC38A" : "#0F7B0F");
        Set("Warn", dark ? "#E0A458" : "#9D5D00");
        Set("Bad", dark ? "#E06C60" : "#C42B1C");
    }

    private static Brush Freeze(SolidColorBrush b)
    {
        if (b.CanFreeze) b.Freeze();
        return b;
    }

    private static bool IsSystemDark()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return k?.GetValue("AppsUseLightTheme") is int v && v == 0;
        }
        catch { return false; }
    }
}
