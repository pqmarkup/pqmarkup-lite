#[ Translation of "pgmarkup_lite.py".
   Version using representing code points as sequence of strings.
]#

import math, sequtils, strutils, tables, unicode

const
  Alignments = {"<<": "left", ">>": "right", "><": "center", "<>": "justify"}.toTable
  Styles = {"*": "b", "_": "u", "-": "s", "~": "i"}.toTable


type PqmException = ref object of CatchableError
  line, column, pos: Natural

func newPqmException(message: string; line, column, pos: Natural): PqmException =
  new(result)
  result.msg = message
  result.line = line
  result.column = column
  result.pos = pos


type
  CodePoint = string        # Code point as UTF-8 string.
  Utf8Seq = seq[CodePoint]  # Sequence of code points.

  Converter = ref object
    toHtmlCalledInsideToHtmlOuterPosList: seq[int]
    ohd: bool
    instr: Utf8Seq

func newConverter(ohd: bool): Converter {.inline.} =
  result = Converter(ohd: ohd)

func isDigit(cp: CodePoint): bool =
  cp.len == 1 and cp[0].isDigit


# Procedures for Utf8Seq.

func find(str: Utf8Seq; c: char; start = 0): int =
  for i in countup(start, str.high):
    if str[i][0] == c:
      return i
  result = -1

func find(str: Utf8Seq; s: string; start = 0): int =
  let s = toSeq(utf8(s))
  var i = start
  let n = s.len - 1
  while i < str.len - n:
    result = i
    for j in 0..n:
      if str[i+j] != s[j]:
        result = -1
        break
    if result >= 0: return
    inc i

func rfind(str: Utf8Seq; c: char; start = str.high): int =
  for i in countdown(start, 0):
    if str[i][0] == c:
      return i
  result = -1


func `$`(str: Utf8Seq): string {.inline.} = str.join()


# Conversion to HTML.

proc toHtml(conv: Converter; instr: Utf8Seq; outfilef: File = nil; outerPos = 0): string =

  var res: string

  conv.toHtmlCalledInsideToHtmlOuterPosList.add outerPos

  proc write(s: string) =
    if outfilef.isNil: res.add s
    else: outfilef.write s

  # Save "instr" to determine the line number by character number.
  if conv.toHtmlCalledInsideToHtmlOuterPosList.len == 1:
    conv.instr = instr

  func exitWithError(message: string; pos: Natural) =
    var
      pos = pos + sum(conv.toHtmlCalledInsideToHtmlOuterPosList)
      line = 1
      lineStart = -1
      t = 0
    while t < pos:
      if conv.instr[t] == "\n":
        inc line
        lineStart = t
      inc t
    raise newPqmException(message, line, pos - lineStart, pos)

  var i = 0

  func nextChar(offset = 1): CodePoint =
    if i + offset < instr.len: instr[i+offset] else: "\0"

  func iNextStr(s: string): bool =
    let str = toSeq(utf8(s))
    if i + str.len > instr.len: return
    for k, cp in str:
      if instr[i+1+k] != cp: return
    result = true

  func prevChar(offset = 1): CodePoint =
    if i - offset >= 0: instr[i-offset] else: "\0"

  proc htmlEscape(str: Utf8Seq): Utf8Seq =
    const Amp = strutils.split("&amp;")
    const Lt = strutils.split("&lt;")
    for cp in str:
      if cp == "&": result.add Amp
      elif cp == "<": result.add Lt
      else: result.add cp

  proc htmlEscapeQ(str: Utf8Seq): Utf8Seq =
    const Amp = strutils.split("&amp;")
    const Quot = strutils.split("&quot;")
    for cp in str:
      if cp == "&": result.add Amp
      elif cp == "\"": result.add Quot
      else: result.add cp

  var writePos = 0

  proc writeToPos(pos, npos: Natural) =
    if pos > writePos:
      write $htmlEscape(instr[writePos..<pos])
    writePos = npos

  proc writeToI(addStr: string; skipChars = 1) =
    writeToPos i, i + skipChars
    write addStr

  func findEndingPairQuote(i: Natural): Natural =
    assert instr[i] == "‘"
    var
      startqpos, i = i
      nestingLevel = 0
    while true:
      if i == instr.len:
        exitWithError("Unpaired left single quotation mark", startqpos)
      case instr[i]
      of "‘":
        inc nestingLevel
      of "’":
        dec nestingLevel
        if nestingLevel == 0: return i
      else:
        discard
      inc i

  func findEndingSqBracket(str: Utf8Seq; i: Natural; start = 0): Natural =
    assert str[i] == "["
    var
      starti, i = i
      nestingLevel = 0
    while true:
      case str[i]
      of "[":
        inc nestingLevel
      of "]":
        dec nestingLevel
        if nestingLevel == 0: return i
      inc i
      if i == str.len:
        exitWithError("Unended comment started", start + starti)


  func removeComments(str: Utf8Seq; start: Natural; level = 3): Utf8Seq =
    if str.len == 0: return str
    var start = start
    result = str
    while true:
      let j = result.find(repeat('[', level))
      if j < 0: break
      let k = result.findEndingSqBracket(j, start) + 1
      start += k - j
      result.delete(j, k - 1)


  var link: Utf8Seq

  proc writeHttpLink(startpos, endpos : Natural; qOffset = 1; text = "") =

    var text = text

    # Looking for the end of the link.
    var nestingLevel = 0
    inc i, 2
    while true:
      if i == instr.len:
        exitWithError("Unended link", endpos + qOffset)
      case instr[i]
      of "[":
        inc nestingLevel
      of "]":
        if nestingLevel == 0: break
        dec nestingLevel
      of " ":
        break
      inc i

    link = htmlEscapeQ(instr[endpos+1+qOffset..<i])
    var tag = "<a href=\"" & $link & '"'
    if link.len >= 2 and link[0] == "." and link[1] == "/":
      tag &= " target=\"_self\""

    # link[http://... ‘title’]
    if instr[i] == " ":
      tag &= " title=\""
      if nextChar() == "‘":
        let endqpos2 = findEndingPairQuote(i + 1)
        if instr[endqpos2 + 1] != "]":
          exitWithError("Expected `]` after `’`", endqpos2 + 1)
        tag &= $htmlEscapeQ(removeComments(instr[i+2..<endqpos2], i + 2))
        i = endqpos2 + 1
      else:
        let endb = instr.findEndingSqBracket(endpos + qOffset)
        tag &= $htmlEscapeQ(remove_comments(instr[i+1..<endb], i + 1))
        i = endb
      tag &= '"'
    if nextChar() == "[" and nextChar(2) == "-":
      var j = i + 3
      while j < instr.len:
        if instr[j] == "]":
          i = j
          break
        if not instr[j].isDigit:
          break
        inc j
    if text.len == 0:
      writeToPos(startpos, i + 1)
      text = conv.toHtml(instr[startpos+qOffset..<endpos], outerPos = startpos + qOffset)
    write tag & '>' & (if text.len != 0: text else: $link) & "</a>"


  proc writeAbbr(startpos, endpos: Natural; qOffset = 1) =
    inc i, qOffset
    let endqpos2 = findEndingPairQuote(i + 1)
    if instr[endqpos2+1] != "]":
      exitWithError("Bracket ] should follow after ’", endqpos2 + 1)
    writeToPos(startpos, endqpos2 + 2)
    write "<abbr title=\"" &
      $htmlEscapeQ(removeComments(instr[i+2..<endqpos2], i + 2)) & "\">" &
      $htmlEscape(removeComments(instr[startpos+qOffset..<endpos], startpos + qOffset)) & "</abbr>"
    i = endqpos2 + 1

  var
    endingTags: seq[string]
    newLineTag = "\0"

  while i < instr.len:
    let cp = instr[i]
    if i == 0 or prevChar() == "\n" or (i == writepos and endingTags.len != 0 and
                                        endingTags[^1] in ["</blockquote>", "</div>"] and
                                        instr[i-2..i-1] in [@[">", "‘"], @["<", "‘"], @["!", "‘"]]):
      if cp == "." and nextChar() == " ":
        writeToI "•"
      elif cp == " ":
        writeToI "&emsp;"
      elif cp in [">", "<"] and (nextChar() in [" ", "["] or iNextStr("‘")): # ]’
        writeToPos(i, i + 2)
        write "<blockquote" & (if cp == "<": " class=\"re\"" else: "") & ">"
        if nextChar() == " ":   # > Quoted text.
          newLineTag = "</blockquote>"
        else:
          if nextChar() == "[":
            if nextChar(2) == "-" and nextChar(3).isDigit():   # >[-1]:‘Quoted text.’ # [
              i = instr.find(']', i + 4) + 1
              writePos = i + 2
            else: # >[http...]:‘Quoted text.’ or >[http...][-1]:‘Quoted text.’
              inc i
              let endb = findEndingSqBracket(instr, i)
              link = instr[i+1..<endb]
              let spacepos = link.find(' ')
              if spacepos > 0:
                link = link[0..<spacepos]
              if link.len > 57:
                link = link[0..link.rfind('/', 46)] & strutils.split("...")
              writeHttpLink(i, i, 0, "<i>" & $link & "</i>")
              inc i
              if instr[i..i+1] != [":", "‘"]:
                exitWithError(
                  "Quotation with url should always has :‘...’ after [" &
                  $link[0..link.find(':')] & "://url]", i)
              write ":<br />\n"
              writePos = i + 2
          else:
            let endqpos = findEndingPairQuote(i + 1)
            if endqpos < instr.high:
              case instr[endqpos + 1]
              of "[":   # >‘Author's name’[http...]:‘Quoted text.’ # ]
                let startqpos = i + 1
                i = endqpos
                write "<i>"
                assert writepos == startqpos + 1
                writepos = startqpos
                writeHttpLink(startqpos, endqpos)
                write "</i>"
                inc i
                if i == instr.high or instr[i..i+1] != [":", "‘"]:  # ’
                  exitWithError("Quotation with url should always has :‘...’ after [" &
                                $link[0..link.find(':')] & "://url]", i)
                write ":<br />\n"
                writePos = i + 2
              of ":":
                write "<i>" & $instr[i+2..<endqpos] & "</i>:<br />\n"
                i = endqpos + 1
                if i == instr.high or instr[i..i+1] != [":", "‘"]:  # ’
                  exitWithError(
                    "Quotation with author's name should be in the form >‘Author's name’:‘Quoted text.’", i)
                writePos = i + 2

          endingTags.add "</blockquote>"

        inc i, 2
        continue

    case cp

    of "‘":  # ‘
      var prevci = i - 1
      var prevc = if prevci >= 0: instr[prevci] else: "\0"
      let startqpos = i
      i = findEndingPairQuote(i)
      let endqpos = i
      var strInP = ""
      if prevc == ")":
        let openp = instr.rfind('(', prevci - 1)
        if openp > 0:
          strInP = $instr[openp+1..startqpos-2]
          prevci = openp - 1
          prevc = instr[prevci]
      if iNextStr("[http") or iNextStr("[./"):
        writeHttpLink(startqpos, endqpos)
      elif iNextStr("[‘"):  # ’]
        writeAbbr(startqpos, endqpos)
      elif prevc in ["0", "O", "О"]:
        writeToPos(prevci, endqpos + 1)
        write ($htmlEscape(instr[startqpos+1..<endqpos])).replace("\n", "<br />\n")
      elif prevc in ["<", ">"] and instr[prevci - 1] in ["<", ">"]:   # text alignement.
        writeToPos(prevci - 1, endqpos + 1)
        write "<div align=\"" & Alignments[instr[prevci-1] & prevc] & "\">" &
              conv.toHtml(instr[startqpos+1..<endqpos], outerPos = startqpos + 1) & "</div>\n"
        newLineTag = ""
      elif iNextStr(":‘") and instr[findEndingPairQuote(i+2)+1] == "<":
        # reversed quote ‘Quoted text.’:‘Author's name’< # ’
        let endrq = findEndingPairQuote(i + 2)
        i = endrq + 1
        writeToPos(prevci + 1, i + 1)
        write "<blockquote>" & conv.toHtml(instr[startqpos+1..<endqpos], outerPos = startqpos+1) &
              "<br />\n<div align='right'><i>" & $instr[endqpos+3..<endrq] & "</i></div></blockquote>"
        newLineTag = ""
      else:
        i = startqpos   # roll back the position.
        if prevc in ["*", "_", "-", "~"]:
          writeToPos(i - 1, i + 1)
          let tag = Styles[prevc]
          write '<' & tag & '>'
          endingTags.add "</" & tag & '>'
        elif prevc in ["H", "Н"]:
          writeToPos(prevci, i + 1)
          var val = 0
          if strInP.len > 0:
            try: val = strInP.parseInt()
            except ValueError: exitWithError("wrong integer value: " & strInP, i)
          let tag = 'h' & $min(max(3 - val, 1), 6)
          write '<' & tag & '>'
          endingTags.add "</" & tag & '>'
        elif prevci > 0 and (instr[prevci-1], prevc) in [("/", "\\"), ("\\", "/")]:
          writeToPos(prevci-1, i + 1)
          let tag = if (instr[prevci-1], prevc) == ("/", "\\"): "sup" else: "sub"
          write '<' & tag & '>'
          endingTags.add "</" & tag & '>'
        elif prevc == "!":
          writeToPos(prevci, i + 1)
          write """<div class="note">"""
          endingTags.add "</div>"
        else:   # ‘
          endingTags.add("’")

    of "’":
      writeToPos(i, i + 1)
      if endingTags.len == 0:
        exitWithError("Unpaired right single quotation mark", i)
      let last = endingTags.pop()
      write last
      if nextChar() == "\n" and (last.startswith("</h") or last in ["</blockquote>", "</div>"]):
        # since <h.> is a block element, it automatically terminates the line, so you don't need to
        # add an extra <br> tag in this case (otherwise you will get an extra empty line after the header)
        write "\n"
        inc i
        inc writepos

    of "`":
      # First, count the number of characters `;
      # this will determine the boundary where the span of code ends.
      let start = i
      inc i
      while i < instr.len:
        if instr[i] != "`": break
        inc i
      let endpos = instr.find(repeat("`", i - start), i)
      if endpos < 0:
        exitWithError("Unended ` started", start)
      writeToPos(start, endpos + i - start)
      var ins = instr[i..<endpos]
      let delta = ins.count("‘") - ins.count("’") # `backticks` and [[[comments]]] can contain ‘quotes’ (for example: [[[‘]]]`Don’t`), that's why.
      if delta > 0: # this code is needed [:backticks]
        for ii in 0..<delta:
          endingTags.add "’"
      else:
        for ii in (delta+1)..0:
          if endingTags.pop() != "’":
            exitWithError("Unpaired single quotation mark found inside code block/span beginning", start)
      ins = htmlEscape(ins)
      if "\n" notin ins:  # this is a single-line code -‘block’span
        write """<pre class="inline_code">""" & $ins & "</pre>"
      else:
        write "<pre>" & $ins & "</pre>\n"
        newLineTag = ""
      inc i, endpos - start - 1

    of "[":
      if iNextStr("http") or iNextStr("./") or
         nextChar() == "‘" and prevChar() notin ["\r", "\n", "\t", " ", "\0"]: # ’
        var s = i - 1
        while s >= writePos and instr[s] notin ["\r", "\n", "\t", " ", "[", "{", "("]: # )}]
          dec s
        if nextChar() == "‘": # ’
          writeAbbr(s + 1, i, 0)
        elif iNextStr("http") or iNextStr("./"):
          writeHttpLink(s + 1, i, 0)
        else:
          assert false
      elif iNextStr("[["):
        let commentStart = i
        var nestingLevel = 0
        while true:
          case instr[i]
          of "[":
            inc nestingLevel
          of "]":
            dec nestingLevel
            if nestingLevel == 0: break
          of "‘": # [backticks:] and this code
            endingTags.add "’" # ‘‘
          of "’":
            doAssert endingTags.pop() == "’"
          inc i
          if i == instr.len:
            exitWithError("Unended comment started", commentStart)
        writeToPos(commentStart, i + 1)
      else:
        if conv.ohd:
          writeToI """<span class="sq"><span class="sq_brackets">[</span>"""
        else:
          writeToI "["

    of "]": # [
      if conv.ohd:
        writeToI """<span class="sq_brackets">]</span></span>"""
      else:
        writeToI "]"

    of "{":
      if conv.ohd:
        writeToI """<span class="cu_brackets" onclick="return spoiler(this, event)"><span class="cu_brackets_b">{</span><span>…</span><span class="cu" style="display: none">"""
      else:
        writeToI "{"

    of "}":
      if conv.ohd:
        writetoI """</span><span class="cu_brackets_b">}</span></span>"""
      else:
        writeToI "}"

    of "\n":
      writeToI (if newLineTag != "\0": newLineTag else: "<br />") & (if newLineTag != "": "\n" else: "")
      newLine_Tag = "\0"

    inc i

  writeToPos(instr.len, 0)
  if endingTags.len != 0: # there is an unclosed opening/left quote somewhere.
    exitWithError("Unclosed left single quotation mark somewhere", instr.len)

  doAssert conv.toHtmlCalledInsideToHtmlOuterPosList.pop() == outerPos

  if outfilef.isNil:
    result = res


proc toHtml(instr: string; outfilef: File; ohd = false) =
  var conv = newConverter(ohd)
  discard conv.toHtml(toSeq(utf8(instr)), outfilef)

proc toHtml(instr: string; ohd = false): string =
  var conv = newConverter(ohd)
  result = conv.toHtml(toSeq(utf8(instr)))


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
