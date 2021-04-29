#include <string>
using namespace std::string_literals;
#include <codecvt>
#include <locale>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <vector>
#include <list>
#include <numeric>
#include <algorithm>
#include <iostream>
//#define assert(...) do {} while(false)
#include <assert.h>


#if (!_DLL) && (_MSC_VER >= 1900 /* VS 2015*/) && (_MSC_VER <= 1914 /* VS 2017 */)
std::locale::id std::codecvt<char16_t, char, _Mbstatet>::id; // [https://stackoverflow.com/a/46422184/2692494 <- google:‘codecvt msvc’]
#endif

/*
std::string utf16_to_utf8(const std::u16string &utf16_string)
{
    // [https://stackoverflow.com/questions/32055357/visual-studio-c-2015-stdcodecvt-with-char16-t-or-char32-t <- google:‘codecvt msvc’]
    std::wstring_convert<std::codecvt_utf8_utf16<int16_t>, int16_t> convert;
    auto p = reinterpret_cast<const int16_t *>(utf16_string.data());
    return convert.to_bytes(p, p + utf16_string.size());
}

std::u16string utf8_to_utf16(const char *s, size_t len)
{
    // [https://stackoverflow.com/questions/18921979/how-to-convert-utf-8-encoded-stdstring-to-utf-16-stdstring <- google:‘msvc utf8 to utf16’]
    return std::wstring_convert<std::codecvt<char16_t,char,std::mbstate_t>,char16_t>().from_bytes(s, s + len);
}
*/
#if 1
std::string utf16_to_utf8(const std::u16string &u16)
{
    return std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t>{}.to_bytes(u16);
}

std::u16string utf8_to_utf16(const std::string &s)
{
    return std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t>{}.from_bytes(s);
}
#else
std::string utf16_to_utf8(const std::u16string &u16)
{
    if (u16.empty())
        return std::string();

    int r = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, (LPCWCH)u16.data(), (int)u16.size(), NULL, 0, NULL, NULL);

    std::string s;
    s.resize(r);
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, (LPCWCH)u16.data(), (int)u16.size(), (LPSTR)s.data(), r, NULL, NULL);
    return s;
}

std::u16string utf8_to_utf16(const std::string &s)
{
    std::u16string r;
    if (s.size() != 0) {
        r.resize(s.size());
        r.resize(MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), (int)s.size(), (LPWSTR)r.data(), (int)r.size()));
    }
    return r;
}
#endif

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
    const char16_t *s;
    int len;
    template <int N> StringLiteral(const char16_t (&s)[N]) : s(s), len(N-1) {}
};

template <int oldN, int newN> std::u16string &&replace_all(std::u16string &&str, const char16_t (&old)[oldN], const char16_t (&n)[newN])
{
    size_t start_pos = 0;
    while((start_pos = str.find(old, start_pos)) != str.npos) {
        str.replace(start_pos, oldN-1, n, newN-1);
        start_pos += newN-1;
    }
    return std::move(str);
}

std::u16string &&html_escape(std::u16string &&str)
{
    replace_all(std::move(str), u"&", u"&amp;");
    replace_all(std::move(str), u"<", u"&lt;");
    return std::move(str);
};

std::u16string &&html_escapeq(std::u16string &&str)
{
    replace_all(std::move(str), u"&", u"&amp;");
    replace_all(std::move(str), u"\"", u"&quot;");
    return std::move(str);
};

std::u16string substr(const std::u16string &s, int start, int end)
{
    return s.substr(start, end - start);
}

bool starts_with(const std::u16string &str, const char16_t *s, size_t sz)
{
    return str.length() >= (int)sz && memcmp(str.data(), s, sz*sizeof(char16_t)) == 0;
}
template <int N> bool starts_with(const std::u16string &str, const char16_t (&s)[N])
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
template <int N> bool in(char16_t c, const char16_t(&s)[N])
{
    for (int i=0; i<N-1; i++)
        if (c == s[i])
            return true;
    return false;
}

class Converter
{
    std::vector<int> to_html_called_inside_to_html_outer_pos_arr;
    bool ohd;
    const std::u16string *instr = nullptr;

public:
    Converter(bool ohd) : ohd(ohd) {}

    std::u16string to_html(const std::u16string &instr, FILE *outfilef = NULL, int outer_pos = 0)
    {
        to_html_called_inside_to_html_outer_pos_arr.push_back(outer_pos);

        std::list<std::u16string> result; // this should be faster than using regular u16string
        size_t result_total_len = 0;
        auto write = [&result, &result_total_len](std::u16string &&s) {
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
                if ((*this->instr)[t] == u'\n') {
                    line++;
                    line_start = t;
                }
                t++;
            }
            throw Exception(message, line, pos - line_start, pos);
        };

        int i = 0;
        auto next_char = [&i, &instr](int offset = 1) {
            return i + offset < instr.length() ? instr[i + offset] : u'\0';
        };

        auto i_next_str = [&i, &instr](const StringLiteral s) {
            return i + 1 + s.len <= instr.length() && memcmp(instr.c_str() + i + 1, s.s, s.len * sizeof(char16_t)) == 0;
        };

        auto prev_char = [&i, &instr](int offset = 1) {
            return i - offset >= 0 ? instr[i - offset] : u'\0';
        };

        int writepos = 0;
        auto write_to_pos = [&instr, &write, &writepos](int pos, int npos)
        {
            write(html_escape(instr.substr(writepos, pos - writepos)));
            writepos = npos;
        };

        auto write_to_i = [&i, &write, &write_to_pos](std::u16string &&add_str, int skip_chars = 1)
        {
            write_to_pos(i, i + skip_chars);
            write(std::move(add_str));
        };

        auto find_ending_pair_quote = [&exit_with_error, &instr](int i)
        {
            assert(instr[i] == u'‘'); // ’
            int startqpos = i;
            int nesting_level = 0;
            while (true) {
                if (i == instr.length())
                    exit_with_error("Unpaired left single quotation mark", startqpos);
                switch (instr[i])
                {
                case u'‘':
                    nesting_level++;
                    break;
                case u'’':
                    if (--nesting_level == 0)
                        return i;
                    break;
                }
                i++;
            }
        };

        auto find_ending_sq_bracket = [&exit_with_error](const std::u16string &str, int i, int start = 0)
        {
            int starti = i;
            assert(str[i] == u'['); // ]
            int nesting_level = 0;
            while (true) {
                switch (str[i])
                {
                case u'[':
                    nesting_level++;
                    break;
                case u']':
                    if (--nesting_level == 0)
                        return i;
                    break;
                }
                i++;
                if (i == str.length())
                    exit_with_error("Unended comment started", start + starti);
            }
        };

        auto remove_comments = [&find_ending_sq_bracket](std::u16string &&s, int start, int level = 3) -> std::u16string&&
        {
            std::u16string brackets(level, u'['); // ]
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

        std::u16string link = u"";

        auto write_http_link = [&exit_with_error, &find_ending_pair_quote, &find_ending_sq_bracket, &i, &instr, &link, &next_char, &write, &remove_comments, &write_to_pos, this](int startpos, int endpos, int q_offset = 1, std::u16string text = u"")
        {
            int nesting_level = 0;
            i += 2;
            while (true) {
                if (i == instr.length())
                    exit_with_error("Unended link", endpos + q_offset);
                switch (instr[i])
                {
                case u'[':
                    nesting_level++;
                    break;
                case u']':
                    if (nesting_level == 0)
                        goto break_;
                    nesting_level--;
                    break;
                case u' ':
                    goto break_;
                    break;
                }
                i++;
            }
            break_:;
            link = html_escapeq(substr(instr, endpos + 1 + q_offset, i));
            auto tag = u"<a href=\"" + link + u"\"";
            if (starts_with(link, u"./"))
                tag += u" target=\"_self\"";

            if (instr[i] == u' ') {
                tag += u" title=\"";
                if (next_char() == u'‘') {
                    int endqpos2 = find_ending_pair_quote(i + 1); // [[
                    if (instr[endqpos2 + 1] != u']')
                        exit_with_error("Expected `]` after `’`", endqpos2 + 1);
                    tag += html_escapeq(remove_comments(substr(instr, i + 2, endqpos2), i + 2));
                    i = endqpos2 + 1;
                }
                else {
                    int endb = find_ending_sq_bracket(instr, endpos + q_offset);
                    tag += html_escapeq(remove_comments(substr(instr, i + 1, endb), i + 1));
                    i = endb;
                }
                tag += u"\"";
            }
            if (next_char() == u'[' && next_char(2) == u'-') {
                int j = i + 3;
                while (j < instr.length()) {
                    if (instr[j] == u']') {
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
            write(tag + u">" + (!text.empty() ? text : link) + u"</a>");
        };

        auto write_abbr = [&exit_with_error, &find_ending_pair_quote, &i, &instr, &write, &remove_comments, &write_to_pos](int startpos, int endpos, int q_offset = 1)
        {
            i += q_offset;
            int endqpos2 = find_ending_pair_quote(i + 1); // [[
            if (instr[endqpos2 + 1] != u']') // ‘
                exit_with_error("Bracket ] should follow after ’", endqpos2 + 1);
            write_to_pos(startpos, endqpos2 + 2);
            write(u"<abbr title=\"" + html_escapeq(remove_comments(substr(instr, i + 2, endqpos2), i + 2)) + u"\">" + html_escape(remove_comments(substr(instr, startpos + q_offset, endpos), startpos + q_offset)) + u"</abbr>");
            i = endqpos2 + 1;
        };

        std::vector<std::u16string> ending_tags;
        std::u16string new_line_tag = std::u16string(1, u'\0');

        while (i < instr.length()) {
            char16_t ch = instr[i];
            if ((i == 0 || prev_char() == u'\n' || (i == writepos && !ending_tags.empty() && in(ending_tags.back(), u"</blockquote>", u"</div>")) && in(instr.substr(i - 2, 2), u">‘", u"<‘", u"!‘"))) { // ’’’
                if (ch == u'.' && next_char() == u' ')
                    write_to_i(u"•");
                else if (in(ch, u'>', u'<') && in(next_char(), u" ‘[")) { // ]’
                    write_to_pos(i, i + 2);
                    write(u"<blockquote"s + (ch == u'<' ? u" class=\"re\"" : u"") + u">");
                    if (next_char() == u' ')
                        new_line_tag = u"</blockquote>";
                    else {
                        if (next_char() == u'[') {
                            if (next_char(2) == u'-' && isdigit(next_char(3))) {
                                i = (int)instr.find(u']', i + 4) + 1;
                                writepos = i + 2;
                            }
                            else {
                                i++;
                                int endb = find_ending_sq_bracket(instr, i);
                                link = substr(instr, i + 1, endb);
                                size_t spacepos = link.find(u' ');
                                if (spacepos != link.npos)
                                    link = link.substr(0, spacepos);
                                if (link.length() > 57)
                                    link = link.substr(0, link.rfind(u'/', 46) + 1) + u"...";
                                write_http_link(i, i, 0, u"<i>" + link + u"</i>");
                                i++;
                                if (instr.substr(i, 2) != u":‘") // ’
                                    exit_with_error("Quotation with url should always has :‘...’ after [http(s)://url]", i);
                                write(u":<br />\n");
                                writepos = i + 2;
                            }
                        }
                        else {
                            int endqpos = find_ending_pair_quote(i + 1);
                            if (instr[endqpos + 1] == u'[') { // ]
                                int startqpos = i + 1;
                                i = endqpos;
                                write(u"<i>");
                                assert(writepos == startqpos + 1);
                                writepos = startqpos;
                                write_http_link(startqpos, endqpos);
                                write(u"</i>");
                                i++;
                                if (instr.substr(i, 2) != u":‘") // ’
                                    exit_with_error("Quotation with url should always has :‘...’ after [http(s)://url]", i);
                                write(u":<br />\n");
                                writepos = i + 2;
                            }
                            else if (instr[endqpos + 1] == u':') {
                                write(u"<i>" + substr(instr, i + 2, endqpos) + u"</i>:<br />\n");
                                i = endqpos + 1;
                                if (instr.substr(i, 2) != u":‘") // ’
                                    exit_with_error("Quotation with author's name should be in the form >‘Author's name’:‘Quoted text.’", i);
                                writepos = i + 2;
                            }
                        }
                        ending_tags.push_back(u"</blockquote>");
                    }
                    i++;
                }
            }

            if (ch == u'‘') {
                int prevci = i - 1;
                char16_t prevc = prevci >= 0 ? instr[prevci] : u'\0';
                int startqpos = i;
                i = find_ending_pair_quote(i);
                int endqpos = i;
                std::u16string str_in_p; // (
                if (prevc == u')') {
                    size_t openp = instr.rfind(u'(', prevci - 1); // )
                    if (openp != instr.npos && openp > 0) {
                        str_in_p = substr(instr, (int)openp + 1, startqpos - 1);
                        prevci = (int)openp - 1;
                        prevc = instr[prevci];
                    }
                }
                if (i_next_str(u"[http") || i_next_str(u"[./")) // ]]
                    write_http_link(startqpos, endqpos);
                else if (i_next_str(u"[‘")) // ’]
                    write_abbr(startqpos, endqpos);
                else if (in(prevc, u"0OО")) {
                    write_to_pos(prevci, endqpos + 1);
                    write(replace_all(html_escape(substr(instr, startqpos + 1, endqpos)), u"\n", u"<br />\n"));
                }
                else if (in(prevc, u"<>") && in(instr[prevci - 1], u"<>")) {
                    write_to_pos(prevci - 1, endqpos + 1);
                    auto a = std::u16string(1, instr[prevci - 1]) + prevc;
                    write(u"<div align=\""s + (a == u"<<" ? u"left" : a == u">>" ? u"right" : a == u"><" ? u"center" : u"justify") + u"\">" + (to_html(substr(instr, startqpos + 1, endqpos), nullptr, startqpos + 1)) + u"</div>\n");
                    new_line_tag = u"";
                }
                else if (i_next_str(u":‘") && instr.substr(find_ending_pair_quote(i + 2) + 1, 1) == u"<") {
                    int endrq = find_ending_pair_quote(i + 2);
                    i = endrq + 1;
                    write_to_pos(prevci + 1, i + 1);
                    write(u"<blockquote>" + to_html(substr(instr, startqpos + 1, endqpos), nullptr, startqpos + 1) + u"<br />\n<div align='right'><i>" + substr(instr, endqpos + 3, endrq) + u"</i></div></blockquote>");
                    new_line_tag = u"";
                }
                else {
                    i = startqpos;
                    if (in(prev_char(), u"*_-~")) {
                        write_to_pos(i - 1, i + 1);
                        char16_t a = prev_char();
                        char16_t tag = a == u'*' ? u'b' : a == u'_' ? u'u' : a == u'-' ? u's' : u'i';
                        write(u"<"s + tag + u">");
                        ending_tags.push_back(u"</"s + tag + u">");
                    }
                    else if (in(prevc, u"HН")) {
                        write_to_pos(prevci, i + 1);
                        int h = 0;
                        if (!str_in_p.empty())
                            if (str_in_p[0] == u'-')
                                h = -(str_in_p[1] - u'0');
                            else if (str_in_p[0] == u'+')
                                h = str_in_p[1] - u'0';
                            else
                                h = str_in_p[0] - u'0';
                        auto tag = u"h"s + char16_t(u'0' + std::min(std::max(3 - h, 1), 6));
                        write(u"<" + tag + u">");
                        ending_tags.push_back(u"</" + tag + u">");
                    }
                    else if (prevci >= 1 && in(instr.substr(prevci - 1, 2), u"/\\", u"\\/")) {
                        write_to_pos(prevci - 1, i + 1);
                        auto tag = instr.substr(prevci - 1, 2) == u"/\\" ? u"sup"s : u"sub"s;
                        write(u"<" + tag + u">");
                        ending_tags.push_back(u"</"s + tag + u">"s);
                    }
                    else if (prevc == u'!') {
                        write_to_pos(prevci, i + 1);
                        write(u"<div class=\"note\">");
                        ending_tags.push_back(u"</div>");
                    }
                    else
                        ending_tags.push_back(u"’");
                }
            }
            else if (ch == u'’') {
                write_to_pos(i, i + 1);
                if (ending_tags.empty())
                    exit_with_error("Unpaired right single quotation mark", i);
                auto last = std::move(ending_tags.back());
                ending_tags.pop_back();
                if (next_char() == u'\n' && (starts_with(last, u"</h") || in(last, u"</blockquote>", u"</div>"))) {
                    write(std::move(last));
                    write(u"\n");
                    i++;
                    writepos++;
                }
                else
                    write(std::move(last));
            }
            else if (ch == u'`') {
                int start = i;
                i++;
                while (i < instr.length()) {
                    if (instr[i] != u'`')
                        break;
                    i++;
                }
                size_t end = instr.find(std::u16string(i - start, u'`'), i);
                if (end == instr.npos)
                    exit_with_error("Unended ` started", start);
                write_to_pos(start, (int)end + i - start);
                auto ins = substr(instr, i, (int)end);
                int delta = (int)std::count(ins.begin(), ins.end(), u'‘') - (int)std::count(ins.begin(), ins.end(), u'’');
                if (delta > 0)
                    for (int i = 0; i < delta; i++) // ‘‘
                        ending_tags.push_back(u"’");
                else
                    for (int i = 0; i < -delta; i++) {
                        if (ending_tags.back() != u"’")
                            exit_with_error("Unpaired single quotation mark found inside code block/span beginning", start);
                        ending_tags.pop_back();
                    }
                ins = html_escape(std::move(ins));
                if (ins.find(u'\n') == ins.npos)
                    write(u"<pre class=\"inline_code\">" + ins + u"</pre>");
                else {
                    write(u"<pre>" + ins + u"</pre>" + u"\n");
                    new_line_tag = u"";
                }
                i = (int)end + i - start - 1;
            }
            else if (ch == u'[') { // ]
                if (i_next_str(u"http") || i_next_str(u"./") || (i_next_str(u"‘") && !in(prev_char(), u"\r\n\t \0"))) {
                    int s = i - 1;
                    while (s >= writepos && !in(instr[s], u"\r\n\t [{(")) // )}]
                        s--;
                    if (i_next_str(u"‘"))
                        write_abbr(s + 1, i, 0);
                    else if (i_next_str(u"http") || i_next_str(u"./"))
                        write_http_link(s + 1, i, 0);
                    else
                        assert(false);
                }
                else if (i_next_str(u"[[")) { // ]]
                    int comment_start = i;
                    int nesting_level = 0;
                    while (true) {
                        switch (instr[i])
                        {
                        case u'[':
                            nesting_level++;
                            break;
                        case u']':
                            if (--nesting_level == 0)
                                goto break_2;
                            break;
                        case u'‘':
                            ending_tags.push_back(u"’");
                            break;
                        case u'’':
                            assert(ending_tags.back() == u"’");
                            ending_tags.pop_back();
                            break;
                        }
                        i++;
                        if (i == instr.length())
                            exit_with_error("Unended comment started", comment_start);
                    }
                    break_2:;
                    write_to_pos(comment_start, i + 1);
                }
                else
                    write_to_i((ohd ? u"<span class=\"sq\"><span class=\"sq_brackets\">"s : u""s) + u"[" + (ohd ? u"</span>" : u""));
            }
            else if (ch == u']') // [
                write_to_i((ohd ? u"<span class=\"sq_brackets\">"s : u""s) + u"]" + (ohd ? u"</span></span>" : u""));
            else if (ch == u'{')
                write_to_i((ohd ? u"<span class=\"cu_brackets\" onclick=\"return spoiler(this, event)\"><span class=\"cu_brackets_b\">"s : u""s) + u"{" + (ohd ? u"</span><span>…</span><span class=\"cu\" style=\"display: none\">" : u""));
            else if (ch == u'}')
                write_to_i((ohd ? u"</span><span class=\"cu_brackets_b\">"s : u""s) + u"}" + (ohd ? u"</span></span>" : u""));
            else if (ch == u'\n') {
                write_to_i((new_line_tag != std::u16string(1, u'\0') ? new_line_tag : u"<br />"s) + (new_line_tag != u"" ? u"\n" : u""));
                new_line_tag = std::u16string(1, u'\0');
            }
            i++;
        }

        write_to_pos((int)instr.length(), 0);
        if (!ending_tags.empty())
            exit_with_error("Unclosed left single quotation mark somewhere", (int)instr.length());
        assert(to_html_called_inside_to_html_outer_pos_arr.back() == outer_pos);
        to_html_called_inside_to_html_outer_pos_arr.pop_back();

        std::u16string result_str;
        result_str.reserve(result_total_len);
        for (auto &&it : result)
            result_str += it;

        if (outfilef == NULL)
            return result_str;

        std::string rstr = utf16_to_utf8(result_str);
        fwrite(rstr.data(), rstr.size(), 1, outfilef);
        return u"";
    }
};

auto to_html(const std::u16string &instr, FILE *outfilef = NULL, bool ohd = false)
{
    return Converter(ohd).to_html(instr, outfilef);
}

template <int N> void write_to_file(FILE *file, const char(&s)[N])
{
    fwrite(s, N-1, 1, file);
}

// [https://stackoverflow.com/a/46931770/2692494 <- google:‘c++ split’]
std::vector<std::u16string> split(const std::u16string &s, const std::u16string &delimiter)
{
    size_t pos_start = 0, pos_end, delim_len = delimiter.length();
    std::u16string token;
    std::vector<std::u16string> res;

    while ((pos_end = s.find(delimiter, pos_start)) != std::u16string::npos) {
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

        std::u16string tests_str = utf8_to_utf16(tests_file_str), delim = u" (()) ";

        int tests_cnt = 0;
        for (auto &&test : split(tests_str, u"|\n\n|")) {
            tests_cnt++;
            size_t delim_pos = test.find(delim);
            std::u16string left = test.substr(0, delim_pos),
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
        to_html(utf8_to_utf16(file_str), outfile, true);
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
