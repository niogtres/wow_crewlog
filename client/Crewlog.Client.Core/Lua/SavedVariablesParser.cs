using System.Globalization;
using System.Text;

namespace Crewlog.Client.Core.Lua;

public sealed class LuaParseException(string message, int line, int column)
    : Exception($"{message} (line {line}, column {column})")
{
    public int Line { get; } = line;
    public int Column { get; } = column;
}

/// <summary>
/// Reads WoW SavedVariables files: a sequence of <c>Name = value</c> assignments where values are
/// nil, booleans, numbers, strings and tables. It is a data parser, not a Lua interpreter:
/// anything else (function calls, operators, code) is a parse error, so a tampered file can't run code.
/// </summary>
public static class SavedVariablesParser
{
    public const int MaxDepth = 64;
    public const int MaxLength = 64 * 1024 * 1024;

    public static IReadOnlyDictionary<string, LuaValue> Parse(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        if (text.Length > MaxLength) throw new LuaParseException($"File is larger than {MaxLength / (1024 * 1024)} MB", 1, 1);
        return new Reader(text).ReadAssignments();
    }

    public static IReadOnlyDictionary<string, LuaValue> ParseFile(string path) =>
        Parse(ReadShared(path));

    /// <summary>Reads a file WoW may be rewriting: shared access, BOM-aware.</summary>
    public static string ReadShared(string path)
    {
        using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var sr = new StreamReader(fs, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        return sr.ReadToEnd();
    }

    private sealed class Reader(string s)
    {
        private int _pos;
        private int _line = 1;
        private int _lineStart;

        private LuaParseException Error(string msg) => new(msg, _line, _pos - _lineStart + 1);

        public Dictionary<string, LuaValue> ReadAssignments()
        {
            var globals = new Dictionary<string, LuaValue>(StringComparer.Ordinal);
            SkipTrivia();
            while (!AtEnd)
            {
                var name = ReadName() ?? throw Error("Expected a variable name");
                SkipTrivia();
                Expect('=');
                globals[name] = ReadValue(0);
                SkipTrivia();
                if (Peek() == ';') { _pos++; SkipTrivia(); }
            }
            return globals;
        }

        private bool AtEnd => _pos >= s.Length;
        private char Peek(int ahead = 0) => _pos + ahead < s.Length ? s[_pos + ahead] : '\0';

        private void Expect(char c)
        {
            if (Peek() != c) throw Error($"Expected '{c}' but found {Describe()}");
            _pos++;
        }

        private string Describe() => AtEnd ? "end of file" : $"'{Peek()}'";

        private void NewLine()
        {
            _line++;
            _lineStart = _pos;
        }

        private void SkipTrivia()
        {
            while (!AtEnd)
            {
                var c = s[_pos];
                if (c == '\n') { _pos++; NewLine(); }
                else if (c is ' ' or '\t' or '\r' or '\f' or '\v') _pos++;
                else if (c == '-' && Peek(1) == '-')
                {
                    _pos += 2;
                    var level = LongBracketLevel();
                    if (level >= 0) ReadLongBracket(level);
                    else while (!AtEnd && s[_pos] != '\n') _pos++;
                }
                else break;
            }
        }

        private LuaValue ReadValue(int depth)
        {
            SkipTrivia();
            if (AtEnd) throw Error("Expected a value but found end of file");
            var c = Peek();
            switch (c)
            {
                case '{':
                    return ReadTable(depth + 1);
                case '"' or '\'':
                    return new LuaString(ReadQuotedString());
                case '[' when LongBracketLevel() >= 0:
                    return new LuaString(ReadLongBracket(LongBracketLevel()));
            }
            if (c == '-' || c == '.' || char.IsAsciiDigit(c)) return new LuaNumber(ReadNumber());

            var word = ReadName() ?? throw Error($"Unexpected {Describe()}");
            return word switch
            {
                "nil" => LuaValue.Nil,
                "true" => new LuaBoolean(true),
                "false" => new LuaBoolean(false),
                "inf" => new LuaNumber(double.PositiveInfinity),
                "nan" => new LuaNumber(double.NaN),
                _ => throw Error($"Unexpected identifier '{word}' (only data is allowed in SavedVariables)"),
            };
        }

        private LuaTable ReadTable(int depth)
        {
            if (depth > MaxDepth) throw Error($"Tables nested deeper than {MaxDepth}");
            Expect('{');
            var t = new LuaTable();
            while (true)
            {
                SkipTrivia();
                if (Peek() == '}') { _pos++; return t; }

                if (Peek() == '[' && LongBracketLevel() < 0)
                {
                    _pos++;
                    var keyValue = ReadValue(depth);
                    SkipTrivia();
                    Expect(']');
                    SkipTrivia();
                    Expect('=');
                    var value = ReadValue(depth);
                    object key = keyValue switch
                    {
                        LuaString str => str.Value,
                        LuaNumber num when !double.IsNaN(num.Value) => num.Value,
                        LuaBoolean b => b.Value ? "true" : "false",
                        _ => throw Error("Table keys must be strings, numbers or booleans"),
                    };
                    if (!value.IsNil) t.Set(key, value);
                }
                else if (IsNameStart(Peek()) && IsAssignmentAhead())
                {
                    var name = ReadName()!;
                    SkipTrivia();
                    Expect('=');
                    var value = ReadValue(depth);
                    if (!value.IsNil) t.Set(name, value);
                }
                else
                {
                    t.AppendPositional(ReadValue(depth));
                }

                SkipTrivia();
                if (Peek() is ',' or ';') { _pos++; continue; }
                SkipTrivia();
                if (Peek() == '}') { _pos++; return t; }
                throw Error($"Expected ',' or '}}' but found {Describe()}");
            }
        }

        // `name =` (not `name ==`) means a named field; otherwise it's a positional value like `true`.
        private bool IsAssignmentAhead()
        {
            var p = _pos;
            while (p < s.Length && IsNameChar(s[p])) p++;
            while (p < s.Length && s[p] is ' ' or '\t' or '\r' or '\n') p++;
            return p < s.Length && s[p] == '=' && (p + 1 >= s.Length || s[p + 1] != '=');
        }

        private static bool IsNameStart(char c) => c == '_' || char.IsAsciiLetter(c);
        private static bool IsNameChar(char c) => c == '_' || char.IsAsciiLetterOrDigit(c);

        private string? ReadName()
        {
            if (AtEnd || !IsNameStart(s[_pos])) return null;
            var start = _pos;
            while (!AtEnd && IsNameChar(s[_pos])) _pos++;
            return s[start.._pos];
        }

        private double ReadNumber()
        {
            var start = _pos;
            var negative = false;
            if (Peek() == '-')
            {
                negative = true;
                _pos++;
                SkipTrivia();
                // WoW can write "-inf" / "-nan" style tokens.
                if (IsNameStart(Peek()))
                {
                    var w = ReadName();
                    if (w == "inf") return double.NegativeInfinity;
                    if (w is not null && w.StartsWith("nan", StringComparison.Ordinal))
                    {
                        if (Peek() == '(') { while (!AtEnd && s[_pos] != ')') _pos++; _pos++; }
                        return double.NaN;
                    }
                    throw Error($"Unexpected '-{w}'");
                }
            }

            if (Peek() == '0' && (Peek(1) == 'x' || Peek(1) == 'X'))
            {
                _pos += 2;
                var hs = _pos;
                while (!AtEnd && char.IsAsciiHexDigit(s[_pos])) _pos++;
                if (hs == _pos) throw Error("Malformed hex number");
                var hex = long.Parse(s[hs.._pos], NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                return negative ? -hex : hex;
            }

            var ds = _pos;
            while (!AtEnd && (char.IsAsciiDigit(s[_pos]) || s[_pos] == '.')) _pos++;
            if (!AtEnd && (s[_pos] == 'e' || s[_pos] == 'E'))
            {
                _pos++;
                if (Peek() is '+' or '-') _pos++;
                while (!AtEnd && char.IsAsciiDigit(s[_pos])) _pos++;
            }
            var token = s[ds.._pos];
            if (token.Length == 0 || !double.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
            {
                _pos = start;
                throw Error($"Malformed number '{s[start..Math.Min(s.Length, start + 20)]}'");
            }
            return negative ? -value : value;
        }

        private string ReadQuotedString()
        {
            var quote = s[_pos++];
            var sb = new StringBuilder();
            while (true)
            {
                if (AtEnd) throw Error("Unterminated string");
                var c = s[_pos++];
                if (c == quote) return sb.ToString();
                if (c == '\n') throw Error("Unescaped line break in string");
                if (c != '\\') { sb.Append(c); continue; }

                if (AtEnd) throw Error("Unterminated string");
                var e = s[_pos++];
                switch (e)
                {
                    case 'n': sb.Append('\n'); break;
                    case 't': sb.Append('\t'); break;
                    case 'r': sb.Append('\r'); break;
                    case 'a': sb.Append('\a'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'v': sb.Append('\v'); break;
                    case '\\': sb.Append('\\'); break;
                    case '"': sb.Append('"'); break;
                    case '\'': sb.Append('\''); break;
                    case '\n': sb.Append('\n'); NewLine(); break; // %q writes a real newline after a backslash
                    case '\r':
                        sb.Append('\n');
                        if (Peek() == '\n') _pos++;
                        NewLine();
                        break;
                    default:
                        if (char.IsAsciiDigit(e))
                        {
                            var code = e - '0';
                            for (var i = 0; i < 2 && char.IsAsciiDigit(Peek()); i++) code = code * 10 + (s[_pos++] - '0');
                            if (code > 255) throw Error("Escape sequence too large");
                            sb.Append((char)code);
                            break;
                        }
                        throw Error($"Invalid escape '\\{e}'");
                }
            }
        }

        // [[...]] or [==[...]==]; returns -1 when the current position isn't one.
        private int LongBracketLevel()
        {
            if (Peek() != '[') return -1;
            var level = 0;
            while (Peek(1 + level) == '=') level++;
            return Peek(1 + level) == '[' ? level : -1;
        }

        private string ReadLongBracket(int level)
        {
            _pos += level + 2;
            if (Peek() == '\r') _pos++;
            if (Peek() == '\n') { _pos++; NewLine(); }
            var close = "]" + new string('=', level) + "]";
            var end = s.IndexOf(close, _pos, StringComparison.Ordinal);
            if (end < 0) throw Error("Unterminated long string or comment");
            var content = s[_pos..end];
            foreach (var ch in content) if (ch == '\n') _line++;
            _pos = end + close.Length;
            _lineStart = _pos;
            return content;
        }
    }
}
