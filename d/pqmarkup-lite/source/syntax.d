module syntax;

import std.sumtype, std.exception, std.typecons;
import lexer, tokens, ast;

alias WasConsumed = Flag!"wasConsumed";

AstNode* parse(Lexer lexer)
{
    auto tokens = lexer.toTokens(); // We'll be starting from the bottom.
    auto visitor = Visitor(true);
    foreach_reverse(tok; tokens)
    {
    debug import std.stdio;
        writeln(tok);
        visitor.visit(tok);
    }
    visitor.finish();
    return visitor.root;
}

private:

Token[] toTokens(Lexer lexer)
{
    Token[] tokens;
    const eof = TokenValue(EOF());
    while(true)
    {
        auto next = lexer.next();
        if(next.value == eof)
            break;
        else
            tokens ~= next;
    }

    return tokens;
}

struct Visitor
{
    enum State
    {
        default_,
        parsingHeader,
        parsingLinkOrAbbrOrText // yep, link syntax is that ambiguous
    }

    AstNode* root;
    AstNode*[] nodeStack;
    AstNode* currentNode;
    uint stringNest;
    Token lastToken;
    State state;

    this(bool __dummy)
    {
        this.currentNode = new AstNode();
        this.root = this.currentNode;
        
        auto lastLine = new AstNode(null, AstNewLine());
        this.root.addChild(lastLine);
        this.pushNode(lastLine);
    }
    
    void pushNode(AstNode* node)
    {
        this.nodeStack ~= this.currentNode;
        this.currentNode = node;
    }

    void popCurrentNode()
    {
        this.currentNode = this.nodeStack[$-1];
        this.nodeStack.length--;
    }

    void visit(Token token)
    {
        final switch(this.state) with(State)
        {
            case default_: this.visitDefault(token); break;
            case parsingHeader: this.visitHeader(token); break;
            case parsingLinkOrAbbrOrText: this.visitTheUniverse(token); break;
        }
        
        lastToken = token;
    }

    void visitDefault(Token token)
    {
        token.value.match!(
            (CloseSParen sp)
            {
                this.state = State.parsingLinkOrAbbrOrText;
                auto node = new AstNode(null, AstInconclusive());
                this.currentNode.addChild(node);
                this.pushNode(node);
            },
            (CloseCParen cp)
            {
                this.currentNode.children[$-1].value.match!(
                    (AstString str)
                    {
                        this.state = State.parsingHeader;
                    },
                    (_) { auto node = new AstNode(null, AstText(")")); }
                );
            },
            (CapitalH ch)
            {
                this.currentNode.children[$-1].value.match!(
                    (AstString str)
                    {
                        auto node = new AstNode(null, AstHeader(3));
                        node.addChild(this.currentNode.children[$-1]);
                        this.currentNode.addChild(node);
                    },
                    (_)
                    {
                        auto node = new AstNode(null, AstText("H"));
                        this.currentNode.addChild(node);
                    }
                );
            },
            (Style st)
            {
                auto node = new AstNode(
                    null,
                    AstStyle(st.style)
                );

                bool addAsText = true;
                if(this.currentNode.children.length)
                {
                    this.currentNode.children[$-1].value.match!(
                        (AstString str)
                        {
                            addAsText = false;
                            node.addChild(this.currentNode.children[$-1]);
                            this.currentNode.addChild(node);
                        },
                        (ref AstNumber number)
                        {
                            if(st.style != StringStyle.strike)
                                return;

                            addAsText = false;
                            number.value *= -1;
                        },
                        (_) {}
                    );
                }

                if(addAsText)
                {
                    // this.currentNode.addChild(node);
                    // TODO:
                }
            },
            (OpenQuote oq)
            {
                enforce(this.stringNest-- > 0, "Unterminated string.");
                this.currentNode.value.match!(
                    (AstString _)
                    {
                        this.popCurrentNode();
                    }, 
                    (_){ throw new Exception("Expected currentNode to be a string."); }
                );
            },
            (Text te)
            {
                auto me = new AstNode(
                    null,
                    AstText(te.text)
                );
                if(!this.handleInconclusiveNode || this.semanticInconclusive(me) == WasConsumed.no)
                    this.currentNode.addChild(me);
            },
            (CloseQuote cq)
            {
                auto node = new AstNode(null, AstString());
                if(!this.handleInconclusiveNode|| this.semanticInconclusive(node) == WasConsumed.no)
                    this.currentNode.addChild(node);
                this.stringNest++;
                this.pushNode(node);
            },
            (Dot dot)
            {
                this.currentNode.addChild(new AstNode(null, AstDot()));
            },
            (WhiteSpace ws)
            {
                this.currentNode.addChild(new AstNode(null, AstWhiteSpace()));
            },
            (NewLine nl)
            {
                auto nextLine = new AstNode(null, AstNewLine());
                this.currentNode.value.match!(
                    (AstNewLine _)
                    {
                        if(this.currentNode.children.length)
                        {
                            this.currentNode.children[$-1].value.match!(
                                (AstBlock block)
                                {
                                    AstNode* wrapperNode = new AstNode();
                                    final switch(block.type) with(BlockType)
                                    {
                                        case leftAlignReciprocal:
                                        case none: return;
                                        case leftAlign:     wrapperNode.value = AstBlock(leftAlign); break;
                                        case rightAlign:    wrapperNode.value = AstBlock(rightAlign); break;
                                        case justify:       wrapperNode.value = AstBlock(justify); break;
                                        case centerAlign:   wrapperNode.value = AstBlock(centerAlign); break;
                                        case quote:         wrapperNode.value = AstBlock(quote); break;
                                    }
                                    this.currentNode.children.length--;
                                    while(this.currentNode.children.length)
                                        wrapperNode.addChild(this.currentNode.children[0]);
                                    this.currentNode.addChild(wrapperNode);
                                },
                                (AstDot dot)
                                {
                                    auto wrapperNode = new AstNode(null, AstListItem());
                                    this.currentNode.children.length--;
                                    while(this.currentNode.children.length)
                                        wrapperNode.addChild(this.currentNode.children[0]);
                                    this.currentNode.addChild(wrapperNode);
                                },
                                (_){}
                            );
                        }
                        this.popCurrentNode();
                        this.currentNode.addChild(nextLine);
                        this.pushNode(nextLine);
                    },
                    (AstBlock _)
                    {
                        this.popCurrentNode();
                    },
                    (_){ this.currentNode.addChild(nextLine); }
                );
            },
            (Block block)
            {
                if(block.type != BlockType.leftAlignReciprocal)
                {
                    bool addByItself = true;
                    if(this.currentNode.children.length)
                    {
                        addByItself = this.currentNode.children[$-1].value.match!(
                            (AstString str)
                            {
                                auto node = new AstNode(null, AstBlock(block.type));
                                node.addChild(this.currentNode.children[$-1]);
                                this.currentNode.addChild(node);
                                return false;
                            },
                            (_){ return true; }
                        );
                    }

                    if(addByItself)
                        this.currentNode.addChild(new AstNode(null, AstBlock(block.type)));
                    return;
                }

                auto node = new AstNode(null, AstBlock(block.type));
                this.currentNode.addChild(node);
                this.pushNode(node);
            },
            (Number num)
            {
                this.currentNode.addChild(new AstNode(null, AstNumber(num.value)));
            },
            (Code code)
            {
                this.currentNode.addChild(new AstNode(null, AstCode(code.text)));
            },
            (_)
            {
                import std.conv : to;
                this.currentNode.addChild(new AstNode(null, AstJunk(token.to!string, "Unhandled/Unexpected token")));
            }
        );
        if(this.handleInconclusiveNode)
            this.semanticInconclusive(null);
    }

    void finish()
    {
        if(this.handleInconclusiveNode)
            this.semanticInconclusive(null);
        this.visit(Token(NewLine())); // Fixes a few corner cases that rely on NewLine's logic.
    }

    bool handleInconclusiveNode()
    {
        return this.semanticInconclusiveNodeStack.length > 0 && this.stringNest == 0;
    }

    bool foundHeaderCount = false;
    bool foundHeaderOpenParen = false;
    void visitHeader(Token token)
    {
        import std.conv : to;
        if(!foundHeaderCount)
        {
            token.value.match!(
                (Number num)
                {
                    auto node = new AstNode(null, AstHeader(num.value));
                    node.addChild(this.currentNode.children[$-1]); // Add the AstString
                    this.currentNode.addChild(node);
                    foundHeaderCount = true;
                },
                (_)
                { 
                    this.currentNode.addChild(new AstNode(null, AstJunk(token.to!string, "Expected a number when parsing header size.")));
                    foundHeaderCount = true;
                }
            );
        }
        else if(!foundHeaderOpenParen)
        {
            const transition = token.value.match!(
                (Plus pl){ return false; },
                (Style st)
                {
                    if(st.style != StringStyle.strike)
                    {
                        this.currentNode.addChild(new AstNode(null, AstJunk(token.to!string, "Unexpected token when parsing header size sign.")));
                        return false;
                    }

                    // God I'd kill to just be able to go "value.as!AstHeader" instead of this.
                    this.currentNode.children[$-1].value.match!(
                        (ref AstHeader h){ h.isNegative = true; },
                        (_){assert(false);}
                    );
                    return false;
                },
                (OpenCParen op){ return true; },
                (_)
                {
                    this.currentNode.addChild(new AstNode(null, AstJunk(token.to!string, "Expected a '(' when parsing header size.")));
                    return true;
                }
            );
            foundHeaderOpenParen = transition;
        }
        else
        {
            token.value.match!(
                (CapitalH h)
                {
                    this.currentNode.children[$-1].value.match!(
                        (ref AstHeader h)
                        { 
                            if(h.isNegative)
                                h.size += 3;
                            else
                                h.size = 3 - h.size; 
                        },
                        (_){assert(false);}
                    );
                },
                (_)
                {
                    this.currentNode.addChild(new AstNode(null, AstJunk(token.to!string, "Expected a 'H' when parsing header.")));
                }
            );

            foundHeaderCount = false;
            foundHeaderOpenParen = false;
            this.state = State.default_;
        }
    }

    void visitTheUniverse(Token token)
    {
        // *Thankfully* you can't embed links into other links, otherwise we'd have a *very* fun time.
        // Future me: Oh god, you can.
        token.value.match!(
            (CloseSParen csp)
            {
                auto node = new AstNode(null, AstInconclusive());
                this.currentNode.addChild(node);
                this.pushNode(node);
            },
            (OpenSParen osp)
            {
                this.semanticInconclusiveNodeStack ~= this.currentNode;
                this.popCurrentNode();

                this.currentNode.value.match!(
                    (AstInconclusive _){ },
                    (_){ this.state = State.default_; }
                );
            },
            (_) 
            {
                this.visitDefault(token);
            }
        );
    }

    AstNode*[] semanticInconclusiveNodeStack;
    WasConsumed semanticInconclusive(AstNode* prefixNode)
    {
        auto semanticInconclusiveNode = semanticInconclusiveNodeStack[$-1];

        // First, see if the node prefixing the inconclusive one is some text, because that means it's for the inconclusive node.
        WasConsumed result;
        if(prefixNode)
        {
            result = prefixNode.value.match!(
                (ref node)
                {
                    static if(!is(typeof(node) == AstText) && !is(typeof(node) == AstString))
                        static assert(false); // Jank like this is why I prefer language solutions over library solutions :(

                    semanticInconclusiveNode.value.match!(
                        (ref AstInconclusive link){ link.textNode = prefixNode; },
                        (_){assert(false);}
                    );
                    return WasConsumed.yes;
                },
                (_) => WasConsumed.no
            );
        }

        // Extract the text node so we can preserve it.
        AstNode* textNode;
        semanticInconclusiveNode.value.match!(
            (ref AstInconclusive link){ textNode = link.textNode; },
            (_){assert(false);}
        );

        // Now, we have the fun of trying to figure whatever the frick this node represents.
        // Also, keep in mind we're going from bottom to top, so children[$-1] is actually children[0] lexically.
        if(semanticInconclusiveNode.children.length >= 1)
        {
            semanticInconclusiveNode.children[$-1].value.match!(
                (AstText text)
                {
                    // link or text. Appears to be determined by the format of text.text's value
                    if(isLink(text.text) || isLocalLink(text.text))
                    {
                        semanticInconclusiveNode.value = AstLink(
                            textNode,
                            text.text,
                            isLocalLink(text.text)
                        );
                    }
                    else
                        semanticInconclusiveNode.value = AstText("["~text.text~"]");
                    semanticInconclusiveNode.children.length--;
                },
                (AstString str)
                {
                    // probably an abbreviation.
                    semanticInconclusiveNode.value = AstAbbr(textNode, semanticInconclusiveNode.children[$-1]);
                    semanticInconclusiveNode.children.length--;
                },
                (AstNumber number)
                {
                    semanticInconclusiveNode.value = AstLinkRef(textNode, number.value);
                    semanticInconclusiveNode.children.length--;
                },
                (_){ /* Stay inconclusive */ }
            );
        }

        semanticInconclusiveNodeStack.length--;
        return result;
    }
}

bool isLocalLink(string text)
{
    import std.algorithm : startsWith;
    return text.startsWith("./");
}

bool isLink(string text)
{
    import std.algorithm : canFind;
    return text.canFind("://");
}