module lexer;

import std, tokens;
import std.uni : isAlphaNum; // resolve symbol conflict
import tokens : EOF;

struct Lexer
{
    private string _text;
    private size_t _cursor;
    private size_t _atFirst;
    private size_t _afterFirst;
    private bool   _readNextTextAsIs; // Special case: URLS are very annoying to concat together if we still delimit by things like "-" and stuff.
                                      //               So if we encounter a '[' that's not for a comment, then Text takes precedence over operators.
                                      //               As a double special case: The open Quote operator still have higher precedence.

    this(string text)
    {
        this._text = text;
    }

    Token next()
    {
        if(this._cursor >= this._text.length)
            return Token(TokenValue(EOF()));

        this._atFirst = this._cursor;
        this._afterFirst = this._cursor;
        const first = peekUtf(this._afterFirst);
        const nextTextAsTrue = this._readNextTextAsIs;
        this._readNextTextAsIs = false;

        if(isStyleChar(first))
        {
            auto token = this.nextStyle(first);
            if(token != Token.init)
                return token;
            else
            {
                this.commit(this._afterFirst);
                return Token(Text("" ~ first.to!char), this._atFirst, this._afterFirst);
            }
        }

        size_t afterComment = this._cursor;
        size_t commentNest;
        if(first == '[' && this.peekManyAscii!3(afterComment) == "[[[")
        {
            this.commit(afterComment);
            commentNest = 1;

            while(commentNest > 0)
            {
                if(!this.readUntilAscii!(c => c == '[' || c == ']')(this._cursor))
                    return Token(EOF());

                size_t afterPeek = this._cursor;
                const peeked = this.peekManyAscii!3(afterPeek);
                if(peeked == "[[[")
                {
                    commentNest++;
                    this.commit(afterPeek);
                }
                else if(peeked == "]]]")
                {
                    commentNest--;
                    this.commit(afterPeek);
                }
                else
                    this.peekUtf(this._cursor);
            }

            return this.next();
        }

        if(nextTextAsTrue)
        {
            if(first == Q_LEFT)
            {
                this.commit(this._afterFirst);
                return Token(OpenQuote(), this._atFirst, this._afterFirst);
            }
            else
                return this.nextText();
        }

        switch(first)
        {
            case ' ':
            case '\t':
                return this.nextWhite();

            static foreach(op; OPERATORS)
            {
                case op.ch:
                    this.commit(this._afterFirst);
                    static if(op.ch == '[')
                        this._readNextTextAsIs = true;
                    return Token(op.value, this._atFirst, this._afterFirst);
            }

            case '>':
            case '<':
                return this.nextBlock(first);

            case '`':
                return this.nextCode();

            default: 
                this.commit(this._afterFirst);
                break;
        }

        if(isAlphaNum(first) || isAuxTextChar(first))
            return this.nextText();

        assert(false, first.to!string);
    }

    private:

    void commit(size_t newCursor)
    {
        this._cursor = newCursor;
    }

    char peekAscii(ref size_t nextCursor)
    {
        return this._text[nextCursor++];
    }

    dchar peekUtf(ref size_t nextCursor)
    {
        return decode(this._text, nextCursor);
    }

    char[amount] peekManyAscii(size_t amount)(ref size_t nextCursor)
    {
        auto end = nextCursor + amount;
        if(end > this._text.length)
            end = this._text.length;
        
        char[amount] chars;
        foreach(i, ch; this._text[nextCursor..end])
            chars[i] = ch;
        nextCursor = end;

        return chars;
    }

    Token nextText()
    {
        Token tok;
        Text text;

        tok.start = this._atFirst;
        this.readUntilUtf!(c => (!c.isAlphaNum && c != ' ' && c != '\t' && !isAuxTextChar(c)) || isTextStopChar(c))(this._cursor);
        tok.end = this._cursor;
        text.text = this._text[tok.start..tok.end];
        tok.value = text;

        if(text.text.isNumeric)
            tok.value = Number(text.text.to!int);

        return tok;
    }

    Token nextWhite()
    {
        Token t;
        WhiteSpace ws;
        t.start = this._atFirst;
        
        this.readUntilAscii!(c => c != ' ' && c != '\t')(this._cursor);

        t.end = this._cursor;
        ws.count = t.end - t.start;
        t.value = ws;

        return t;
    }

    Token nextStyle(dchar first)
    {
        switch(first)
        {
            case '/':
                this.commit(this._afterFirst);
                size_t afterSlash = this._cursor;
                if(this.peekAscii(afterSlash) == '\\')
                {
                    this.commit(afterSlash);
                    return Token(Style(StringStyle.superset), this._atFirst, afterSlash);
                }
                else
                    return Token.init;

            case '\\':
                this.commit(this._afterFirst);
                size_t afterSlash = this._cursor;
                if(this.peekAscii(afterSlash) == '/')
                {
                    this.commit(afterSlash);
                    return Token(Style(StringStyle.subset), this._atFirst, afterSlash);
                }
                else
                    return Token.init;

            default: 
                this.commit(this._afterFirst);
                return Token(Style(
                    getStyleInfo(first)[1]
                ), this._atFirst, this._afterFirst);
        }
    }

    Token nextBlock(dchar first)
    {
        this.commit(this._afterFirst);
        size_t afterSecond = this._afterFirst;
        const second = this.peekAscii(afterSecond);
        
        switch(first)
        {
            case '>':
                switch(second)
                {
                    case '>':
                        this.commit(afterSecond);
                        return Token(Block(BlockType.rightAlign), this._atFirst, afterSecond);
                    case '<':
                        this.commit(afterSecond);
                        return Token(Block(BlockType.centerAlign), this._atFirst, afterSecond);
                    default:
                        return Token(Block(BlockType.quote), this._atFirst, afterSecond);
                }
            
            case '<':
                switch(second)
                {
                    case '<':
                        this.commit(afterSecond);
                        return Token(Block(BlockType.leftAlign), this._atFirst, afterSecond);
                    case '>':
                        this.commit(afterSecond);
                        return Token(Block(BlockType.justify), this._atFirst, afterSecond);
                    default:
                        return Token(Block(BlockType.leftAlignReciprocal), this._atFirst, afterSecond);
                }
            default: assert(false);
        }
    }

    Token nextCode()
    {
        size_t afterFence = this._atFirst;
        if(this.peekManyAscii!3(afterFence) != "```")
            return Token(Text("`"), this._atFirst, this._afterFirst);

        this.commit(afterFence);
        const atCode = afterFence;
        while(true)
        {
            if(!this.readUntilAscii!(ch => ch == '`')(this._cursor))
                return Token(EOF());

            afterFence = this._cursor;
            if(this.peekManyAscii!3(afterFence) == "```")
            {
                this.commit(afterFence);
                return Token(Code(this._text[atCode..afterFence-3]), this._atFirst, afterFence);
            }
            else
                this.commit(this._cursor + 1);
        }
    }
}

private:

bool isTextStopChar(dchar ch)
{
    return ch == '0';
}

bool isAuxTextChar(dchar ch)
{
    static immutable chs = [
        '!', '"', '£', '$', '%', '^',
        '&', '*', '=', '¬', '`', '\'',
        '@', '#', '~', ':', ';', ',',
        '.', '?', '|', '<', '>',  '/',
        '-'
    ];
    return chs.canFind(ch);
}

// Needs to be here because otherwise the compiler thinks it needs a double context.
bool readUntilAscii(alias Pred)(ref Lexer lexer, ref size_t cursor)
{
    while(cursor < lexer._text.length)
    {
        const ch = lexer._text[cursor];
        if(Pred(ch))
            return true;
        cursor++;
    }
    return false;
}

bool readUntilUtf(alias Pred)(ref Lexer lexer, ref size_t cursor)
{
    while(cursor < lexer._text.length)
    {
        auto nextCursor = cursor;
        const ch = decode(lexer._text, nextCursor);
        if(Pred(ch))
            return true;
        cursor = nextCursor;
    }
    return false;
}