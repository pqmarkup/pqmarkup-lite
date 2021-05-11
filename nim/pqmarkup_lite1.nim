#[ Translation of "pgmarkup_lite.py".
   Version using representing code points as sequence of Runes.
]#

import math, sequtils, strutils, tables, unicode


type PqmException = ref object of CatchableError
  line, column, pos: Natural

func newPqmException(message: string; line, column, pos: Natural): PqmException =
  new(result)
  result.msg = message
  result.line = line
  result.column = column
  result.pos = pos


type Runes = seq[Rune]  # Sequence of code points.

# Templates used to construct Rune from char and Runes from string (using u'c' and u"s" syntax).
template u(c: char): Rune = Rune(c)
template u(str: string): Runes = str.toRunes


type Converter = ref object
  toHtmlCalledInsideToHtmlOuterPosList: seq[int]
  ohd: bool
  runes: Runes

func newConverter(ohd: bool): Converter {.inline.} =
  result = Converter(ohd: ohd)

const
  Alignments = {u"<<": "left", u">>": "right", u"><": "center", u"<>": "justify"}.toTable
  Styles = {u'*': "b", u'_': "u", u'-': "s", u'~': "i"}.toTable
  LSQM = Rune(0x2018)   # left single quotation mark (‘).
  RSQM = Rune(0x2019)   # right single quotation mark (’).
  CyrEn = Rune(0x041D)  # Cyrillic letter EN.
  CyrO = Rune(0x041E)   # Cyrillic capital letter O.


# Additional procedures for Runes.

template `==`(rune: Rune; c: char): bool = rune == Rune(c)


func isDigit(rune: Rune): bool {.inline.} =
  (rune >=% u'0') and (rune <=% u'9')


func find(runes: Runes; c: char; start = 0): int =
  for i in countup(start, runes.high):
    if runes[i] == c:
      return i
  result = -1


func find(runes: Runes; r: Runes; start = 0): int =
  var i = start
  let n = r.len - 1
  while i < runes.len - n:
    result = i
    for j in 0..n:
      if runes[i+j] != r[j]:
        result = -1
        break
    if result >= 0: return
    inc i


func rfind(runes: Runes; c: char; start = runes.high): int =
  for i in countdown(start, 0):
    if runes[i] == c:
      return i
  result = -1


# Conversion to HTML.

proc toHtml(conv: Converter; runes: Runes; outfilef: File = nil; outerPos = 0): string =

  var res: string   # Result (if outfilef is nil).

  conv.toHtmlCalledInsideToHtmlOuterPosList.add outerPos

  proc write(s: string) =
    if outfilef.isNil: res.add s
    else: outfilef.write s


  # Save "runes" to determine the line number by character number.
  if conv.toHtmlCalledInsideToHtmlOuterPosList.len == 1:
    conv.runes = runes


  func exitWithError(message: string; pos: Natural) =
    var
      pos = pos + sum(conv.toHtmlCalledInsideToHtmlOuterPosList)
      line = 1
      lineStart = -1
      t = 0
    while t < pos:
      if conv.runes[t] == '\n':
        inc line
        lineStart = t
      inc t
    raise newPqmException(message, line, pos - lineStart, pos)


  var i = 0   # Index in rune sequence.

  func nextChar(offset = 1): Rune =
    if i + offset < runes.len: runes[i+offset] else: u'\0'

  func iNextStr(r: Runes): bool =
    if i + r.len > runes.len: return
    for k, rune in r:
      if runes[i+1+k] != rune: return
    result = true

  func prevChar(offset = 1): Rune =
    if i - offset >= 0: runes[i-offset] else: u'\0'

  proc htmlEscape(r: Runes): Runes =
    const Amp = u"&amp;"
    const Lt = u"&lt;"
    for rune in r:
      if rune == '&': result.add Amp
      elif rune == '<': result.add Lt
      else: result.add rune

  proc htmlEscapeQ(r: Runes): Runes =
    const Amp = u"&amp;"
    const Quot = u"&quot;"
    for rune in r:
      if rune == '&': result.add Amp
      elif rune == '"': result.add Quot
      else: result.add rune

  var writePos = 0

  proc writeToPos(pos, npos: int) =
    if pos > writePos:
      write $htmlEscape(runes[writePos..<pos])
    writePos = npos

  proc writeToI(addStr: string; skipChars = 1) =
    writeToPos i, i + skipChars
    write addStr

  func findEndingPairQuote(i: Natural): Natural =
    assert runes[i] == LSQM
    var
      startqpos, i = i
      nestingLevel = 0
    while true:
      if i == runes.len:
        exitWithError("Unpaired left single quotation mark", startqpos)
      case runes[i]
      of LSQM:
        inc nestingLevel
      of RSQM:
        dec nestingLevel
        if nestingLevel == 0: return i
      else:
        discard
      inc i

  func findEndingSqBracket(r: Runes; i: Natural; start = 0): Natural =
    assert r[i] == '['
    var
      starti, i = i
      nestingLevel = 0
    while true:
      case r[i]
      of u'[':
        inc nestingLevel
      of u']':
        dec nestingLevel
        if nestingLevel == 0: return i
      else:
        discard
      inc i
      if i == r.len:
        exitWithError("Unended comment started", start + starti)


  func removeComments(r: Runes; start: Natural; level = 3): Runes =
    if r.len == 0: return r
    var start = start
    result = r
    while true:
      let j = result.find(sequtils.repeat(u'[', level))
      if j < 0: break
      let k = result.findEndingSqBracket(j, start) + 1
      start += k - j
      result.delete(j, k - 1)


  var link: Runes

  proc writeHttpLink(startpos, endpos : Natural; qOffset = 1; text = "") =

    var text = text

    # Looking for the end of the link.
    var nestingLevel = 0
    inc i, 2
    while true:
      if i == runes.len:
        exitWithError("Unended link", endpos + qOffset)
      case runes[i]
      of u'[':
        inc nestingLevel
      of u']':
        if nestingLevel == 0: break
        dec nestingLevel
      of u' ':
        break
      else:
        discard
      inc i

    link = htmlEscapeQ(runes[endpos+1+qOffset..<i])
    var tag = "<a href=\"" & $link & '"'
    if link.len >= 2 and link[0] == '.' and link[1] == '/':
      tag &= " target=\"_self\""

    # link[http://... ‘title’]
    if runes[i] == ' ':
      tag &= " title=\""
      if nextChar() == LSQM:
        let endqpos2 = findEndingPairQuote(i + 1)
        if runes[endqpos2 + 1] != ']':
          exitWithError("Expected `]` after `’`", endqpos2 + 1)
        tag &= $htmlEscapeQ(removeComments(runes[i+2..<endqpos2], i + 2))
        i = endqpos2 + 1
      else:
        let endb = runes.findEndingSqBracket(endpos + qOffset)
        tag &= $htmlEscapeQ(remove_comments(runes[i+1..<endb], i + 1))
        i = endb
      tag &= '"'
    if nextChar() == '[' and nextChar(2) == '-':
      var j = i + 3
      while j < runes.len:
        if runes[j] == ']':
          i = j
          break
        if not runes[j].isDigit:
          break
        inc j
    if text.len == 0:
      writeToPos(startpos, i + 1)
      text = conv.toHtml(runes[startpos+qOffset..<endpos], outerPos = startpos + qOffset)
    write tag & '>' & (if text.len != 0: text else: $link) & "</a>"


  proc writeAbbr(startpos, endpos: Natural; qOffset = 1) =
    inc i, qOffset
    let endqpos2 = findEndingPairQuote(i + 1)
    if runes[endqpos2+1] != ']':
      exitWithError("Bracket ] should follow after ’", endqpos2 + 1)
    writeToPos(startpos, endqpos2 + 2)
    write "<abbr title=\"" &
      $htmlEscapeQ(removeComments(runes[i+2..<endqpos2], i + 2)) & "\">" &
      $htmlEscape(removeComments(runes[startpos+qOffset..<endpos], startpos + qOffset)) & "</abbr>"
    i = endqpos2 + 1

  var
    endingTags: seq[string]
    newLineTag = "\0"

  while i < runes.len:
    let rune = runes[i]
    if i == 0 or prevChar() == '\n' or (i == writepos and endingTags.len != 0 and
                                        endingTags[^1] in ["</blockquote>", "</div>"] and
                                        runes[i-2..i-1] in [u">‘", u"<‘", u"!‘"]):
      if rune == '.' and nextChar() == ' ':
        writeToI "•"
      elif rune == u' ':
        writeToI "&emsp;"
      elif rune in [u'>', u'<'] and (nextChar() in [u' ', u'['] or iNextStr(u"‘")): # ]’
        writeToPos(i, i + 2)
        write "<blockquote" & (if rune == '<': " class=\"re\"" else: "") & ">"
        if nextChar() == ' ':   # > Quoted text.
          newLineTag = "</blockquote>"
        else:
          if nextChar() == '[':
            if nextChar(2) == '-' and nextChar(3).isDigit():   # >[-1]:‘Quoted text.’ # [
              i = runes.find(']', i + 4) + 1
              writePos = i + 2
            else: # >[http...]:‘Quoted text.’ or >[http...][-1]:‘Quoted text.’
              inc i
              let endb = findEndingSqBracket(runes, i)
              link = runes[i+1..<endb]
              let spacepos = link.find(' ')
              if spacepos > 0:
                link = link[0..<spacepos]
              if link.len > 57:
                link = link[0..link.rfind('/', 46)] & u"..."
              writeHttpLink(i, i, 0, "<i>" & $link & "</i>")
              inc i
              if runes[i..i+1] != [u':', LSQM]:
                exitWithError(
                  "Quotation with url should always has :‘...’ after [" &
                  $link[0..link.find(':')] & "://url]", i)
              write ":<br />\n"
              writePos = i + 2
          else:
            let endqpos = findEndingPairQuote(i + 1)
            if endqpos < runes.high:
              case runes[endqpos + 1]
              of u'[':   # >‘Author's name’[http...]:‘Quoted text.’ # ]
                let startqpos = i + 1
                i = endqpos
                write "<i>"
                assert writepos == startqpos + 1
                writepos = startqpos
                writeHttpLink(startqpos, endqpos)
                write "</i>"
                inc i
                if i == runes.high or runes[i..i+1] != [u':', LSQM]:
                  exitWithError("Quotation with url should always has :‘...’ after [" &
                                $link[0..link.find(':')] & "://url]", i)
                write ":<br />\n"
                writePos = i + 2
              of u':':
                write "<i>" & $runes[i+2..<endqpos] & "</i>:<br />\n"
                i = endqpos + 1
                if i == runes.high or runes[i..i+1] != [u':', LSQM]:
                  exitWithError(
                    "Quotation with author's name should be in the form >‘Author's name’:‘Quoted text.’", i)
                writePos = i + 2
              else:
                discard

          endingTags.add "</blockquote>"

        inc i, 2
        continue

    case rune

    of LSQM:  # ‘
      var prevci = i - 1
      var prevc = if prevci >= 0: runes[prevci] else: u'\0'
      let startqpos = i
      i = findEndingPairQuote(i)
      let endqpos = i
      var strInP = ""
      if prevc == ')':
        let openp = runes.rfind('(', prevci - 1)
        if openp > 0:
          strInP = $runes[openp+1..startqpos-2]
          prevci = openp - 1
          prevc = runes[prevci]
      if iNextStr(u"[http") or iNextStr(u"[./"):
        writeHttpLink(startqpos, endqpos)
      elif iNextStr(u"[‘"):
        writeAbbr(startqpos, endqpos)
      elif prevc in [u'0', u'O', CyrO]:
        writeToPos(prevci, endqpos + 1)
        write ($htmlEscape(runes[startqpos+1..<endqpos])).replace("\n", "<br />\n")
      elif prevc in [u'<', u'>'] and runes[prevci - 1] in [u'<', u'>']:   # text alignement.
        writeToPos(prevci - 1, endqpos + 1)
        write "<div align=\"" & Alignments[@[runes[prevci-1], prevc]] & "\">" &
              conv.toHtml(runes[startqpos+1..<endqpos], outerPos = startqpos + 1) & "</div>\n"
        newLineTag = ""
      elif iNextStr(u":‘") and runes[findEndingPairQuote(i+2)+1] == '<':
        # reversed quote ‘Quoted text.’:‘Author's name’< # ’
        let endrq = findEndingPairQuote(i + 2)
        i = endrq + 1
        writeToPos(prevci + 1, i + 1)
        write "<blockquote>" & conv.toHtml(runes[startqpos+1..<endqpos], outerPos = startqpos+1) &
              "<br />\n<div align='right'><i>" & $runes[endqpos+3..<endrq] & "</i></div></blockquote>"
        newLineTag = ""
      else:
        i = startqpos   # roll back the position.
        if prevc in [u'*', u'_', u'-', u'~']:
          writeToPos(i - 1, i + 1)
          let tag = Styles[prevc]
          write '<' & tag & '>'
          endingTags.add "</" & tag & '>'
        elif prevc in [u'H', CyrEn]:
          writeToPos(prevci, i + 1)
          var val = 0
          if strInP.len > 0:
            try: val = strInP.parseInt()
            except ValueError: exitWithError("wrong integer value: " & strInP, i)
          let tag = 'h' & $min(max(3 - val, 1), 6)
          write '<' & tag & '>'
          endingTags.add "</" & tag & '>'
        elif prevci > 0 and (runes[prevci-1], prevc) in [(u'/', u'\\'), (u'\\', u'/')]:
          writeToPos(prevci-1, i + 1)
          let tag = if (runes[prevci-1], prevc) == (u'/', u'\\'): "sup" else: "sub"
          write '<' & tag & '>'
          endingTags.add "</" & tag & '>'
        elif prevc == '!':
          writeToPos(prevci, i + 1)
          write """<div class="note">"""
          endingTags.add "</div>"
        else:   # ‘
          endingTags.add("’")

    of RSQM:
      writeToPos(i, i + 1)
      if endingTags.len == 0:
        exitWithError("Unpaired right single quotation mark", i)
      let last = endingTags.pop()
      write last
      if nextChar() == '\n' and (last.startswith("</h") or last in ["</blockquote>", "</div>"]):
        # since <h.> is a block element, it automatically terminates the line, so you don't need to
        # add an extra <br> tag in this case (otherwise you will get an extra empty line after the header)
        write "\n"
        inc i
        inc writepos

    of u'`':
      # First, count the number of characters `;
      # this will determine the boundary where the span of code ends.
      let start = i
      inc i
      while i < runes.len:
        if runes[i] != '`': break
        inc i
      let endpos = runes.find(sequtils.repeat(u'`', i - start), i)
      if endpos < 0:
        exitWithError("Unended ` started", start)
      writeToPos(start, endpos + i - start)
      var r = runes[i..<endpos]
      let delta = r.count(LSQM) - r.count(RSQM) # `backticks` and [[[comments]]] can contain ‘quotes’ (for example: [[[‘]]]`Don’t`), that's why.
      if delta > 0: # this code is needed [:backticks]
        for ii in 0..<delta:   # ‘‘
          endingTags.add "’"
      else:
        for ii in (delta+1)..0:
          if endingTags.pop() != "’":
            exitWithError("Unpaired single quotation mark found inside code block/span beginning", start)
      r = htmlEscape(r)
      if u('\n') notin r:  # this is a single-line code -‘block’span
        write """<pre class="inline_code">""" & $r & "</pre>"
      else:
        write "<pre>" & $r & "</pre>\n"
        newLineTag = ""
      inc i, endpos - start - 1

    of u'[':
      if iNextStr(u"http") or iNextStr(u"./") or
         iNextStr(u"‘") and prevChar() notin [u'\r', u'\n', u'\t', u' ', u'\0']: # ’
        var s = i - 1
        while s >= writePos and runes[s] notin [u'\r', u'\n', u'\t', u' ', u'[', u'{', u'(']:
          dec s
        if iNextStr(u"‘"): # ’
          writeAbbr(s + 1, i, 0)
        elif iNextStr(u"http") or iNextStr(u"./"):
          writeHttpLink(s + 1, i, 0)
        else:
          assert false
      elif iNextStr(u"[["):
        let commentStart = i
        var nestingLevel = 0
        while true:
          case runes[i]
          of u'[':
            inc nestingLevel
          of u']':
            dec nestingLevel
            if nestingLevel == 0: break
          of LSQM: # [backticks:] and this code
            endingTags.add "’" # ‘‘
          of RSQM:
            doAssert endingTags.pop() == "’"
          else:
            discard
          inc i
          if i == runes.len:
            exitWithError("Unended comment started", commentStart)
        writeToPos(commentStart, i + 1)
      else:
        if conv.ohd:
          writeToI """<span class="sq"><span class="sq_brackets">[</span>"""
        else:
          writeToI "["

    of u']': # [
      if conv.ohd:
        writeToI """<span class="sq_brackets">]</span></span>"""
      else:
        writeToI "]"

    of u'{':
      if conv.ohd:
        writeToI """<span class="cu_brackets" onclick="return spoiler(this, event)"><span class="cu_brackets_b">{</span><span>…</span><span class="cu" style="display: none">"""
      else:
        writeToI "{"

    of u'}':
      if conv.ohd:
        writetoI """</span><span class="cu_brackets_b">}</span></span>"""
      else:
        writeToI "}"

    of u'\n':
      writeToI (if newLineTag != "\0": newLineTag else: "<br />") & (if newLineTag != "": "\n" else: "")
      newLine_Tag = "\0"

    else:
      discard

    inc i

  writeToPos(runes.len, 0)
  if endingTags.len != 0: # there is an unclosed opening/left quote somewhere.
    exitWithError("Unclosed left single quotation mark somewhere", runes.len)

  doAssert conv.toHtmlCalledInsideToHtmlOuterPosList.pop() == outerPos

  if outfilef.isNil:
    result = res


proc toHtml(instr: string; outfilef: File; ohd = false) =
  var conv = newConverter(ohd)
  discard conv.toHtml(instr.toRunes, outfilef)

proc toHtml(instr: string; ohd = false): string =
  var conv = newConverter(ohd)
  result = conv.toHtml(instr.toRunes)


when isMainModule:

  import os

  if "-t" in commandLineParams():
    var testsCnt = 0
    for test in readFile("../tests.txt").split("|\n\n|"):
      let t = test.split(" (()) ")
      if t[0].toHtml != t[1]:
        quit "Error in test |" & test & '|', QuitFailure
      inc testsCnt
    echo "All of ", testsCnt, " tests passed!"
    quit QuitSuccess

  if paramCount() < 2:
    echo "Usage: pqmarkup_lite input-file output-file"
    quit QuitSuccess

  let infileStr = try: readFile(paramStr(1))
                  except IOError: quit "Cannot read file '$#'." % paramStr(1)

  let errpos = infileStr.validateUtf8()
  if errpos >= 0:
    quit "Input is not a valid UTF-8!"

  let outFile = try: open(paramStr(2), fmWrite)
                except IOError: quit "Can’t open file '$#' for writing." % paramStr(2)

  outFile.write(r"""
<html>
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
""")

  try:
    infileStr.toHtml(outFile, true)
  except PqmException:
    let e = PqmException(getCurrentException())
    stderr.write "$1 at line $2, column $3.\n".format(e.msg, e.line, e.column)
    quit QuitFailure

  outfile.write "</div>\n</body>\n</html>"
