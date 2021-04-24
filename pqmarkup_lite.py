import sys
from typing import List, IO, Callable, Dict
Char = str

class Exception(Exception):
    message : str
    line : int
    column : int
    pos : int
    def __init__(self, message, line, column, pos):
        self.message = message
        self.line = line
        self.column = column
        self.pos = pos

class Converter:
    to_html_called_inside_to_html_outer_pos_list : List[int]
    ohd : bool
    instr : str

    def __init__(self, ohd):
        self.to_html_called_inside_to_html_outer_pos_list = []
        #self.newline_chars = []
        self.ohd = ohd

    def to_html(self, instr : str, outfilef : IO[str] = None, *, outer_pos = 0) -> str:
        self.to_html_called_inside_to_html_outer_pos_list.append(outer_pos)

        result : List[str] = [] # this should be faster than using regular string
        class Writer:
            write : Callable[[str], None]
        outfile = Writer()
        if outfilef is None:
            outfile.write = lambda s: result.append(s)
        else:
            outfile.write = lambda s: outfilef.write(s)

        # Save instr to determine the line number by character number
        if len(self.to_html_called_inside_to_html_outer_pos_list) == 1:
            self.instr = instr

        def exit_with_error(message, pos):
            pos += sum(self.to_html_called_inside_to_html_outer_pos_list)
            line = 1
            line_start = -1
            t = 0
            while t < pos:
                if self.instr[t] == "\n":
                    line += 1
                    line_start = t
                t += 1
            raise Exception(message, line, pos - line_start, pos)

        i = 0
        def next_char(offset = 1):
            return instr[i + offset] if i + offset < len(instr) else Char("\0")

        def i_next_str(str): # i_ — if_/is_
            #return i + len(str) <= len(instr) and instr[i:i+len(str)] == str
            return instr[i+1:i+1+len(str)] == str # first check is not necessarily in Python

        def prev_char(offset = 1):
            return instr[i - offset] if i - offset >= 0 else Char("\0")

        def html_escape(str):
            return str.replace('&', '&amp;').replace('<', '&lt;')
        def html_escapeq(str):
            return str.replace('&', '&amp;').replace('"', '&quot;')

        writepos = 0
        def write_to_pos(pos, npos):
            nonlocal writepos
            outfile.write(html_escape(instr[writepos:pos]))
            writepos = npos

        def write_to_i(add_str, skip_chars = 1):
            write_to_pos(i, i+skip_chars)
            outfile.write(add_str)

        def find_ending_pair_quote(i): # searches for the end of a ‘string’
            assert(instr[i] == "‘") # ’
            startqpos = i
            nesting_level = 0
            while True:
                if i == len(instr):
                    exit_with_error('Unpaired left single quotation mark', startqpos)
                ch = instr[i]
                if ch == "‘":
                    nesting_level += 1
                elif ch == "’":
                    nesting_level -= 1
                    if nesting_level == 0:
                        return i
                i += 1

        def find_ending_sq_bracket(str, i, start = 0):
            starti = i
            assert(str[i] == "[") # ]
            nesting_level = 0
            while True:
                ch = str[i]
                if ch == "[":
                    nesting_level += 1
                elif ch == "]":
                    nesting_level -= 1
                    if nesting_level == 0:
                        return i
                i += 1
                if i == len(str):
                    exit_with_error('Unended comment started', start + starti)

        def remove_comments(s : str, start, level = 3):
            while True:
                j = s.find("["*level) # ]
                if j == -1:
                    break
                k = find_ending_sq_bracket(s, j, start) + 1
                start += k - j
                s = s[0:j] + s[k:]
            return s

        link = ''

        def write_http_link(startpos, endpos : int, q_offset = 1, text = ''):
            nonlocal i, link
            # Looking for the end of the link
            nesting_level = 0
            i += 2
            while True:
                if i == len(instr):
                    exit_with_error('Unended link', endpos+q_offset)
                ch = instr[i]
                if ch == "[":
                    nesting_level += 1
                elif ch == "]":
                    if nesting_level == 0:
                        break
                    nesting_level -= 1
                elif ch == " ":
                    break
                i += 1

            link = html_escapeq(instr[endpos+1+q_offset:i])
            tag = '<a href="' + link + '"'
            if link.startswith('./'):
                tag += ' target="_self"'

            # link[http://... ‘title’]
            if instr[i] == " ":
                tag += ' title="'
                if next_char() == "‘": # [
                    endqpos2 = find_ending_pair_quote(i+1)
                    if instr[endqpos2+1] != ']': # [
                        exit_with_error('Expected `]` after `’`', endqpos2+1)
                    tag += html_escapeq(remove_comments(instr[i+2:endqpos2], i+2))
                    i = endqpos2 + 1
                else:
                    endb = find_ending_sq_bracket(instr, endpos+q_offset)
                    tag += html_escapeq(remove_comments(instr[i+1:endb], i+1))
                    i = endb
                tag += '"'
            if next_char() == '[' and next_char(2) == '-':
                j = i + 3
                while j < len(instr):
                    if instr[j] == ']':
                        i = j
                        break
                    if not instr[j].isdigit():
                        break
                    j += 1
            if text == '':
                write_to_pos(startpos, i+1)
                text = self.to_html(instr[startpos+q_offset:endpos], outer_pos = startpos+q_offset)
            outfile.write(tag + '>' + (text if text != '' else link) + '</a>')

        def write_abbr(startpos, endpos, q_offset = 1):
            nonlocal i
            i += q_offset
            endqpos2 = find_ending_pair_quote(i+1) # [[‘
            if instr[endqpos2+1] != ']':
                exit_with_error("Bracket ] should follow after ’", endqpos2+1)
            write_to_pos(startpos, endqpos2+2)
            outfile.write('<abbr title="'
                + html_escapeq(remove_comments(instr[i+2:endqpos2], i+2)) + '">'
                + html_escape(remove_comments(instr[startpos+q_offset:endpos], startpos+q_offset)) + '</abbr>')
            i = endqpos2 + 1

        ending_tags : List[str] = []
        new_line_tag = "\0"

        while i < len(instr):
            ch = instr[i]
            if (i == 0 or prev_char() == "\n" # if beginning of line
                       or (i == writepos and len(ending_tags) != 0 and ending_tags[-1] in ('</blockquote>', '</div>') and instr[i-2:i] in ('>‘', '<‘', '!‘'))): # ’’’ # or beginning of blockquote or note
                if ch == '.' and next_char() == ' ':
                    write_to_i('•')
                elif ch in ('>', '<') and (next_char() in ' ‘['): # this is blockquote # ]’
                    write_to_pos(i, i + 2)
                    outfile.write('<blockquote'+(ch=='<')*' class="re"'+'>')
                    if next_char() == ' ': # > Quoted text.
                        new_line_tag = '</blockquote>'
                    else:
                        if next_char() == '[': # ]
                            if next_char(2) == '-' and next_char(3).isdigit(): # >[-1]:‘Quoted text.’ # [
                                i = instr.find(']', i + 4) + 1
                                writepos = i + 2
                            else: # >[http...]:‘Quoted text.’ or >[http...][-1]:‘Quoted text.’
                                i += 1
                                endb = find_ending_sq_bracket(instr, i)
                                link = instr[i + 1:endb]
                                spacepos = link.find(' ')
                                if spacepos != -1:
                                    link = link[:spacepos]
                                if len(link) > 57:
                                    link = link[:link.rfind('/', 0, 47)+1] + '...'
                                write_http_link(i, i, 0, '<i>'+link+'</i>') # this function changes `link` :o, but I left[‘I mean didn't rename it to `link_`’] it as is [at least for a while] because it still works correctly
                                i += 1
                                if instr[i:i+2] != ':‘': # ’
                                    exit_with_error("Quotation with url should always has :‘...’ after ["+link[:link.find(':')]+"://url]", i)
                                outfile.write(":<br />\n")
                                writepos = i + 2
                        else:
                            endqpos = find_ending_pair_quote(i + 1)
                            if instr[endqpos+1:endqpos+2] == "[": # >‘Author's name’[http...]:‘Quoted text.’ # ]
                                startqpos = i + 1
                                i = endqpos
                                outfile.write('<i>')
                                assert(writepos == startqpos + 1)
                                writepos = startqpos
                                write_http_link(startqpos, endqpos)
                                outfile.write('</i>')
                                i += 1
                                if instr[i:i+2] != ':‘': # ’
                                    exit_with_error("Quotation with url should always has :‘...’ after ["+link[:link.find(':')]+"://url]", i)
                                outfile.write(":<br />\n")
                                writepos = i + 2
                            elif instr[endqpos+1:endqpos+2] == ":": # >‘Author's name’:‘Quoted text.’
                                outfile.write("<i>"+instr[i+2:endqpos]+"</i>:<br />\n")
                                i = endqpos + 1
                                if instr[i:i+2] != ':‘': # ’
                                    exit_with_error("Quotation with author's name should be in the form >‘Author's name’:‘Quoted text.’", i)
                                writepos = i + 2
                            # else this is just >‘Quoted text.’
                        ending_tags.append('</blockquote>')
                    i += 1

            if ch == "‘":
                prevci = i - 1
                prevc = instr[prevci] if prevci >= 0 else Char("\0")
                #assert(prevc == prev_char())
                startqpos = i
                i = find_ending_pair_quote(i)
                endqpos = i
                str_in_b = '' # (
                if prevc == ')':
                    openb = instr.rfind('(', 0, prevci - 1) # )
                    if openb != -1 and openb > 0:
                        str_in_b = instr[openb+1:startqpos-1]
                        prevci = openb - 1
                        prevc = instr[prevci]
                if i_next_str('[http') or i_next_str('[./'): # ]]
                    write_http_link(startqpos, endqpos)
                elif i_next_str('[‘'): # ’]
                    write_abbr(startqpos, endqpos)
                elif next_char() == '{' and self.ohd:
                    # Looking for the end of the spoiler (`}`)
                    nesting_level = 0
                    i += 2
                    while True:
                        if i == len(instr):
                            exit_with_error('Unended spoiler', endqpos+1)
                        ch = instr[i]
                        if ch == "{":
                            nesting_level += 1
                        elif ch == "}":
                            if nesting_level == 0:
                                break
                            nesting_level -= 1
                        i += 1
                    write_to_pos(prevci + 1, i + 1)
                    outer_p = endqpos+(3 if instr[endqpos+2] == "\n" else 2) # checking for == "\n" is needed to ignore newline after `{`
                    outfile.write('<span class="spoiler_title" onclick="return spoiler2(this, event)">' + remove_comments(instr[startqpos+1:endqpos], startqpos+1) + '<br /></span>' # use `span`, since with a `div` the underline will be full screen
                        + '<div class="spoiler_text" style="display: none">\n' + self.to_html(instr[outer_p:i], outer_pos = outer_p) + "</div>\n")
                    if next_char() == "\n": # to ignore newline after `}`
                        i += 1
                        writepos = i + 1
                elif prevc == "'": # raw [html] output
                    t = startqpos - 1
                    while t >= 0:
                        if instr[t] != "'":
                            break
                        t -= 1
                    eat_left = startqpos - 1 - t
                    t = endqpos + 1
                    while t < len(instr):
                        if instr[t] != "'":
                            break
                        t += 1
                    eat_right = t - (endqpos + 1)
                    write_to_pos(startqpos - eat_left, t)
                    outfile.write(instr[startqpos + eat_left:endqpos - eat_right + 1])
                elif prevc in '0OО':
                    write_to_pos(prevci, endqpos+1)
                    outfile.write(html_escape(instr[startqpos+1:endqpos]).replace("\n", "<br />\n"))
                elif prevc in '<>' and instr[prevci-1] in '<>': # text alignment
                    write_to_pos(prevci-1, endqpos+1)
                    outfile.write('<div align="' + {'<<':'left', '>>':'right', '><':'center', '<>':'justify'}[instr[prevci-1]+prevc] + '">'
                                 + self.to_html(instr[startqpos+1:endqpos], outer_pos = startqpos+1) + "</div>\n")
                    new_line_tag = ''
                elif i_next_str(":‘") and instr[find_ending_pair_quote(i+2)+1:find_ending_pair_quote(i+2)+2] == '<': # this is reversed quote ‘Quoted text.’:‘Author's name’< # ’
                    endrq = find_ending_pair_quote(i+2)
                    i = endrq + 1
                    write_to_pos(prevci + 1, i + 1)
                    outfile.write('<blockquote>' + self.to_html(instr[startqpos+1:endqpos], outer_pos = startqpos+1) + "<br />\n<div align='right'><i>" + instr[endqpos+3:endrq] + "</i></div></blockquote>")
                    new_line_tag = ''
                else:
                    i = startqpos # roll back the position
                    if prev_char() in '*_-~':
                        write_to_pos(i - 1, i + 1)
                        tag = {'*':'b', '_':'u', '-':'s', '~':'i'}[prev_char()]
                        outfile.write('<' + tag + '>')
                        ending_tags.append('</' + tag + '>')
                    elif prevc in 'HН':
                        write_to_pos(prevci, i + 1)
                        tag = 'h' + str(min(max(3 - (0 if str_in_b == '' else int(str_in_b)), 1), 6))
                        outfile.write('<' + tag + '>')
                        ending_tags.append('</' + tag + '>')
                    elif (instr[prevci-1:prevci], prevc) in (('/', "\\"), ("\\", '/')):
                        write_to_pos(prevci-1, i + 1)
                        tag = 'sup' if (instr[prevci-1], prevc) == ('/', "\\") else 'sub'
                        outfile.write('<' + tag + '>')
                        ending_tags.append('</' + tag + '>')
                    elif prevc == '!':
                        write_to_pos(prevci, i + 1)
                        outfile.write('<div class="note">')
                        ending_tags.append('</div>')
                    else: # ‘
                        ending_tags.append('’')
            elif ch == "’":
                write_to_pos(i, i + 1)
                if len(ending_tags) == 0:
                    exit_with_error('Unpaired right single quotation mark', i)
                last = ending_tags.pop()
                outfile.write(last)
                if next_char() == "\n" and (last.startswith('</h') or last in ('</blockquote>', '</div>')): # since <h.> is a block element, it automatically terminates the line, so you don't need to add an extra <br> tag in this case (otherwise you will get an extra empty line after the header)
                    outfile.write("\n")
                    i += 1
                    writepos += 1
            elif ch == '`':
                # First, count the number of characters ` — this will determine the boundary where the span of code ends
                start = i
                i += 1
                while i < len(instr):
                    if instr[i] != '`':
                        break
                    i += 1
                end = instr.find((i - start)*'`', i)
                if end == -1:
                    exit_with_error('Unended ` started', start)
                write_to_pos(start, end + i - start)
                ins = instr[i:end]
                delta = ins.count("‘") - ins.count("’") # `backticks` and [[[comments]]] can contain ‘quotes’ (for example: [[[‘]]]`Don’t`), that's why
                if delta > 0: # this code is needed [:backticks]
                    for ii in range(delta): # ‘‘
                        ending_tags.append('’')
                else:
                    for ii in range(-delta):
                        if ending_tags.pop() != '’':
                            exit_with_error('Unpaired single quotation mark found inside code block/span beginning', start)
                ins = html_escape(ins)
                if not "\n" in ins: # this is a single-line code -‘block’span
                    outfile.write('<pre class="inline_code">' + ins + '</pre>')
                else:
                    outfile.write('<pre>' + ins + '</pre>' + "\n")
                    new_line_tag = ''
                i = end + i - start - 1
            elif ch == '[': # ]
                if i_next_str('http') or i_next_str('./') or (i_next_str('‘') and prev_char() not in "\r\n\t \0"): # ’
                    s = i - 1
                    while s >= writepos and instr[s] not in "\r\n\t [{(": # )}]
                        s -= 1
                    if i_next_str('‘'): # ’
                        write_abbr(s + 1, i, 0)
                    elif i_next_str('http') or i_next_str('./'):
                        write_http_link(s + 1, i, 0)
                    else:
                        assert(False)
                elif i_next_str('[['): # ]] comment
                    comment_start = i
                    nesting_level = 0
                    while True:
                        ch = instr[i]
                        if ch == "[":
                            nesting_level += 1
                        elif ch == "]":
                            nesting_level -= 1
                            if nesting_level == 0:
                                break
                        elif ch == "‘": # [backticks:] and this code
                            ending_tags.append('’') # ‘‘
                        elif ch == "’":
                            assert(ending_tags.pop() == '’')
                        i += 1
                        if i == len(instr):
                            exit_with_error('Unended comment started', comment_start)
                    write_to_pos(comment_start, i+1)
                else:
                    write_to_i('<span class="sq"><span class="sq_brackets">'*self.ohd + '[' + self.ohd*'</span>')
            elif ch == "]": # [
                write_to_i('<span class="sq_brackets">'*self.ohd + ']' + self.ohd*'</span></span>')
            elif ch == "{":
                write_to_i('<span class="cu_brackets" onclick="return spoiler(this, event)"><span class="cu_brackets_b">'*self.ohd + '{' + self.ohd*'</span><span>…</span><span class="cu" style="display: none">')
            elif ch == "}":
                write_to_i('</span><span class="cu_brackets_b">'*self.ohd + '}' + self.ohd*'</span></span>')
            elif ch == "\n":
                write_to_i((new_line_tag if new_line_tag != "\0" else "<br />") + ("\n" if new_line_tag != '' else ""))
                new_line_tag = "\0"

            i += 1

        write_to_pos(len(instr), 0)
        if len(ending_tags) != 0: # there is an unclosed opening/left quote somewhere
            exit_with_error('Unclosed left single quotation mark somewhere', len(instr))

        assert(self.to_html_called_inside_to_html_outer_pos_list.pop() == outer_pos)

        if outfilef is None:
            return ''.join(result)

        return ''

def to_html(instr, outfilef : IO[str] = None, ohd = False):
    return Converter(ohd).to_html(instr, outfilef)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('Usage: pqmarkup_lite input-file output-file')
        sys.exit(0)

    args_infile = sys.stdin
    try:
        args_infile = open(sys.argv[1], 'r', encoding = 'utf-8-sig')
    except:
        sys.exit("Can't open file '" + sys.argv[1] + "'")

    infile_str : str
    try:
        infile_str = args_infile.read()
    except UnicodeDecodeError:
        sys.exit('Input is not a valid UTF-8!')

    args_outfile = sys.stdout
    try:
        args_outfile = open(sys.argv[2], 'w', encoding = 'utf-8', newline = "\n")
    except:
        sys.exit("Can't open file '" + sys.argv[2] + "' for writing")

    args_outfile.write(
R'''<html>
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
function spoiler2(element, event)
{
    element.nextSibling.style.display = (element.nextSibling.style.display == "none" ? "" : "none");
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
''')
    try:
        to_html(infile_str, args_outfile, True)
    except Exception as e:
        sys.stderr.write(e.message + " at line " + str(e.line) + ", column " + str(e.column) + "\n")
        sys.exit(-1)
    args_outfile.write(
'''</div>
</body>
</html>''')
