using System;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace WinSetup.Pro.UI;

/// <summary>Swaps the palette brushes in Application.Resources. Light + Dark.</summary>
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
        void Set(string key, string hex) => r[key] = new SolidColorBrush(
            (Color)ColorConverter.ConvertFromString(hex));

        if (dark)
        {
            Set("Bg", "#1B1D22");
            Set("BgAlt", "#23262D");
            Set("Card", "#2A2E37");
            Set("Border", "#3A3F4B");
            Set("Fg", "#E8EAED");
            Set("FgMuted", "#9AA0AA");
            Set("Sidebar", "#15171B");
            Set("SidebarFg", "#C9CDD4");
        }
        else
        {
            Set("Bg", "#F5F6F8");
            Set("BgAlt", "#FFFFFF");
            Set("Card", "#FFFFFF");
            Set("Border", "#E1E4E8");
            Set("Fg", "#1F2328");
            Set("FgMuted", "#656D76");
            Set("Sidebar", "#1F2328");
            Set("SidebarFg", "#D0D4DA");
        }
        Set("Accent", "#3B82F6");
        Set("AccentFg", "#FFFFFF");
        Set("Ok", "#22A06B");
        Set("Warn", "#D98A00");
        Set("Bad", "#D1493F");
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
