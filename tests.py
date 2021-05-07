import os, tempfile, sys, pqmarkup_lite

test_id = 0
failed_tests = 0
kdiff_showed = False
def TEST(str1, str2, ohd = False):
    global test_id, failed_tests, kdiff_showed
    test_id += 1
    print("Test " + str(test_id) + " ...", end = '')
    str1 = pqmarkup_lite.to_html(str1, ohd = ohd)
    if str1 != str2:
        str1 = str(str1)
        str2 = str(str2)
        print("FAILED!")
        if not kdiff_showed:
            for envvar in ['ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432']:
                os.environ["PATH"] += os.pathsep + os.getenv(envvar, '') + r'\KDiff3'
            command = 'kdiff3'
            for file in [('wrong', str1), ('right', str2)]: # можно наоборот — [('right', str2), ('wrong', str1)], только цвет нужно оставить как при [('wrong', str1), ('right', str2)]
                full_fname = os.path.join(tempfile.gettempdir(), file[0])
                command += ' "' + full_fname + '"'
                open(full_fname, 'w', encoding = 'utf-8-sig', newline = "\n").write(file[1])
            os.system(command)
            kdiff_showed = True
        failed_tests += 1
    else:
        print("passed")

TEST("*‘bold’",          "<b>bold</b>")
TEST("_‘underlined’",    "<u>underlined</u>")
TEST("-‘strikethrough’", "<s>strikethrough</s>")
TEST("~‘italics’",       "<i>italics</i>")
TEST("H‘header’\n" +
     "H(1)‘header’",     "<h3>header</h3>\n"
                       + "<h2>header</h2>")
TEST("H(+1)‘header’",    "<h2>header</h2>")
TEST("H(-1)‘header’",    "<h4>header</h4>")
TEST("[http://address]", '<a href="http://address">http://address</a>')
TEST("link[http://address]", '<a href="http://address">link</a>')
TEST("link[https://address]", '<a href="https://address">link</a>')
TEST("‘multiword link’[http://address]", '<a href="http://address">multiword link</a>')
TEST("link[https://address ‘title &text[[[comment]]]’]", '<a href="https://address" title="title &amp;text">link</a>')
TEST("link[https://address title [.&.] text[[[comment]]]]", '<a href="https://address" title="title [.&amp;.] text">link</a>')
TEST('‘[[[Scoping rules/]]]Code blocks’[./code-blocks]', '<a href="./code-blocks" target="_self">Code blocks</a>')
TEST(R'‘Versioning with 100%/versions_threshold/\‘2’ overhead’[./versioning.pq]', '<a href="./versioning.pq" target="_self">Versioning with 100%/versions_threshold<sup>2</sup> overhead</a>')
TEST('‘compares files based on which ~‘lines’ have changed’[http://www.devuxer.com/2014/02/15/why-the-mercurial-zipdoc-extension-fails-for-excel-files/]', '<a href="http://www.devuxer.com/2014/02/15/why-the-mercurial-zipdoc-extension-fails-for-excel-files/">compares files based on which <i>lines</i> have changed</a>')
TEST("text[‘title text’]", '<abbr title="title text">text</abbr>')
TEST("[text][‘title text’]", '[text]<abbr title="title text"></abbr>') # чтобы получить '<abbr title="title text">[text]</abbr>' пишите так: ‘[text]’[‘title text’]
TEST('Примечание 1: только режимы ‘r’ и ‘w’ поддерживаются на данный момент [‘мои мысли на тему режимов открытия файлов’[./File]]', 'Примечание 1: только режимы ‘r’ и ‘w’ поддерживаются на данный момент [<a href="./File" target="_self">мои мысли на тему режимов открытия файлов</a>]')
TEST('Примечание 1: только режимы ‘r’ и ‘w’ поддерживаются на данный момент [[‘’]‘мои мысли на тему режимов открытия файлов’[./File]]', 'Примечание 1: только режимы ‘r’ и ‘w’ поддерживаются на данный момент [<abbr title=""></abbr><a href="./File" target="_self">мои мысли на тему режимов открытия файлов</a>]') # maybe this test is unnecessary
TEST('[[‘’][[[Справка/]]]Документация по методам доступна на данный момент только ‘на английском’[./../../built-in-types].]', '[<abbr title=""></abbr>Документация по методам доступна на данный момент только <a href="./../../built-in-types" target="_self">на английском</a>.]')
TEST('[‘мои мысли на тему режимов открытия файлов’[./File]]', '[<a href="./File" target="_self">мои мысли на тему режимов открытия файлов</a>]')
#TEST("‘`‘` и `’`’[‘`‘` и `’`’]", '<abbr title="`‘` и `’`"><code>‘</code> и <code>’</code></abbr>') # Почему оставил закомментированным: должна возникнуть необходимость использовать такое в реальном тексте прежде чем добавлять какой-либо функционал в код ‘на всякий случай’/‘на будущее’.
TEST("link[http://address][1] ‘the same link’[1]", '<a href="http://address">link</a>[1] ‘the same link’[1]')
TEST("[[[comment[[[[sensitive information]]]]]]]", "")
TEST("[[[com]ment]]", "")
TEST("[[[[comment]]]]", "")
TEST("[[[[[com]m]e]n]t]", "")
TEST("\n A", "<br />\n&emsp;A")
TEST(" A", "&emsp;A")
TEST("a\n---=\n", "a<br />\n---=<br />\n")
TEST("a0‘*‘<non-bold>’’", "a*‘&lt;non-bold>’")
#TEST(open("tests/test1.pq", encoding="utf-8").read(), open("tests/test1.pq.to_habr_html", encoding="utf-8").read(), habr_html = True) # для проверки безопасности рефакторинга нужен был какой-либо обширный тестовый текст на пк-разметке [-TODO подобрать такой текст, который не стыдно закоммитить :)(:-]
TEST("""<<‘выравнивание по левому краю’
>>‘выравнивание по правому краю’
><‘выравнивание по центру’
<>‘выравнивание по ширине’""", """\
<div align="left">выравнивание по левому краю</div>
<div align="right">выравнивание по правому краю</div>
<div align="center">выравнивание по центру</div>
<div align="justify">выравнивание по ширине</div>
""")
TEST("‘’<<", "‘’&lt;&lt;") # was [before this commit]: ‘’<div align="left"></div>&lt;&lt;
TEST(R"/\‘надстрочный\superscript’\/‘подстрочный\subscript’", R"<sup>надстрочный\superscript</sup><sub>подстрочный\subscript</sub>")
TEST("> Quote\n" +
     ">‘Quote2’\n", "<blockquote>Quote</blockquote>\n"
                  + "<blockquote>Quote2</blockquote>\n")
TEST(">[http://address]:‘Quoted text.’",                '<blockquote><a href="http://address"><i>http://address</i></a>:<br />\nQuoted text.</blockquote>')
TEST(">[http://another-address][-1]:‘Quoted text.’\n" +
     ">[-1]:‘Another quoted text.’",                    '<blockquote><a href="http://another-address"><i>http://another-address</i></a>:<br />\nQuoted text.</blockquote>\n'
                                                      + '<blockquote>Another quoted text.</blockquote>')
TEST(">‘Author's name’[http://address]:‘Quoted text.’", '<blockquote><i><a href="http://address">Author\'s name</a></i>:<br />\nQuoted text.</blockquote>')
TEST(">‘Author's name’:‘Quoted text.’",                 '<blockquote><i>Author\'s name</i>:<br />\nQuoted text.</blockquote>')
TEST("‘Quoted text.’:‘Author's name’<",                 "<blockquote>Quoted text.<br />\n<div align='right'><i>Author's name</i></div></blockquote>")
TEST('>‘Как люди думают. Дмитрий Чернышев. 2015. 304с.’:‘[[[стр.89:]]]...’', "<blockquote><i>Как люди думают. Дмитрий Чернышев. 2015. 304с.</i>:<br />\n...</blockquote>")
TEST(">‘>‘Автор против nullable-типов?’\nДа. Адрес, указывающий на незаконный участок памяти, сам незаконен.’", '<blockquote><blockquote>Автор против nullable-типов?</blockquote>\nДа. Адрес, указывающий на незаконный участок памяти, сам незаконен.</blockquote>')
TEST(">‘> Автор против nullable-типов?\nДа. Адрес, указывающий на незаконный участок памяти, сам незаконен.’", '<blockquote><blockquote>Автор против nullable-типов?</blockquote>\nДа. Адрес, указывающий на незаконный участок памяти, сам незаконен.</blockquote>')
TEST("‘понимание [[[процесса]]] разбора [[[разметки]]] человеком’[‘говоря проще: приходится [[[гораздо]]] меньше думать о том, будет это работать или не будет, а просто пишешь в соответствии с чёткими/простыми/логичными правилами, и всё’]", '<abbr title="говоря проще: приходится  меньше думать о том, будет это работать или не будет, а просто пишешь в соответствии с чёткими/простыми/логичными правилами, и всё">понимание  разбора  человеком</abbr>')
TEST(
""". unordered
. list""",
"""• unordered<br />
• list""")
TEST("""A
```
let s2 = str
        .lowercaseString
        .replace("hello", withString: "goodbye")
```
B
C""",
"""A<br />
<pre>
let s2 = str
        .lowercaseString
        .replace("hello", withString: "goodbye")
</pre>
B<br />
C""") # с тегом <code> пробелы ‘корректно не отображаются’/коллапсируются

# Check for error handling
test_id += 1
was_error = False
print("Test " + str(test_id) + " (error handling) ...", end = '')
try:
    pqmarkup_lite.to_html("\nT‘‘‘`’’’")
except pqmarkup_lite.Exception as e:
    was_error = True
    if e.line == 2 and e.column == 5 and e.pos == 5:
        print("passed")
    else:
        print("FAILED!")
        failed_tests += 1
assert(was_error)

# Check for presence of TAB and CR characters in source files and forbid them
test_id += 1
print("Test " + str(test_id) + ". Checking source files for unallowed characters...")
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d[0] != '.'] # exclude hidden folders (e.g. `.hg`)
    for name in files:
        if name.endswith(('.py', '.txt')):
            file_bytes = open(os.path.join(root, name), 'rb').read()
            if b"\r" in file_bytes or b"\t" in file_bytes:
                print(R"Unallowed character (\r or \t) found in file '" + os.path.join(root, name)[2:] + "'")
                failed_tests += 1

if failed_tests == 0:
    print("OK (all " + str(test_id) + " tests passed)")
    sys.exit(0)
else:
    print(str(test_id-failed_tests) + " tests passed and " + str(failed_tests) + " failed.")
    sys.exit(1)
