using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinSetup.Pro.UI.Models;

/// <summary>The envelope every read verb returns on stdout.</summary>
public sealed class ApiEnvelope
{
    [JsonPropertyName("apiVersion")] public int ApiVersion { get; set; }
    [JsonPropertyName("verb")] public string Verb { get; set; } = "";
    [JsonPropertyName("ok")] public bool Ok { get; set; }
    [JsonPropertyName("error")] public string? Error { get; set; }
    [JsonPropertyName("data")] public JsonElement Data { get; set; }
}

public sealed class SystemInfo
{
    [JsonPropertyName("OsCaption")] public string OsCaption { get; set; } = "";
    [JsonPropertyName("OsBuild")] public long OsBuild { get; set; }
    [JsonPropertyName("Architecture")] public string Architecture { get; set; } = "";
    [JsonPropertyName("PSVersion")] public string PsVersion { get; set; } = "";
    [JsonPropertyName("PSEdition")] public string PsEdition { get; set; } = "";
    [JsonPropertyName("IsAdmin")] public bool IsAdmin { get; set; }
    [JsonPropertyName("WingetPresent")] public bool WingetPresent { get; set; }
    [JsonPropertyName("WingetVersion")] public string? WingetVersion { get; set; }
    [JsonPropertyName("WslPresent")] public bool WslPresent { get; set; }
    [JsonPropertyName("FreeDiskGB")] public double? FreeDiskGb { get; set; }
    [JsonPropertyName("Hostname")] public string Hostname { get; set; } = "";
    [JsonPropertyName("User")] public string User { get; set; } = "";
    [JsonPropertyName("Internet")] public bool Internet { get; set; }
}

public sealed class DiagnosticCheck
{
    [JsonPropertyName("Name")] public string Name { get; set; } = "";
    [JsonPropertyName("Ok")] public bool Ok { get; set; }
    [JsonPropertyName("Detail")] public string Detail { get; set; } = "";
}

public sealed class ProfileInfo
{
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("description")] public string? Description { get; set; }
    [JsonPropertyName("componentCount")] public int ComponentCount { get; set; }
    [JsonPropertyName("components")] public List<string> Components { get; set; } = new();
    [JsonPropertyName("unknown")] public List<string> Unknown { get; set; } = new();
    [JsonPropertyName("compatible")] public bool Compatible { get; set; }
}

public sealed class ComponentInfo
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("category")] public string Category { get; set; } = "";
    [JsonPropertyName("description")] public string? Description { get; set; }
    [JsonPropertyName("requiresAdmin")] public bool RequiresAdmin { get; set; }
    [JsonPropertyName("critical")] public bool Critical { get; set; }
    [JsonPropertyName("dependsOn")] public List<string> DependsOn { get; set; } = new();
    [JsonPropertyName("selected")] public bool Selected { get; set; }
    [JsonPropertyName("state")] public string State { get; set; } = "Unknown";
    [JsonPropertyName("installed")] public bool Installed { get; set; }
    [JsonPropertyName("configured")] public bool Configured { get; set; }
    [JsonPropertyName("version")] public string? Version { get; set; }
    [JsonPropertyName("summary")] public string? Summary { get; set; }
}

public sealed class PlanChange
{
    [JsonPropertyName("component")] public string Component { get; set; } = "";
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("action")] public string Action { get; set; } = "";
    [JsonPropertyName("requiresAdmin")] public bool RequiresAdmin { get; set; }
}

public sealed class PlanBackup
{
    [JsonPropertyName("component")] public string Component { get; set; } = "";
    [JsonPropertyName("file")] public string File { get; set; } = "";
}

public sealed class PlanResult
{
    [JsonPropertyName("profile")] public string? Profile { get; set; }
    [JsonPropertyName("dryRun")] public bool DryRun { get; set; }
    [JsonPropertyName("changes")] public List<PlanChange> Changes { get; set; } = new();
    [JsonPropertyName("requiresAdmin")]
    [JsonConverter(typeof(StringListConverter))]
    public List<string> RequiresAdmin { get; set; } = new();
    [JsonPropertyName("backups")] public List<PlanBackup> Backups { get; set; } = new();
    [JsonPropertyName("preserve")]
    [JsonConverter(typeof(StringListConverter))]
    public List<string> Preserve { get; set; } = new();
    [JsonPropertyName("unknown")]
    [JsonConverter(typeof(StringListConverter))]
    public List<string> Unknown { get; set; } = new();
}

/// <summary>One line of the apply/resume NDJSON stream.</summary>
public sealed class RunEvent
{
    [JsonPropertyName("type")] public string Type { get; set; } = "";
    [JsonPropertyName("component")] public string? Component { get; set; }
    [JsonPropertyName("name")] public string? Name { get; set; }
    [JsonPropertyName("action")] public string? Action { get; set; }
    [JsonPropertyName("detail")] public string? Detail { get; set; }
    [JsonPropertyName("error")] public string? Error { get; set; }
    [JsonPropertyName("index")] public int Index { get; set; }
    [JsonPropertyName("total")] public int Total { get; set; }
    [JsonPropertyName("installed")] public int Installed { get; set; }
    [JsonPropertyName("configured")] public int Configured { get; set; }
    [JsonPropertyName("skipped")] public int Skipped { get; set; }
    [JsonPropertyName("failed")] public int Failed { get; set; }
    [JsonPropertyName("aborted")] public bool Aborted { get; set; }
    [JsonPropertyName("journalPath")] public string? JournalPath { get; set; }
    [JsonPropertyName("components")]
    [JsonConverter(typeof(StringListConverter))]
    public List<string> Components { get; set; } = new();
}

public sealed class JournalEntry
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("status")] public string Status { get; set; } = "";
    [JsonPropertyName("action")] public string? Action { get; set; }
    [JsonPropertyName("error")] public string? Error { get; set; }
}

public sealed class JournalCounts
{
    [JsonPropertyName("completed")] public int Completed { get; set; }
    [JsonPropertyName("pending")] public int Pending { get; set; }
    [JsonPropertyName("failed")] public int Failed { get; set; }
}

public sealed class JournalInfo
{
    [JsonPropertyName("profile")] public string? Profile { get; set; }
    [JsonPropertyName("dryRun")] public bool DryRun { get; set; }
    [JsonPropertyName("startedUtc")] public string? StartedUtc { get; set; }
    [JsonPropertyName("updatedUtc")] public string? UpdatedUtc { get; set; }
    [JsonPropertyName("completed")] public bool Completed { get; set; }
    [JsonPropertyName("counts")] public JournalCounts Counts { get; set; } = new();
    [JsonPropertyName("entries")] public List<JournalEntry> Entries { get; set; } = new();
    [JsonPropertyName("resumable")] public bool Resumable { get; set; }
}

/// <summary>Accepts a JSON string, a string array, or null - the engine's
/// ConvertTo-Json unwraps single-element arrays to a scalar.</summary>
public sealed class StringListConverter : JsonConverter<List<string>>
{
    public override List<string> Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions o)
    {
        var list = new List<string>();
        if (reader.TokenType == JsonTokenType.Null) return list;
        if (reader.TokenType == JsonTokenType.String) { list.Add(reader.GetString() ?? ""); return list; }
        if (reader.TokenType == JsonTokenType.StartArray)
        {
            while (reader.Read() && reader.TokenType != JsonTokenType.EndArray)
                if (reader.TokenType == JsonTokenType.String) list.Add(reader.GetString() ?? "");
        }
        return list;
    }

    public override void Write(Utf8JsonWriter writer, List<string> value, JsonSerializerOptions o)
    {
        writer.WriteStartArray();
        foreach (var s in value) writer.WriteStringValue(s);
        writer.WriteEndArray();
    }
}
