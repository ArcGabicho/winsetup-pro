using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace WinSetup.Pro.UI.Views;

public sealed class BoolToVis : IValueConverter
{
    public static readonly BoolToVis Instance = new();
    public object Convert(object? v, Type t, object? p, CultureInfo c)
        => v is true ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object? v, Type t, object? p, CultureInfo c) => Binding.DoNothing;
}

public sealed class NullToVis : IValueConverter
{
    public static readonly NullToVis Instance = new();
    public object Convert(object? v, Type t, object? p, CultureInfo c)
        => string.IsNullOrEmpty(v as string) ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object? v, Type t, object? p, CultureInfo c) => Binding.DoNothing;
}

public sealed class InverseBoolToVis : IValueConverter
{
    public static readonly InverseBoolToVis Instance = new();
    public object Convert(object? v, Type t, object? p, CultureInfo c)
        => v is true ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object? v, Type t, object? p, CultureInfo c) => Binding.DoNothing;
}

public sealed class EnumMatch : IValueConverter
{
    public static readonly EnumMatch Instance = new();
    public object Convert(object? v, Type t, object? p, CultureInfo c)
        => v?.ToString() == p?.ToString();
    public object ConvertBack(object? v, Type t, object? p, CultureInfo c) => Binding.DoNothing;
}

public sealed class CountToVis : IValueConverter
{
    public static readonly CountToVis Instance = new();
    public object Convert(object? v, Type t, object? p, CultureInfo c)
        => v is int n && n > 0 ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object? v, Type t, object? p, CultureInfo c) => Binding.DoNothing;
}

/// <summary>Component / diagnostic state -> brush.</summary>
public sealed class StateToBrush : IValueConverter
{
    public static readonly StateToBrush Instance = new();
    public object Convert(object? v, Type t, object? p, CultureInfo c)
    {
        var key = (v as string) switch
        {
            "Installed" or "Configured" => "Ok",
            "NeedsConfiguration" => "Warn",
            "Missing" => "Accent",
            "RequiresAdministrator" => "Warn",
            _ => "FgMuted",
        };
        return Application.Current.TryFindResource(key) as Brush
               ?? new SolidColorBrush(Colors.Gray);
    }
    public object ConvertBack(object? v, Type t, object? p, CultureInfo c) => Binding.DoNothing;
}

public sealed class BoolToBrush : IValueConverter
{
    public static readonly BoolToBrush Instance = new();
    public object Convert(object? v, Type t, object? p, CultureInfo c)
        => Application.Current.TryFindResource(v is true ? "Ok" : "Bad") as Brush
           ?? new SolidColorBrush(Colors.Gray);
    public object ConvertBack(object? v, Type t, object? p, CultureInfo c) => Binding.DoNothing;
}
