module app;

import std : Nullable;
import jcli : CommandDefault, CommandPositionalArg, CommandNamedArg, Result, CommandHelpText, CommandParser;
import lexer, syntax;

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
            import std;
            auto lexer = Lexer(test.input);

            // DEBUG
            auto ast = syntax.parse(lexer);
            writeln(*ast);
            writeln();
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
    import std       : splitter, filter, all, array, map, countUntil, byCodeUnit, until;
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
            .until!(test => test.input == "@ ") // Allow myself to limit test cases until I've worked on the code to parse them
            .array;

    return typeof(return).success(cases);
}