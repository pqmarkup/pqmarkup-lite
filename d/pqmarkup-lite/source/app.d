module app;

import std : Nullable, Appender, enforce, decode, to, SumType, tuple, strip;
import std.sumtype : match, tryMatch;
import std.utf : codeLength;
import jcli : CommandDefault, CommandPositionalArg, CommandNamedArg, Result, CommandHelpText, CommandParser;

alias StringBuilder = Appender!(char[]);

@CommandDefault
struct Options
{
    @CommandPositionalArg(0, "file", "The markup file to use.")
    string file;

    @CommandNamedArg("t|is-test", "Specified if the provided file is a test file.")
    Nullable!bool isTestFile;
}

struct TestCase
{
    string input;
    string output;
}

int main(string[] args)
{
    import std : readText, writeln;

    auto optionsResult = getOptions(args);
    if(optionsResult.isFailure)
        return -1;

    const options = optionsResult.asSuccess.value;
    const text    = readText(options.file);

    if(options.isTestFile.get(false))
    {
        auto result = getTestCases(text);
        if(result.isFailure)
        {
            import std : writeln;
            writeln("error: ", result.asFailure.error);
            return -1;
        }

        foreach(test; result.asSuccess.value)
        {
            auto html = transform(test.input);
            writeln(test.input, " -> ", html);
            //assert(html == test.output, html~" !!!! "~test.output);
        }
    }
    return 0;
}

Result!Options getOptions(string[] args)
{
    import std : writeln;

    CommandParser!Options parser;
    Options options;

    auto result = parser.parse(args[1..$], /*ref*/options);

    if(!result.isSuccess)
    {
        CommandHelpText!Options help;
        writeln(help.toString("pqmarkup-lite"));
        return typeof(return).failure("");
    }

    return typeof(return).success(options);
}

Result!(TestCase[]) getTestCases(string text)
{
    import std       : splitter, filter, all, array, map, countUntil, byCodeUnit;
    import std.ascii : isWhite; // dunno why, but I have to do this one separately for it to wkr.

    const DELIM = " (()) ";
    auto cases =
        text.splitter('|')
            .map!((split)
            {
                if(split.all!isWhite)
                    return null;

                const delimStart = split.byCodeUnit.countUntil(DELIM);
                if(delimStart < 0)
                    return null;
                return [split[0..delimStart+1], split[delimStart+DELIM.length..$]];
            })
            .filter!(splits => splits !is null)
            .map!(splits => TestCase(splits[0], splits[1]))
            .array;

    return typeof(return).success(cases);
}

enum StringStyle
{
    none,
    bold,
    underline,
    strike,
    italic,
    superset,
    subset
}

enum Q_LEFT = '‘';
enum Q_RIGHT = '’';
immutable STYLES = 
[
    tuple('*', StringStyle.bold,        "b"),
    tuple('_', StringStyle.underline,   "u"),
    tuple('-', StringStyle.strike,      "s"),
    tuple('~', StringStyle.italic,      "i"),
    tuple('\\', StringStyle.subset,     "sub"),
    tuple('/', StringStyle.superset,    "sup"),
];

bool isStyleChar(dchar ch)
{
    switch(ch)
    {
        static foreach(style; STYLES)
            case style[0]: return true;

        default: return false;
    }
}
///
unittest
{
    assert('_'.isStyleChar);
    assert(!'!'.isStyleChar);
}

auto getStyleInfo(dchar ch)
{
    switch(ch)
    {
        static foreach(style; STYLES)
            case style[0]: return style;

        default: return tuple('\0', StringStyle.none, "");
    }
}

auto getStyleInfo(StringStyle style)
{
    switch(style)
    {
        static foreach(s; STYLES)
            case s[1]: return s;

        default: return tuple('\0', StringStyle.none, "");
    }
}

struct Attrib
{
    string name;
    string value;
}

enum DomType
{
    normal,
    styling,
    str,
    prefix,
    whitespace = _special | 1, // Signifies whitespace, but isn't actually outputted.
    endofline = _special | 2,
    comment = _special | 3,

    _special = 0xFF000000
}

struct Dom
{
    string tag;
    DomType type;
    size_t tempCursor;
    Attrib[] attribs;
    string innerText;
    Dom*[] children;
    Dom* parent;
    bool lock;

    Dom* addChild(Dom* child)
    {
        child.parent = &this;
        this.children ~= child;
        return child;
    }

    void addAttrib(string name, string value)
    {
        this.attribs ~= Attrib(name, value);
    }

    bool isSpecialType()
    {
        return (this.type & 0xFF000000) == 0xFF000000;
    }

    string toString()
    {
        import std.exception : assumeUnique;

        assert(this.tag == "body");
        StringBuilder builder;
        builder.reserve(512 * this.children.length);

        foreach(ref child; this.children)
            child.toString(builder);

        return builder.data.assumeUnique;
    }

    void toString(ref StringBuilder builder)
    {
        import std.algorithm : substitute;

        if(this.tag.length && !this.isSpecialType)
        {
            builder.put('<');
            builder.put(this.tag);

            foreach(attrib; this.attribs)
            {
                builder.put(' ');
                builder.put(attrib.name);
                builder.put("=\"");
                builder.put(attrib.value.substitute!(
                    "&", "&amp;"
                ));
                builder.put('"');
            }

            builder.put('>');
        }
        builder.put(this.innerText);
        foreach(ref child; this.children)
            child.toString(builder);

        if(this.tag.length && !this.isSpecialType)
        {
            builder.put("</");
            builder.put(this.tag);
            builder.put('>');
        }
    }
}

string transform(string input)
{
    Dom* body_ = new Dom("body");
    Dom* currNode = body_;
    body_.parent = body_;
    size_t cursor;
    uint commentNest = 0;

    dchar peek(out size_t newCursor)
    {
        newCursor = cursor;
        return decode(input, newCursor);
    }

    dchar[amount] peekMany(size_t amount)(out size_t newCursor)
    {
        dchar[amount] results;
        newCursor = cursor;
        foreach(i; 0..amount)
            results[i] = decode(input, newCursor);
        return results;
    }

    dchar next()
    {
        return decode(input, cursor);
    }

    dchar[amount] nextMany(size_t amount)()
    {
        return peekMany!amount(cursor);
    }

    void commit(size_t newCursor)
    {
        cursor = newCursor;
    }

    void finishSliceIfStr(Dom* dom, size_t end)
    {
        if(dom.type == DomType.str && !dom.lock)
        {
            dom.lock = true;
            dom.innerText = input[dom.tempCursor..end];
        }
    }

    void popParentIfPrefix()
    {
        if(currNode.type == DomType.prefix)
            currNode = currNode.parent;
    }

    bool peekUntil(out size_t newCursor, dchar[] chars...)
    {
        import std.algorithm : any;

        newCursor = cursor;
        size_t prevCursor;
        while(newCursor < input.length)
        {
            prevCursor = newCursor;
            const ch = decode(input, newCursor);
            if(chars.any!(c => c == ch))
            {
                newCursor = prevCursor;
                return true;
            }
        }

        return false;
    }

    while(cursor < input.length) with(DomType)
    {
        size_t afterFirst;
        const atFirst = cursor;
        const first = peek(afterFirst);
        bool fallThrough = false;
        
        if(commentNest > 0 && input.length - cursor < 3)
            break;

        switch(first)
        {
            case '[':
                size_t afterComment;
                if(peekMany!3(afterComment) == "[[[")
                {
                    finishSliceIfStr(currNode, atFirst);
                    commit(afterComment);
                    commentNest++;
                    break;
                }
                else if(commentNest > 0)
                {
                    commit(afterFirst);
                    break;
                }

                commit(afterFirst);
                size_t afterFirstParam;
                peekUntil(afterFirstParam, ' ', ']', Q_LEFT, '[');
                currNode = currNode.addChild(new Dom("a", normal, afterFirst));
                currNode.addChild(new Dom(null, str));
                currNode.children[$-1].innerText = input[afterFirst..afterFirstParam];
                commit(afterFirstParam);
                break;

            case ']':
                size_t afterComment;
                if(commentNest > 0 && peekMany!3(afterComment) == "]]]")
                {
                    commit(afterComment);
                    commentNest--;
                    break;
                }
                else if(commentNest > 0)
                {
                    commit(afterFirst);
                    break;
                }

                commit(afterFirst);
                currNode = currNode.parent;
                break;

            default:
                fallThrough = true;
                break;
        }

        if(!fallThrough)
            continue;
        else if(commentNest > 0)
        {
            commit(afterFirst);
            continue;
        }

        size_t _1;
        switch(first)
        {
            case '*': if(peekMany!2(_1)[1] == Q_LEFT) currNode = currNode.addChild(new Dom("b", styling)); commit(afterFirst); goto default;
            case '-': if(peekMany!2(_1)[1] == Q_LEFT) currNode = currNode.addChild(new Dom("s", styling)); commit(afterFirst); goto default;
            case '_': if(peekMany!2(_1)[1] == Q_LEFT) currNode = currNode.addChild(new Dom("u", styling)); commit(afterFirst); goto default;
            case '~': if(peekMany!2(_1)[1] == Q_LEFT) currNode = currNode.addChild(new Dom("i", styling)); commit(afterFirst); goto default;
            case '/':
                if(peekMany!3(_1) != ['/', '\\', Q_LEFT])
                    goto default;
                next(); next();
                currNode = currNode.addChild(new Dom("sup", styling));
                break;
            case '\\':
                if(peekMany!3(_1) != ['\\', '/', Q_LEFT])
                    goto default;
                next(); next();
                currNode = currNode.addChild(new Dom("sub", styling));
                break;
            case Q_LEFT: currNode = currNode.addChild(new Dom("", str, afterFirst)); commit(afterFirst); break;
            case Q_RIGHT:
                finishSliceIfStr(currNode, cursor);
                currNode = currNode.parent;
                commit(afterFirst);
                popParentIfPrefix();
                break;

            case 'H':
                commit(afterFirst);
                size_t afterH;
                const afterHCh = peek(afterH);
                switch(afterHCh)
                {
                    case Q_LEFT:
                        currNode = currNode.addChild(new Dom("h3", prefix));
                        break;

                    case '(':
                        commit(afterH);
                        size_t afterNumber;
                        peekUntil(afterNumber, ')');
                        const number = input[afterH..afterNumber];
                        commit(afterNumber);
                        next();
                        currNode = currNode.addChild(new Dom("h"~(3 - number.to!int).to!string, prefix));
                        break;

                    default:
                        commit(afterFirst);
                        break;
                }
                break;
            default:
                if(currNode.parent.type == normal)
                {
                    import std.uni : isAlphaNum;
                    
                    bool wasWhite;
                    while(cursor < input.length && (input[cursor] == ' ' || input[cursor] == '\t'))
                    {
                        wasWhite = true;
                        cursor++;
                    }
                    if(wasWhite)
                        currNode.addChild(new Dom(null, whitespace));

                    bool wasLine;
                    while(cursor < input.length && input[cursor] == '\n')
                    {
                        wasLine = true;
                        currNode.addChild(new Dom(null, endofline));
                        cursor++;
                    }

                    if(wasLine)
                        break;

                    const start = cursor;
                    while(cursor < input.length)
                    {
                        size_t afterCh;
                        auto ch = peek(afterCh);
                        if(!isAlphaNum(ch))
                            break;
                        commit(afterCh);
                    }

                    if(cursor == atFirst)
                    {
                        commit(afterFirst);
                        break;
                    }

                    if(currNode.type == str)
                    {
                        currNode.innerText ~= " "~input[start..cursor];
                    }
                    else if(currNode.children.length && currNode.children[$-1].type == str)
                    {
                        auto node = currNode.children[$-1];
                        node.innerText = input[node.tempCursor..cursor];
                    }
                    else
                        currNode.addChild(new Dom(null, str, start, null, input[start..cursor]));
                }
                else
                    commit(afterFirst);
                break;
        }
    }

    import std;
    writeln(body_.toString());

    return null;
}