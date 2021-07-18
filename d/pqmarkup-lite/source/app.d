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
            assert(html == test.output, html~" !!!! "~test.output);
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

struct EndPartialString // The ending part of a partial string.
{
    string text;
    StringStyle style;
}
struct PartialString // Any "middle" parts of a partial string.
{
    string text;
}
struct StartPartialString // The starting part of a partial string.
{
    string text;
    StringStyle style;
}
struct FullString // String without anything in between.
{
    string text;
    StringStyle style;
}
struct Comment {}
struct LinkStart 
{
    string url;
}
struct LinkEnd 
{
    Nullable!int index;
}
struct LinkRef
{
    int index;
}
struct Word 
{
    string text;
}
struct RawNewLine {}
struct HeaderStart
{
    int level;
}
struct HeaderEnd
{
    int level;
}

alias Fragment = SumType!(
    PartialString, EndPartialString, FullString,
    Comment,       LinkStart,        Word,
    RawNewLine,    LinkEnd,          StartPartialString,
    HeaderStart,   HeaderEnd,        LinkRef
);

alias FragmentCallback = void delegate(Fragment);

immutable DOM_COMPOUND_STRING = "_compoundstr";

struct Attrib
{
    string name;
    string value;
}

struct Dom
{
    string tag;
    Attrib[] attribs;
    string innerText;
    Dom*[] children;
    Dom* parent;

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

    bool isCompoundString()
    {
        return this.tag == DOM_COMPOUND_STRING;
    }

    bool isProbablyString()
    {
        return this.tag.length == 0;
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

        if(this.tag.length && this.tag[0] != '_')
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

        if(this.tag.length && this.tag[0] != '_')
        {
            builder.put("</");
            builder.put(this.tag);
            builder.put('>');
        }
    }
}

string transform(string input)
{
    Fragment prevFrag;    // Useful in some cases as well.
    Fragment waitingFrag; // Sometimes we need to wait a little bit to see what's came next.

    Dom*        body_        = new Dom("body");
    Dom*        currentChild = body_;
    string[int] urlsByIndex;

    void handleWaitingFrag(ref Fragment thisFrag)
    {
        if(waitingFrag == Fragment.init)
            return;

        waitingFrag.tryMatch!(
        );

        waitingFrag = Fragment.init;
    }

    fragmentPusher(input, (fragment)
    {
        bool keepPrevFrag = false;
        handleWaitingFrag(fragment);
        fragment.match!(
            (StartPartialString value)=> prevFrag.tryMatch!(
                (LinkStart link) 
                {
                    currentChild.addAttrib("title", value.text);
                    keepPrevFrag = true;
                },
                (_) 
                { 
                    if(!currentChild.isCompoundString)
                        currentChild = currentChild.addChild(new Dom(DOM_COMPOUND_STRING));
                    currentChild.addChild(createTextDom(value.text, value.style)); 
                },
            ),
            (PartialString value)=> prevFrag.tryMatch!(
                (LinkStart link) 
                {
                    if(currentChild.attribs.length == 1)
                        currentChild.addAttrib("title", value.text);
                    else
                        currentChild.attribs[1].value ~= value.text;
                    keepPrevFrag = true;
                },
                (_) 
                {
                    currentChild.addChild(createTextDom(value.text, StringStyle.none));
                },
            ),
            (EndPartialString value) => prevFrag.tryMatch!(
                (LinkStart link) 
                {
                    currentChild.attribs[1].value ~= value.text;
                },
                (_)
                {
                    currentChild.addChild(createTextDom(value.text, value.style));
                    currentChild = currentChild.parent;
                },
            ),
            (FullString value) => prevFrag.tryMatch!(
                (LinkStart link) 
                {
                    currentChild.addAttrib("title", value.text);
                },
                (_) 
                { 
                    currentChild.addChild(createTextDom(value.text, value.style));
                }
            ),
            (HeaderStart value)
            {
                currentChild = currentChild.addChild(new Dom("h"~value.level.to!string));
            },
            (HeaderEnd value)
            {
                currentChild = currentChild.parent;
            },
            (Comment value){},
            (LinkStart value)
            {
                auto link = new Dom("a", [Attrib("href", value.url)]);

                // If our sibling is a string/compound string, then it's probably our label.
                if(currentChild.children.length)
                {
                    auto sibling = currentChild.children[$-1];
                    if(sibling.isCompoundString || sibling.isProbablyString)
                    {
                        currentChild.children.length--;
                        link.addChild(sibling);
                    }

                    // idk, but this is what the tests say
                }
                else
                    link.innerText = value.url;

                if(value.url is null)
                {
                    link.tag = "abbr";
                    link.attribs = null;
                }
                currentChild = currentChild.addChild(link);
            },
            (LinkEnd value)
            {
                if(!value.index.isNull)
                    urlsByIndex[value.index.get] = currentChild.attribs[0].value;
                currentChild = currentChild.parent;
            },
            (LinkRef value)
            {

            },
            (Word value)
            {
                currentChild.addChild(createTextDom(value.text, StringStyle.none));
            },
            (RawNewLine value)
            {
            },
        );
        if(!keepPrevFrag)
            prevFrag = fragment;
    });

    Fragment f;
    handleWaitingFrag(f); // Just in case there's one left over.
    return body_.toString();
}

Dom* createTextDom(string text, StringStyle style)
{
    auto dom = new Dom();
    dom.tag = getStyleInfo(style)[2];
    dom.innerText = text;

    return dom;
}

void fragmentPusher(string input, FragmentCallback callback)
{
    size_t cursor;

    while(cursor < input.length)
    {
        const next = decode(input, cursor);

        if(next.isStyleChar || next == Q_LEFT)
        {
            goBack(cursor, next);
            if(!pushString(input, cursor, callback))
                assert(0);
            continue;
        }

        switch(next)
        {
            case 'H':
                pushHeader(input, cursor, callback);
                continue;

            case '[':
                if(!skipComment(input, cursor))
                    pushLink(input, cursor, callback);
                break;

            case '\n':
                callback(Fragment(RawNewLine()));
                break;

            default: break;
        }

        import std.uni : isAlphaNum;
        if(next.isAlphaNum)
        {
            goBack(cursor, next);
            pushWord(input, cursor, callback);
        }
    }
}

bool pushString(string input, ref size_t cursor, FragmentCallback callback)
{
    bool isPartial = false;
    void pushPartial(string text, StringStyle style, bool isEnd)
    {
        if(!isPartial)
        {
            callback(Fragment(StartPartialString(
                text, style
            )));
        }
        else if(!isEnd)
        {
            callback(Fragment(PartialString(
                text
            )));
        }
        else
        {
            callback(Fragment(EndPartialString(
                text, style
            )));
        }

        isPartial = true;
    }

    auto next = decode(input, cursor);
    const rollback = cursor;
    const style = getStyleInfo(next)[1];

    // Stray style character on its own.
    if(style == StringStyle.none && next != Q_LEFT)
        return false;

    if(style == StringStyle.superset || style == StringStyle.subset)
    {
        next = decode(input, cursor);
        if(next != (style == StringStyle.superset ? '\\' : '/'))
        {
            cursor = rollback;
            return false;
        }
    }

    if(next != Q_LEFT) // ditto.
    {
        next = decode(input, cursor);
        if(next != Q_LEFT)
        {
            cursor = rollback;
            return false;
        }
    }

    auto start = cursor;
    while(cursor < input.length)
    {
        const beforeComment = cursor;
        if(skipComment(input, cursor))
        {
            pushPartial(input[start..beforeComment], style, false);
            start = cursor;
        }
        
        next = decode(input, cursor);

        if(isStyleChar(next) || next == Q_LEFT)
        {
            goBack(cursor, next);
            pushPartial(input[start..cursor], style, false);
            if(!pushString(input, cursor, callback))
            {
                pushPartial(""~cast(char)next, style, false);
            }
            start = cursor;
        }
        else if(next == Q_RIGHT)
        {
            auto text = input[start..cursor-next.codeLength!char];
            if(!isPartial)
                callback(Fragment(FullString(text, style)));
            else
                pushPartial(text, style, true);
            return true;
        }
    }

    return true;
}

void pushHeader(string input, ref size_t cursor, FragmentCallback callback)
{
    int level = 3;
    if(input[cursor] == '(')
    {
        const start = ++cursor;
        enforce(readUntil(input, cursor, ')'), "Unexpected EOF when reading header size. No terminating ')' was found.");
        const end = cursor++;

        level += -1 * input[start..end].to!int;
    }

    callback(Fragment(HeaderStart(level)));
    enforce(pushString(input, cursor, callback), "Couldn't parse the header name for some reason.");
    callback(Fragment(HeaderEnd(level)));
}

void pushWord(string input, ref size_t cursor, FragmentCallback callback)
{
    import std.uni : isAlphaNum;

    const start = cursor;
    auto next = decode(input, cursor);
    while(cursor < input.length && next.isAlphaNum)
        next = decode(input, cursor);
    if(cursor < input.length)
        goBack(cursor, next);

    callback(Fragment(Word(input[start..cursor])));
}

void pushLink(string input, ref size_t cursor, FragmentCallback callback)
{
    eatWhite(input, cursor);

    auto start = cursor;
    auto next = decode(input, cursor);
    if(next == Q_LEFT) // Link with tooltip but no actual link.
    {
        goBack(cursor, next);
        callback(Fragment(LinkStart(null)));
        return;
    }
    else if(next == ']') // Empty link
    {
        callback(Fragment(LinkStart(null)));
        callback(Fragment(LinkEnd()));
        return;
    }
    else if(next == '-') // reference to another link
    {
        enforce(readUntil(input, cursor, ']'), "Unexpected EOF when reading link reference index.");
        callback(Fragment(LinkRef(
            input[start..cursor].to!int
        )));
        cursor++;
        return;
    }

    // Otherwise, we _should_ have a URL, so just read to a delim
    enforce(readUntil(input, cursor, ']', ' '));
    callback(Fragment(LinkStart(
        input[start..cursor]
    )));

    // Very annoying edge case: apparently the tooltip doesn't actually need to be in a string.
    import std.uni : isAlphaNum;
    eatWhite(input, cursor);
    start = cursor;
    next = decode(input, cursor);
    if(!isAlphaNum(next))
    {
        goBack(cursor, next);
        return;
    }

    // Even more annoying, there seems to be a strange part of the syntax that allows that "[.&.]" thing to happen.
    // soooooooooooooooooooooooooo we're doing things the hard way.
    size_t bracketPairs;
    while(cursor < input.length)
    {
        next = input[cursor];

        if(next == '[')
        {
            const end = cursor;
            if(skipComment(input, cursor))
            {
                callback(Fragment(PartialString(input[start..end])));
                start = cursor;
            }
            else
                bracketPairs++;
        }
        else if(next == ']')
        {
            if(bracketPairs == 0)
            {
                cursor++;
                callback(Fragment(LinkEnd()));
                return;
            }
            bracketPairs--;
        }

        cursor++;
    }
}

bool skipComment(string input, ref size_t cursor)
{
    if(input[cursor] != '[')
        return false;

    auto remaining = input.length - cursor;
    if(remaining >= 3 && input[cursor..cursor+3] == "[[[")
    {
        cursor += 3;
        while(cursor < input.length)
        {
            if(!readUntil(input, cursor, '[', ']'))
                return false;

            const prev = input[cursor];
            if(prev == '[')
            {
                if(!skipComment(input, cursor))
                    cursor++;
            }
            else
            {
                remaining = input.length - cursor;
                if(remaining >= 3 && input[cursor..cursor+3] == "]]]")
                {
                    cursor += 3;
                    return true;
                }
                cursor++;
            }
        }
    }

    return false;
}

void goBack(ref size_t cursor, dchar lastChar)
{
    cursor -= lastChar.codeLength!char;
}

bool readUntil(string input, ref size_t cursor, char[] chs...)
{
    while(cursor < input.length) 
    {
        const next = input[cursor];
        foreach(ch; chs)
        {
            if(next == ch)
                return true;
        }
        cursor++;
    }

    return false;
}

// this could genuinely be seen as a racist function name nowadays...
void eatWhite(string input, ref size_t cursor)
{
    import std.ascii : isWhite;

    while(cursor < input.length)
    {
        const next = input[cursor];
        if(!next.isWhite)
            return;
        cursor++;
    }
}