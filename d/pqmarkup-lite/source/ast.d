module ast;

import std.sumtype;
import tokens;

alias AstNodeT = SumType!(
    AstRoot,
    AstString,
    AstText,
    AstHeader,
    AstLink,
    AstAbbr,
    AstJunk,
    AstWhiteSpace,
    AstStyle,
    AstNewLine,
    AstInconclusive,
    AstDot,
    AstNumber,
    AstBlock,
    AstLinkRef,
    AstListItem,
    AstCode,
);

struct AstNode
{
    import std.array : Appender;
    import std.range : repeat, take;

    AstNode* parent;
    AstNodeT value;
    AstNode*[] children;

    this(ValueT)(AstNode* p, ValueT v, AstNode*[] c = null)
    {
        if(p)
            p.addChild(&this);
        this.value = AstNodeT(v);
        this.children = c;
    }

    void addChild(AstNode* child)
    {
        import std.algorithm : remove;

        if(child.parent)
            child.parent.children = child.parent.children.remove!(i => i is child);

        this.children ~= child;
        child.parent = &this;
    }

    string toString()
    {
        import std.exception : assumeUnique;

        Appender!(char[]) output;
        this.toString(0, output);
        return output.data.assumeUnique;
    }

    void toString(size_t indent, ref Appender!(char[]) output)
    {
        import std.conv : to;

        output.put(repeat(' ').take(indent * 4));
        output.put(this.value.to!string());
        output.put('\n');
        foreach(child; this.children)
            child.toString(indent + 1, output);
    }
}

struct AstRoot{}
struct AstString {}
struct AstText 
{
    string text;
}
struct AstHeader
{
    int size;
    bool isNegative;
}
struct AstLink
{
    AstNode* textNode;
    string href;
    bool isLocalLink;
}
struct AstAbbr
{
    AstNode* textNode;
    AstNode* titleNode;
}
struct AstDot{}
struct AstWhiteSpace{}
struct AstNewLine{}
struct AstInconclusive
{
    AstNode* textNode;
}
struct AstJunk
{
    string text;
    string message;
}
struct AstStyle
{
    StringStyle style;
}
struct AstNumber
{
    int value;
}
struct AstLinkRef
{
    AstNode* textNode;
    int value;
}
struct AstBlock
{
    BlockType type;
}
struct AstListItem
{
}
struct AstCode
{
    string text;
}