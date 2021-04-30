#include <string>
using namespace std::string_literals;
//#define WIN32_LEAN_AND_MEAN
//#define NOMINMAX
//#include <windows.h>
#include <vector>
#include <list>
#include <numeric>
#include <algorithm>
#include <iostream>
//#define assert(...) do {} while(false)
#include <assert.h>


class Exception
{
public:
    std::string message;
    int line, column, pos;

    Exception(const std::string &message, int line, int column, int pos) :
        message(message), line(line), column(column), pos(pos) {}
};

class StringLiteral
{
public:
    const char *s;
    int len;
    template <int N> StringLiteral(const char (&s)[N]) : s(s), len(N-1) {}
};

template <int oldN, int newN> std::string &&replace_all(std::string &&str, const char (&old)[oldN], const char (&n)[newN])
{
    size_t start_pos = 0;
    while((start_pos = str.find(old, start_pos)) != str.npos) {
        str.replace(start_pos, oldN-1, n, newN-1);
        start_pos += newN-1;
    }
    return std::move(str);
}

std::string &&html_escape(std::string &&str)
{
    replace_all(std::move(str), "&", "&amp;");
    replace_all(std::move(str), "<", "&lt;");
    return std::move(str);
};

std::string &&html_escapeq(std::string &&str)
{
    replace_all(std::move(str), "&", "&amp;");
    replace_all(std::move(str), "\"", "&quot;");
    return std::move(str);
};

std::string substr(const std::string &s, int start, int end)
{
    return s.substr(start, end - start);
}

bool starts_with(const std::string &str, const char *s, size_t sz)
{
    return str.length() >= (int)sz && memcmp(str.data(), s, sz*sizeof(char)) == 0;
}
template <int N> bool starts_with(const std::string &str, const char (&s)[N])
{
    return starts_with(str, s, N-1);
}

template <class ValTy, class Ty1, class Ty2> bool in(const ValTy &val, const Ty1 &t1, const Ty2 &t2)
{
    return val == t1 || val == t2;
}
template <class ValTy, class Ty1, class Ty2, class Ty3> bool in(const ValTy &val, const Ty1 &t1, const Ty2 &t2, const Ty3 &t3)
{
    return val == t1 || val == t2 || val == t3;
}
template <int N> bool in(char c, const char(&s)[N])
{
    for (int i=0; i<N-1; i++)
        if (c == s[i])
            return true;
    return false;
}

// [https://github.com/nim-lang/Nim/blob/version-1-4/lib/pure/unicode.nim#L54 <- https://nim-lang.org/docs/unicode.html]
int rune_len_at(const std::string &s, int i)
{
    unsigned c = (unsigned char)s[i];
    if (c <= 127) return 1;
    if (c >> 5 == 0b110) return 2;
    if (c >> 4 == 0b1110) return 3;
    if (c >> 3 == 0b11110) return 4;
    assert(false);
    __assume(0); // suppress warning C4715
}

class Converter
{
    std::vector<int> to_html_called_inside_to_html_outer_pos_arr;
    bool ohd;
    const std::string *instr = nullptr;

public:
    Converter(bool ohd) : ohd(ohd) {}

    std::string to_html(const std::string &instr, FILE *outfilef = NULL, int outer_pos = 0)
    {
        to_html_called_inside_to_html_outer_pos_arr.push_back(outer_pos);

        std::list<std::string> result; // this should be faster than using regular string
        size_t result_total_len = 0;
        auto write = [&result, &result_total_len](std::string &&s) {
            result_total_len += s.length();
            result.push_back(std::move(s));
        };

        if (to_html_called_inside_to_html_outer_pos_arr.size() == 1)
            this->instr = &instr;

        auto exit_with_error = [this](const std::string &message, int pos)
        {
            pos += std::accumulate(to_html_called_inside_to_html_outer_pos_arr.begin(), to_html_called_inside_to_html_outer_pos_arr.end(), 0);
            int line = 1;
            int line_start = -1;
            int t = 0;
            while (t < pos) {
                if ((*this->instr)[t] == '\n') {
                    line++;
                    line_start = t;
                }
                t++;
            }
            throw Exception(message, line, pos - line_start, pos);
        };

        int i = 0;
        auto next_char = [&i, &instr](int offset = 1) {
            return i + offset < instr.length() ? instr[i + offset] : '\0';
        };

        auto i_next_str3 = [&i, &instr](const StringLiteral s) {
            return i + 3 + s.len <= instr.length() && memcmp(instr.c_str() + i + 3, s.s, s.len) == 0;
        };

        auto i_next_str = [&i, &instr](const StringLiteral s) {
            return i + 1 + s.len <= instr.length() && memcmp(instr.c_str() + i + 1, s.s, s.len) == 0;
        };

        auto ch_is = [&i, &instr](const StringLiteral s) {
            return i + s.len <= instr.length() && memcmp(instr.c_str() + i, s.s, s.len) == 0;
        };

        auto prev_char = [&i, &instr](int offset = 1) {
            return i - offset >= 0 ? instr[i - offset] : '\0';
        };

        int writepos = 0;
        auto write_to_pos = [&instr, &write, &writepos](int pos, int npos)
        {
            write(html_escape(instr.substr(writepos, pos - writepos)));
            writepos = npos;
        };

        auto write_to_i = [&i, &write, &instr, &write_to_pos](std::string &&add_str)
        {
            assert(rune_len_at(instr, i) == 1);
            write_to_pos(i, i + 1);
            write(std::move(add_str));
        };

        auto find_ending_pair_quote = [&exit_with_error, &instr](int i)
        {
            assert(memcmp(&instr[i], u8"‘", 3) == 0); // ’
            int startqpos = i;
            int nesting_level = 0;
            while (true) {
                if (i >= instr.length() - 2)
                    exit_with_error("Unpaired left single quotation mark", startqpos);
                if (memcmp(&instr[i], u8"‘", 3) == 0)
                    nesting_level++;
                else if (memcmp(&instr[i], u8"’", 3) == 0)
                    if (--nesting_level == 0)
                        return i;
                i++;
            }
        };

        auto find_ending_sq_bracket = [&exit_with_error](const std::string &str, int i, int start = 0)
        {
            int starti = i;
            assert(str[i] == '['); // ]
            int nesting_level = 0;
            while (true) {
                switch (str[i])
                {
                case '[':
                    nesting_level++;
                    break;
                case ']':
                    if (--nesting_level == 0)
                        return i;
                    break;
                }
                i++;
                if (i == str.length())
                    exit_with_error("Unended comment started", start + starti);
            }
        };

        auto remove_comments = [&find_ending_sq_bracket](std::string &&s, int start, int level = 3) -> std::string&&
        {
            std::string brackets(level, '['); // ]
            while (true) {
                size_t j = s.find(brackets);
                if (j == s.npos)
                    break;
                int k = find_ending_sq_bracket(s, (int)j, start) + 1;
                start += k - (int)j;
                s.erase(j, k - j);
            }
            return std::move(s);
        };

        std::string link;

        auto write_http_link = [&exit_with_error, &find_ending_pair_quote, &find_ending_sq_bracket, &i, &instr, &link, &i_next_str, &write, &remove_comments, &write_to_pos, this](int startpos, int endpos, int q_offset = 3, std::string text = "")
        { // ‘
            assert(memcmp(&instr[i], u8"’[", 4) == 0 || instr[i] == '['); // ]]
            int nesting_level = 0;
            i += 4;
            while (true) {
                if (i == instr.length())
                    exit_with_error("Unended link", endpos + q_offset);
                switch (instr[i])
                {
                case '[':
                    nesting_level++;
                    break;
                case ']':
                    if (nesting_level == 0)
                        goto break_;
                    nesting_level--;
                    break;
                case ' ':
                    goto break_;
                    break;
                }
                i++;
            }
            break_:;
            link = html_escapeq(substr(instr, endpos + 1 + q_offset, i));
            auto tag = "<a href=\"" + link + "\"";
            if (starts_with(link, "./"))
                tag += " target=\"_self\"";

            if (instr[i] == ' ') {
                tag += " title=\"";
                if (i_next_str(u8"‘")) {
                    int endqpos2 = find_ending_pair_quote(i + 1); // [[
                    if (instr[endqpos2 + 3] != ']')
                        exit_with_error("Expected `]` after `’`", endqpos2 + 3);
                    tag += html_escapeq(remove_comments(substr(instr, i + 4, endqpos2), i + 4));
                    i = endqpos2 + 3;
                }
                else {
                    int endb = find_ending_sq_bracket(instr, endpos + q_offset);
                    tag += html_escapeq(remove_comments(substr(instr, i + 1, endb), i + 1));
                    i = endb;
                }
                tag += "\"";
            }
            if (i_next_str(u8"[-")) {
                int j = i + 3;
                while (j < instr.length()) {
                    if (instr[j] == ']') {
                        i = j;
                        break;
                    }
                    if (!isdigit(instr[j]))
                        break;
                    j++;
                }
            }
            if (text.empty()) {
                write_to_pos(startpos, i + 1);
                text = to_html(substr(instr, startpos + q_offset, endpos), nullptr, startpos + q_offset);
            }
            write(tag + ">" + (!text.empty() ? text : link) + "</a>");
        };

        auto write_abbr = [&exit_with_error, &find_ending_pair_quote, &i, &instr, &write, &remove_comments, &write_to_pos](int startpos, int endpos, int q_offset = 3)
        {
            i += q_offset;
            int endqpos2 = find_ending_pair_quote(i + 1); // [[
            if (instr[endqpos2 + 3] != ']') // ‘
                exit_with_error("Bracket ] should follow after ’", endqpos2 + 3);
            write_to_pos(startpos, endqpos2 + 4);
            write("<abbr title=\"" + html_escapeq(remove_comments(substr(instr, i + 4, endqpos2), i + 4)) + "\">" + html_escape(remove_comments(substr(instr, startpos + q_offset, endpos), startpos + q_offset)) + "</abbr>");
            i = endqpos2 + 3;
        };

        std::vector<std::string> ending_tags;
        std::string new_line_tag = std::string(1, '\0');

        while (i < instr.length()) {
            char ch = instr[i];
            if ((i == 0 || prev_char() == '\n' || (i == writepos && !ending_tags.empty() && in(ending_tags.back(), "</blockquote>", "</div>")) && in(instr.substr(i - 4, 4), u8">‘", u8"<‘", u8"!‘"))) { // ’’’
                if (ch == '.' && next_char() == ' ')
                    write_to_i(u8"•");
                else if (in(ch, '>', '<') && (in(next_char(), " [") || i_next_str(u8"‘"))) { // ]’
                    write_to_pos(i, i + 2/* + (i_next_str(u8"‘") ? 2 : 0)*/); // ’
                    write("<blockquote"s + (ch == '<' ? " class=\"re\"" : "") + ">");
                    if (next_char() == ' ')
                        new_line_tag = "</blockquote>";
                    else {
                        if (next_char() == '[') {
                            if (next_char(2) == '-' && isdigit(next_char(3))) {
                                i = (int)instr.find(']', i + 4) + 1;
                            }
                            else {
                                i++;
                                int endb = find_ending_sq_bracket(instr, i);
                                link = substr(instr, i + 1, endb);
                                size_t spacepos = link.find(' ');
                                if (spacepos != link.npos)
                                    link = link.substr(0, spacepos);
                                int link_length = 0, pos46;
                                for (int i = 0; i < link.length();) {
                                    link_length++;
                                    i += rune_len_at(link, i);
                                    if (link_length == 46)
                                        pos46 = i;
                                }
                                if (link_length > 57)
                                    link = link.substr(0, link.rfind('/', pos46) + 1) + "...";
                                write_http_link(i, i, 0, "<i>" + link + "</i>");
                                i++;
                                if (instr.substr(i, 4) != u8":‘") // ’
                                    exit_with_error("Quotation with url should always has :‘...’ after [http(s)://url]", i);
                                write(":<br />\n");
                            }
                        }
                        else {
                            int endqpos = find_ending_pair_quote(i + 1);
                            if (instr[endqpos + 3] == '[') { // ]
                                int startqpos = i + 1;
                                i = endqpos;
                                write("<i>");
                                assert(writepos == startqpos + 1);
                                writepos = startqpos;
                                write_http_link(startqpos, endqpos);
                                write("</i>");
                                i++;
                                if (instr.substr(i, 4) != u8":‘") // ’
                                    exit_with_error("Quotation with url should always has :‘...’ after [http(s)://url]", i);
                                write(":<br />\n");
                            }
                            else if (instr[endqpos + 3] == ':') {
                                write("<i>" + substr(instr, i + 4, endqpos) + "</i>:<br />\n");
                                i = endqpos + 3;
                                if (instr.substr(i, 4) != u8":‘") // ’
                                    exit_with_error("Quotation with author's name should be in the form >‘Author's name’:‘Quoted text.’", i);
                            }
                        }
                        writepos = i + 4;
                        ending_tags.push_back("</blockquote>");
                    }
                    i++;
                    i += rune_len_at(instr, i);
                    continue;
                }
            }

            if (ch_is(u8"‘")) {
                int prevci = i - 1;
                char prevc = '\0', prevc2[2] = "\0";
                if (prevci >= 0) {
                    if ((instr[prevci] & 0b1100'0000) == 0b1000'0000) { // this is a continuation byte
                        prevci -= 1;
                        //assert((instr[prevci] & 0b1100'0000) != 0b1000'0000);
                        //assert((instr[prevci] & 0b1110'0000) == 0b1100'0000);
                    //  prevc  = instr[prevci];
                    //  prevc2 = instr[prevci + 1];
                        prevc2[0] = instr[prevci];
                        prevc2[1] = instr[prevci + 1];
                    }
                    else
                        prevc = instr[prevci];
                }
                int startqpos = i;
                i = find_ending_pair_quote(i);
                int endqpos = i;
                std::string str_in_p; // (
                if (prevc == ')') {
                    size_t openp = instr.rfind('(', prevci - 1); // )
                    if (openp != instr.npos && openp > 0) {
                        str_in_p = substr(instr, (int)openp + 1, startqpos - 1);
                        prevci = (int)openp - 1;
                        prevc = instr[prevci];
                        if ((prevc & 0b1100'0000) == 0b1000'0000) { // this is a continuation byte
                            prevci -= 1;
                            prevc2[0] = instr[prevci];
                            prevc2[1] = instr[prevci + 1];
                        }
                    }
                }
                if (i_next_str3("[http") || i_next_str3("[./")) // ]]
                    write_http_link(startqpos, endqpos);
                else if (i_next_str3(u8"[‘")) // ’]
                    write_abbr(startqpos, endqpos);
                else if (in(prevc, "0O") || /*(prevc == u8"О"[0] && prevc2 == u8"О"[1])*/memcmp(prevc2, u8"О", 2) == 0) {
                    write_to_pos(prevci, endqpos + 3);
                    write(replace_all(html_escape(substr(instr, startqpos + 3, endqpos)), "\n", "<br />\n"));
                }
                else if (in(prevc, "<>") && prevci >= 1 && in(instr[prevci - 1], "<>")) {
                    write_to_pos(prevci - 1, endqpos + 3);
                    auto a = std::string(1, instr[prevci - 1]) + prevc;
                    write("<div align=\""s + (a == "<<" ? "left" : a == ">>" ? "right" : a == "><" ? "center" : "justify") + "\">" + (to_html(substr(instr, startqpos + 3, endqpos), nullptr, startqpos + 3)) + "</div>\n");
                    new_line_tag = "";
                }
                else if (i_next_str3(u8":‘") && instr.substr(find_ending_pair_quote(i + 4) + 3, 1) == "<") {
                    int endrq = find_ending_pair_quote(i + 4);
                    i = endrq + 3;
                    write_to_pos(prevci + 1, i + 1);
                    write("<blockquote>" + to_html(substr(instr, startqpos + 3, endqpos), nullptr, startqpos + 3) + "<br />\n<div align='right'><i>" + substr(instr, endqpos + 7, endrq) + "</i></div></blockquote>");
                    new_line_tag = "";
                }
                else {
                    i = startqpos;
                    if (in(prevc, "*_-~")) {
                        write_to_pos(i - 1, i + 3);
                        char tag = prevc == '*' ? 'b' : prevc == '_' ? 'u' : prevc == '-' ? 's' : 'i';
                        write("<"s + tag + ">");
                        ending_tags.push_back("</"s + tag + ">");
                    }
                    else if (prevc == 'H' || /*(prevc == u8"Н"[0] && prevc2 == u8"Н"[1])*/memcmp(prevc2, u8"Н", 2) == 0) {
                        write_to_pos(prevci, i + 3);
                        int h = 0;
                        if (!str_in_p.empty())
                            if (str_in_p[0] == '-')
                                h = -(str_in_p[1] - '0');
                            else if (str_in_p[0] == '+')
                                h = str_in_p[1] - '0';
                            else
                                h = str_in_p[0] - '0';
                        auto tag = "h"s + char('0' + std::min(std::max(3 - h, 1), 6));
                        write("<" + tag + ">");
                        ending_tags.push_back("</" + tag + ">");
                    }
                    else if (prevci >= 1 && in(instr.substr(prevci - 1, 2), "/\\", "\\/")) {
                        write_to_pos(prevci - 1, i + 3);
                        auto tag = instr.substr(prevci - 1, 2) == "/\\" ? "sup" : "sub";
                        write("<"s + tag + ">");
                        ending_tags.push_back("</"s + tag + ">");
                    }
                    else if (prevc == '!') {
                        write_to_pos(prevci, i + 3);
                        write("<div class=\"note\">");
                        ending_tags.push_back("</div>");
                    }
                    else
                        ending_tags.push_back(u8"’");
                }
            }
            else if (ch_is(u8"’")) {
                write_to_pos(i, i + 3);
                if (ending_tags.empty())
                    exit_with_error("Unpaired right single quotation mark", i);
                auto last = std::move(ending_tags.back());
                ending_tags.pop_back();
                if (next_char(3) == '\n' && (starts_with(last, "</h") || in(last, "</blockquote>", "</div>"))) {
                    write(std::move(last));
                    write("\n");
                    i += 3;
                    assert(rune_len_at(instr, writepos) == 1);
                    writepos++;
                }
                else
                    write(std::move(last));
            }
            else if (ch == '`') {
                int start = i;
                i++;
                while (i < instr.length()) {
                    if (instr[i] != '`')
                        break;
                    i++;
                }
                size_t end = instr.find(std::string(i - start, '`'), i);
                if (end == instr.npos)
                    exit_with_error("Unended ` started", start);
                write_to_pos(start, (int)end + i - start);
                auto ins = substr(instr, i, (int)end);
                int delta = 0;
                if (ins.length() >= 3)
                    for (size_t i = 0, n = ins.length() - 2; i < n; i++)
                        if (memcmp(&ins[i], u8"‘", 3) == 0)
                            delta++;
                        else if (memcmp(&ins[i], u8"’", 3) == 0)
                            delta--;
                if (delta > 0)
                    for (int i = 0; i < delta; i++) // ‘‘
                        ending_tags.push_back(u8"’");
                else
                    for (int i = 0; i < -delta; i++) {
                        if (ending_tags.back() != u8"’")
                            exit_with_error("Unpaired single quotation mark found inside code block/span beginning", start);
                        ending_tags.pop_back();
                    }
                ins = html_escape(std::move(ins));
                if (ins.find('\n') == ins.npos)
                    write("<pre class=\"inline_code\">" + ins + "</pre>");
                else {
                    write("<pre>" + ins + "</pre>\n");
                    new_line_tag = "";
                }
                i = (int)end + i - start - 1;
            }
            else if (ch == '[') { // ]
                if (i_next_str("http") || i_next_str("./") || (i_next_str(u8"‘") && !in(prev_char(), "\r\n\t \0"))) {
                    int s = i - 1;
                    while (s >= writepos && !in(instr[s], "\r\n\t [{(")) // )}]
                        s--;
                    if (i_next_str(u8"‘"))
                        write_abbr(s + 1, i, 0);
                    else if (i_next_str(u8"http") || i_next_str(u8"./"))
                        write_http_link(s + 1, i, 0);
                    else
                        assert(false);
                }
                else if (i_next_str(u8"[[")) { // ]]
                    int comment_start = i;
                    int nesting_level = 0;
                    while (true) {
                        char c = instr[i];
                        if (c == '[')
                            nesting_level++;
                        else if (c == ']') {
                            if (--nesting_level == 0)
                                break;
                        }
                        else if (c == u8"‘"[0] && instr[i+1] == u8"‘"[1] && instr[i+2] == u8"‘"[2])
                            ending_tags.push_back(u8"’");
                        else if (c == u8"’"[0] && instr[i + 1] == u8"’"[1] && instr[i + 2] == u8"’"[2]) {
                            assert(ending_tags.back() == u8"’");
                            ending_tags.pop_back();
                        }
                        i++;
                        if (i == instr.length())
                            exit_with_error("Unended comment started", comment_start);
                    }
                    write_to_pos(comment_start, i + 1);
                }
                else
                    write_to_i((ohd ? "<span class=\"sq\"><span class=\"sq_brackets\">"s : ""s) + "[" + (ohd ? "</span>" : ""));
            }
            else if (ch == ']') // [
                write_to_i((ohd ? "<span class=\"sq_brackets\">"s : ""s) + "]" + (ohd ? "</span></span>" : ""));
            else if (ch == '{')
                write_to_i((ohd ? "<span class=\"cu_brackets\" onclick=\"return spoiler(this, event)\"><span class=\"cu_brackets_b\">"s : ""s) + "{" + (ohd ? u8"</span><span>…</span><span class=\"cu\" style=\"display: none\">" : ""));
            else if (ch == '}')
                write_to_i((ohd ? "</span><span class=\"cu_brackets_b\">"s : ""s) + "}" + (ohd ? "</span></span>" : ""));
            else if (ch == '\n') {
                write_to_i((new_line_tag != std::string(1, '\0') ? new_line_tag : "<br />"s) + (new_line_tag != "" ? "\n" : ""));
                new_line_tag = std::string(1, '\0');
            }
            i += rune_len_at(instr, i);
        }

        write_to_pos((int)instr.length(), 0);
        if (!ending_tags.empty())
            exit_with_error("Unclosed left single quotation mark somewhere", (int)instr.length());
        assert(to_html_called_inside_to_html_outer_pos_arr.back() == outer_pos);
        to_html_called_inside_to_html_outer_pos_arr.pop_back();

        std::string result_str;
        result_str.reserve(result_total_len);
        for (auto &&it : result)
            result_str += it;

        if (outfilef == NULL)
            return result_str;

        fwrite(result_str.data(), result_str.size(), 1, outfilef);
        return "";
    }
};

auto to_html(const std::string &instr, FILE *outfilef = NULL, bool ohd = false)
{
    return Converter(ohd).to_html(instr, outfilef);
}

template <int N> void write_to_file(FILE *file, const char(&s)[N])
{
    fwrite(s, N-1, 1, file);
}

// [https://stackoverflow.com/a/46931770/2692494 <- google:‘c++ split’]
std::vector<std::string> split(const std::string &s, const std::string &delimiter)
{
    size_t pos_start = 0, pos_end, delim_len = delimiter.length();
    std::string token;
    std::vector<std::string> res;

    while ((pos_end = s.find(delimiter, pos_start)) != std::string::npos) {
        token = s.substr(pos_start, pos_end - pos_start);
        pos_start = pos_end + delim_len;
        res.push_back(token);
    }

    res.push_back(s.substr(pos_start));
    return res;
}

int main(int argc, char *argv[])
{
    if (argc == 2 && strcmp(argv[1], "-t") == 0) {
        FILE *tests_file = NULL;
        fopen_s(&tests_file, "../../tests.txt", "rb");
        fseek(tests_file, 0, SEEK_END);
        size_t tests_file_size = ftell(tests_file);
        fseek(tests_file, 0, SEEK_SET);
        std::string tests_file_str;
        tests_file_str.resize(tests_file_size);
        fread(const_cast<char*>(tests_file_str.data()), tests_file_size, 1, tests_file);
        fclose(tests_file);

        std::string delim = " (()) ";

        int tests_cnt = 0;
        for (auto &&test : split(tests_file_str, "|\n\n|")) {
            tests_cnt++;
            size_t delim_pos = test.find(delim);
            std::string left = test.substr(0, delim_pos),
                       right = test.substr(delim_pos + delim.length());
            if (to_html(left) != right) {
                std::cerr << "Error in test #" << tests_cnt << "\n";
                return -1;
            }
        }
        std::cout << "All of " << tests_cnt << " tests are passed!\n";
        return 0;
    }

    if (argc < 3) {
        std::cout << "Usage: pqmarkup_lite input-file output-file\n";
        return 0;
    }

    FILE *infile = NULL;
    fopen_s(&infile, argv[1], "rb");
    fseek(infile, 0, SEEK_END);
    size_t infile_size = ftell(infile);
    fseek(infile, 0, SEEK_SET);

    std::string file_str;
    unsigned char utf8bom[3] = {0xEF, 0xBB, 0xBF}, first3bytes[3] = {0};
    size_t _ = fread(first3bytes, 3, 1, infile);
    if (memcmp(first3bytes, utf8bom, 3) == 0)
        infile_size -= 3;
    else
        fseek(infile, 0, SEEK_SET);
    file_str.resize(infile_size);
    _ = fread(const_cast<char*>(file_str.data()), infile_size, 1, infile);
    fclose(infile);

    FILE *outfile = NULL;
    fopen_s(&outfile, argv[2], "wb");
    write_to_file(outfile, u8R"(<html>
<head>
<meta charset="utf-8" />
<base target="_blank">
<script type="text/javascript">
function spoiler(element, event)
{
    if (event.target.nodeName == 'A' || event.target.parentNode.nodeName == 'A' || event.target.onclick)//for links in spoilers and spoilers2 in spoilers to work
        return;
    var e = element.firstChild.nextSibling.nextSibling;//element.getElementsByTagName('span')[0]
    e.previousSibling.style.display = e.style.display;//<span>…</span> must have inverted display style
    e.style.display = (e.style.display == "none" ? "" : "none");
    element.firstChild.style.fontWeight =
    element. lastChild.style.fontWeight = (e.style.display == "" ? "normal" : "bold");
    event.stopPropagation();
}
</script>
<style type="text/css">
div#main, td {
    font-size: 14px;
    font-family: Verdana, sans-serif;
    line-height: 160%;
    text-align: justify;
}
span.cu_brackets_b {
    font-size: initial;
    font-family: initial;
    font-weight: bold;
}
a {
    text-decoration: none;
    color: #6da3bd;
}
a:hover {
    text-decoration: underline;
    color: #4d7285;
}
h1, h2, h3, h4, h5, h6 {
    margin: 0;
    font-weight: 400;
}
h1 {font-size: 200%; line-height: 130%;}
h2 {font-size: 180%; line-height: 135%;}
h3 {font-size: 160%; line-height: 140%;}
h4 {font-size: 145%; line-height: 145%;}
h5 {font-size: 130%; line-height: 140%;}
h6 {font-size: 120%; line-height: 140%;}
span.sq {color: gray; font-size: 0.8rem; font-weight: normal; /*pointer-events: none;*/}
span.sq_brackets {color: #BFBFBF;}
span.cu_brackets {cursor: pointer;}
span.cu {background-color: #F7F7FF;}
abbr {text-decoration: none; border-bottom: 1px dotted;}
pre {margin: 0;}
pre, code {font-family: 'Courier New'; line-height: normal}
ul, ol {margin: 11px 0 7px 0;}
ul li, ol li {padding: 7px 0;}
ul li:first-child, ol li:first-child {padding-top   : 0;}
ul  li:last-child, ol  li:last-child {padding-bottom: 0;}
table {margin: 9px 0; border-collapse: collapse;}
table th, table td {padding: 6px 13px; border: 1px solid #BFBFBF;}
span.spoiler_title {
    color: #548eaa;
    cursor: pointer;
    border-bottom: 1px dotted;
}
div.spoiler_text {
    /*border: 1px dotted;*/
    margin: 5px;
    padding: 3px;
}
blockquote {
    margin: 0 0 7px 0;
    padding: 7px 12px;
}
blockquote:not(.re) {border-left:  0.2em solid #C7EED4; background-color: #FCFFFC;}
blockquote.re       {border-right: 0.2em solid #C7EED4; background-color: #F9FFFB;}
div.note {
    padding: 18px 20px;
    background: #ffffd7;
}
pre.code_block {padding: 6px 0;}
pre.inline_code {
    display: inline;
    padding: 0px 3px;
    border: 1px solid #E5E5E5;
    background-color: #FAFAFA;
    border-radius: 3px;
}
img {vertical-align: middle;}

div#main {width: 100%;}
@media screen and (min-width: 750px) {
    div#main {width: 724px;}
}
</style>
</head>
<body>
<div id="main" style="margin: 0 auto">
)");
    try {
        to_html(file_str, outfile, true);
    }
    catch (const Exception &e) {
        std::cerr << e.message << " at line " << e.line << ", column " << e.column << "\n";
        return -1;
    }

    write_to_file(outfile, u8R"(</div>
</body>
</html>)");

    fclose(outfile);
}
