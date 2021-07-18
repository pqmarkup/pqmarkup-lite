module tokens;

import std;

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
    tuple('*',  StringStyle.bold,       "b"),
    tuple('_',  StringStyle.underline,  "u"),
    tuple('-',  StringStyle.strike,     "s"),
    tuple('~',  StringStyle.italic,     "i"),
    tuple('\\', StringStyle.subset,     "sub"),
    tuple('/',  StringStyle.superset,   "sup"),
];

struct Operator
{
    dchar ch;
    TokenValue value;
}

immutable OPERATORS =
[
    Operator(Q_LEFT,  TokenValue(OpenQuote())),
    Operator(Q_RIGHT, TokenValue(CloseQuote())),
    Operator('H',     TokenValue(CapitalH())),
    Operator('\n',    TokenValue(NewLine(1))),
    Operator('(',     TokenValue(OpenCParen())),
    Operator(')',     TokenValue(CloseCParen())),
    Operator('+',     TokenValue(Plus())),
    Operator('[',     TokenValue(OpenSParen())),
    Operator(']',     TokenValue(CloseSParen())),
    Operator('.',     TokenValue(Dot())),
    Operator('0',     TokenValue(Zero())),
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
    return STYLES.filter!(s => s[0] == ch).front;
}

alias TokenValue = SumType!(
    Style,
    OpenQuote,
    CloseQuote,
    CapitalH,
    OpenCParen,
    CloseCParen,
    Number,
    OpenSParen,
    CloseSParen,
    Zero,
    LeftAlign,
    RightAlign,
    CenterAlign,
    JustifyAlign,
    Block,
    NewLine,
    WhiteSpace,
    EOF,
    Text,
    Plus,
    Dot
);

struct Token
{
    TokenValue value;
    size_t start;
    size_t end;

    this(T)(T value, size_t s = 0, size_t e = 0)
    {
        this.value = value;
        this.start = s;
        this.end = e;
    }
}

struct Style
{
    StringStyle style;
}

struct OpenQuote
{
}

struct CloseQuote
{
}

struct CapitalH
{
}

struct OpenCParen
{
}

struct CloseCParen
{
}

struct Number
{
    ptrdiff_t value;
}

struct OpenSParen
{
}

struct CloseSParen
{
}

struct Zero
{
}

struct LeftAlign
{
}

struct RightAlign
{
}

struct CenterAlign
{
}

struct JustifyAlign
{
}

struct Block
{
}

struct NewLine
{
    size_t count;
}

struct WhiteSpace
{
    size_t count;
}

struct EOF
{
}

struct Text
{
    string text;
}

struct Plus
{
}

struct Dot
{
}