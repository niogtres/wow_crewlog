using System.Globalization;

namespace Crewlog.Client.Core.Lua;

/// <summary>A value from a SavedVariables file: nil, boolean, number, string or table. Nothing executable.</summary>
public abstract class LuaValue
{
    public static readonly LuaNil Nil = new();

    public virtual string? AsString() => null;
    public virtual double? AsNumber() => null;
    public virtual bool? AsBoolean() => null;
    public virtual LuaTable? AsTable() => null;

    public int? AsInt()
    {
        var n = AsNumber();
        if (n is null || double.IsNaN(n.Value) || n.Value is > int.MaxValue or < int.MinValue) return null;
        return (int)Math.Round(n.Value);
    }

    public long? AsLong()
    {
        var n = AsNumber();
        if (n is null || double.IsNaN(n.Value) || n.Value is > long.MaxValue or < long.MinValue) return null;
        return (long)Math.Round(n.Value);
    }

    public bool IsNil => this is LuaNil;
}

public sealed class LuaNil : LuaValue
{
    internal LuaNil() { }
    public override string ToString() => "nil";
}

public sealed class LuaBoolean(bool value) : LuaValue
{
    public bool Value { get; } = value;
    public override bool? AsBoolean() => Value;
    public override string ToString() => Value ? "true" : "false";
}

public sealed class LuaNumber(double value) : LuaValue
{
    public double Value { get; } = value;
    public override double? AsNumber() => Value;
    public override string ToString() => Value.ToString("R", CultureInfo.InvariantCulture);
}

public sealed class LuaString(string value) : LuaValue
{
    public string Value { get; } = value;
    public override string? AsString() => Value;
    public override string ToString() => Value;
}

/// <summary>
/// A Lua table split like Lua's own: a 1-based array part for positional values and a hash part keyed by
/// <see cref="string"/> or <see cref="double"/> (integral numeric keys outside the array part).
/// </summary>
public sealed class LuaTable : LuaValue
{
    private readonly List<LuaValue> _array = [];
    private readonly Dictionary<object, LuaValue> _hash = [];

    public override LuaTable AsTable() => this;

    /// <summary>Positional values, index 0 here is Lua index 1.</summary>
    public IReadOnlyList<LuaValue> Array => _array;

    /// <summary>Non-positional entries. Keys are <see cref="string"/> or <see cref="double"/>.</summary>
    public IReadOnlyDictionary<object, LuaValue> Hash => _hash;

    public int Count => _array.Count + _hash.Count;

    internal void AppendPositional(LuaValue v) => _array.Add(v);

    internal void Set(object key, LuaValue v)
    {
        if (key is double d && d == Math.Floor(d) && d == _array.Count + 1)
        {
            _array.Add(v);
            // An explicit [n] can make following hash entries contiguous; fold them in.
            while (_hash.Remove((double)(_array.Count + 1), out var next)) _array.Add(next);
            return;
        }
        _hash[key] = v;
    }

    public LuaValue this[string key] => _hash.TryGetValue(key, out var v) ? v : Nil;

    /// <summary>Lua-style 1-based lookup across array and hash parts.</summary>
    public LuaValue this[int index]
    {
        get
        {
            if (index >= 1 && index <= _array.Count) return _array[index - 1];
            return _hash.TryGetValue((double)index, out var v) ? v : Nil;
        }
    }

    /// <summary>All entries as (key, value), array part first with 1-based numeric keys.</summary>
    public IEnumerable<KeyValuePair<object, LuaValue>> Pairs()
    {
        for (var i = 0; i < _array.Count; i++) yield return new((double)(i + 1), _array[i]);
        foreach (var kv in _hash) yield return kv;
    }

    /// <summary>Entries whose keys are integral numbers, e.g. quest ids used as keys.</summary>
    public IEnumerable<KeyValuePair<int, LuaValue>> IntKeyed()
    {
        foreach (var (k, v) in Pairs())
            if (k is double d && d == Math.Floor(d) && d is >= int.MinValue and <= int.MaxValue)
                yield return new((int)d, v);
    }

    /// <summary>Entries whose keys are strings.</summary>
    public IEnumerable<KeyValuePair<string, LuaValue>> StringKeyed()
    {
        foreach (var (k, v) in _hash)
            if (k is string s) yield return new(s, v);
    }
}
