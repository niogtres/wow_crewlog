using Crewlog.Client.Core.Lua;

namespace Crewlog.Client.Tests;

public class SavedVariablesParserTests
{
    private static LuaTable Table(string lua, string name = "T") =>
        SavedVariablesParser.Parse(lua)[name].AsTable() ?? throw new InvalidOperationException("not a table");

    [Fact]
    public void Parses_primitives_and_multiple_globals()
    {
        var g = SavedVariablesParser.Parse("""
            A = 1
            B = -2.5
            C = "hi"
            D = true
            E = false
            F = nil
            G = 1e3
            H = 0x1F
            """);
        Assert.Equal(1, g["A"].AsNumber());
        Assert.Equal(-2.5, g["B"].AsNumber());
        Assert.Equal("hi", g["C"].AsString());
        Assert.True(g["D"].AsBoolean());
        Assert.False(g["E"].AsBoolean());
        Assert.True(g["F"].IsNil);
        Assert.Equal(1000, g["G"].AsNumber());
        Assert.Equal(31, g["H"].AsNumber());
    }

    [Fact]
    public void Reads_wow_style_table_with_index_comments_and_trailing_commas()
    {
        var t = Table("""

            T = {
            	["name"] = "Zarnokk",
            	["list"] = {
            		788, -- [1]
            		3911, -- [2]
            	},
            	["nested"] = {
            		{
            			["k"] = "ACCEPT",
            		}, -- [1]
            	},
            }
            """);
        Assert.Equal("Zarnokk", t["name"].AsString());
        var list = t["list"].AsTable()!;
        Assert.Equal([788.0, 3911.0], list.Array.Select(v => v.AsNumber()!.Value));
        Assert.Equal("ACCEPT", t["nested"].AsTable()![1].AsTable()!["k"].AsString());
    }

    [Fact]
    public void Handles_escapes_including_percent_q_newlines_and_decimal_codes()
    {
        var g = SavedVariablesParser.Parse("S = \"a\\\"b\\\\c\\nd\\\ne\\65\\t\"\nQ = 'single'");
        Assert.Equal("a\"b\\c\nd\neA\t", g["S"].AsString());
        Assert.Equal("single", g["Q"].AsString());
    }

    [Fact]
    public void Numeric_keys_fold_into_the_array_part_when_contiguous()
    {
        var t = Table("T = { [1] = \"a\", [3] = \"c\", [2] = \"b\", [97279] = \"q\" }");
        Assert.Equal(3, t.Array.Count);
        Assert.Equal("c", t[3].AsString());
        Assert.Equal("q", t[97279].AsString());
        Assert.Equal([1, 2, 3, 97279], t.IntKeyed().Select(kv => kv.Key).OrderBy(k => k));
    }

    [Fact]
    public void Named_fields_positional_values_and_comments_mix()
    {
        var t = Table("""
            --[[ block
            comment ]]
            T = { x = 1, true, y = "z"; [==[long]==], -- trailing
            }
            """);
        Assert.Equal(1, t["x"].AsNumber());
        Assert.Equal("z", t["y"].AsString());
        Assert.True(t[1].AsBoolean());
        Assert.Equal("long", t[2].AsString());
    }

    [Fact]
    public void Nil_values_in_tables_are_dropped()
    {
        var t = Table("T = { [\"a\"] = nil, [\"b\"] = 1 }");
        Assert.True(t["a"].IsNil);
        Assert.Equal(1, t.Count);
    }

    [Fact]
    public void Special_numbers_parse()
    {
        var g = SavedVariablesParser.Parse("A = inf\nB = -inf\nC = -nan(ind)\nD = .5");
        Assert.Equal(double.PositiveInfinity, g["A"].AsNumber());
        Assert.Equal(double.NegativeInfinity, g["B"].AsNumber());
        Assert.True(double.IsNaN(g["C"].AsNumber()!.Value));
        Assert.Equal(0.5, g["D"].AsNumber());
    }

    [Theory]
    [InlineData("T = os.execute('calc')", "Unexpected identifier 'os'")]
    [InlineData("T = { a = loadstring(\"x\") }", "Unexpected identifier 'loadstring'")]
    [InlineData("T = function() end", "Unexpected identifier 'function'")]
    [InlineData("T = 1 + 2", "Expected a variable name")]
    [InlineData("T = { 1, 2", "Expected ',' or '}'")]
    [InlineData("T = \"unterminated", "Unterminated string")]
    public void Rejects_code_and_malformed_input(string lua, string expected)
    {
        var ex = Assert.Throws<LuaParseException>(() => SavedVariablesParser.Parse(lua));
        Assert.Contains(expected, ex.Message);
    }

    [Fact]
    public void Reports_line_numbers()
    {
        var ex = Assert.Throws<LuaParseException>(() => SavedVariablesParser.Parse("T = {\n  a = 1,\n  b = ?\n}"));
        Assert.Equal(3, ex.Line);
    }

    [Fact]
    public void Limits_nesting_depth()
    {
        var deep = "T = " + new string('{', SavedVariablesParser.MaxDepth + 2) + new string('}', SavedVariablesParser.MaxDepth + 2);
        Assert.Throws<LuaParseException>(() => SavedVariablesParser.Parse(deep));
    }

    [Fact]
    public void Parses_the_real_probe_dump_from_the_forever_client_when_present()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Fixtures", "private", "Crewlog_Probe.lua");
        if (!File.Exists(path)) return; // private fixture, only on the dev machine
        var db = SavedVariablesParser.ParseFile(path)["Crewlog_ProbeDB"].AsTable()!;
        Assert.Equal("0.0.1", db["probeVersion"].AsString());
        var build = db["runs"].AsTable()![1].AsTable()!["environment"].AsTable()!["build"].AsTable()!;
        Assert.Equal(16001, build[4].AsInt());
    }
}
