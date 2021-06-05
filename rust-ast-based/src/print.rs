use std::{fmt, io};

use crate::{Ast, PqLiteError, CLOSE_QUOTE_STR, OPEN_QUOTE_STR};

fn write_html_escaped(text: &str, f: &mut fmt::Formatter) -> fmt::Result {
    // & becomes &amp;
    // < becomes &lt;
    // > becomes &gt;
    // note: efficiency could be greatly improved here by using `find` manually, rather
    // than allocating 3 strings for this operation.
    f.write_str(
        &text
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;"),
    )
}
fn write_html_escaped_with_linebreaks(text: &str, f: &mut fmt::Formatter) -> fmt::Result {
    // & becomes &amp;
    // < becomes &lt;
    // > becomes &gt;
    // note: efficiency could be greatly improved here by using `find` manually, rather
    // than allocating 4 strings for this operation.
    let mut text = &*text
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;");
    // don't write a br for the first \n.
    if text.starts_with('\n') {
        f.write_str("\n")?;
        text = &text[1..];
    }
    f.write_str(&text.replace('\n', "<br />\n"))
}
fn write_attr_value_escaped(text: &str, f: &mut fmt::Formatter) -> fmt::Result {
    // & becomes &amp;
    // < becomes &lt;
    // > becomes &gt;
    // " becomes &quot;
    // ' becomes &#39;
    // note: efficiency could be greatly improved here by using `find` manually, rather
    // than allocating 4 strings for this operation.
    f.write_str(
        &text
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('\"', "&quot;"),
    )
}

impl<'a> fmt::Display for Ast<'a> {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Ast::Text(text) => write_html_escaped_with_linebreaks(text, f)?,
            Ast::CowText(text) => write_html_escaped_with_linebreaks(text, f)?,
            Ast::NoBrText(text) => write_html_escaped(text, f)?,
            Ast::Root(nodes) => {
                for node in nodes {
                    write!(f, "{}", node)?;
                }
            }
            Ast::Quoted { inner, .. } => {
                f.write_str(OPEN_QUOTE_STR)?;
                for node in inner {
                    write!(f, "{}", node)?;
                }
                f.write_str(CLOSE_QUOTE_STR)?;
            }
            Ast::Bracketed(nodes) => {
                f.write_str("[")?;
                for node in nodes {
                    write!(f, "{}", node)?;
                }
                f.write_str("]")?;
            }
            Ast::CurlyBraced(nodes) => {
                f.write_str("{")?;
                for node in nodes {
                    write!(f, "{}", node)?;
                }
                f.write_str("}")?;
            }
            Ast::BlockQuoted(nodes) => {
                f.write_str("<blockquote>")?;
                for node in nodes {
                    write!(f, "{}", node)?;
                }
                f.write_str("</blockquote>\n")?;
            }
            Ast::CodeQuoted(nodes) => {
                f.write_str("<pre>")?;
                for node in nodes {
                    write!(f, "{}", node)?;
                }
                f.write_str("</pre>")?;
            }
            Ast::TooltipText(_) => {
                unreachable!("TooltipText should be processed out by now.");
            }
            Ast::ProcessedPrefixSuffix(prefix, nodes, suffix) => {
                f.write_str(prefix)?;
                for node in nodes {
                    write!(f, "{}", node)?;
                }
                f.write_str(suffix)?;
            }
            Ast::Header(header_number, nodes) => {
                write!(f, "<h{}>", header_number)?;
                for node in nodes {
                    write!(f, "{}", node)?;
                }
                write!(f, "</h{}>", header_number)?;
            }
            Ast::Tooltip {
                tooltip_text,
                inner,
            } => {
                f.write_str("<abbr title=\"")?;
                write_attr_value_escaped(tooltip_text, f)?;
                f.write_str("\">")?;
                for node in inner {
                    write!(f, "{}", node)?;
                }
                f.write_str("</abbr>")?;
            }
            Ast::Link {
                link_location,
                tooltip_text,
                inner,
            } => {
                f.write_str("<a href=\"")?;
                write_attr_value_escaped(link_location, f)?;
                // *shrug* reference impl does this so we will too, despite it
                // not being in spec.
                if link_location.starts_with("./") {
                    f.write_str("\" target=\"_self")?;
                }
                if let Some(tooltip_text) = tooltip_text {
                    f.write_str("\" title=\"")?;
                    write_attr_value_escaped(tooltip_text, f)?;
                }
                f.write_str("\">")?;
                for node in inner {
                    write!(f, "{}", node)?;
                }
                f.write_str("</a>")?;
            }
        }
        Ok(())
    }
}

pub fn ast_to_unwrapped_html(ast: &Ast<'_>, mut output: impl io::Write) -> Result<(), PqLiteError> {
    write!(output, "{}", ast)?;
    Ok(())
}

pub fn ast_to_wrapped_html(ast: &Ast<'_>, mut output: impl io::Write) -> Result<(), PqLiteError> {
    write!(
        output,
        "{}",
        r#"<html>
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
pre {margin: 0; font-family: 'Courier New'; line-height: normal;}
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
pre.inline_code {
    display: inline;
    padding: 0px 3px;
    border: 1px solid #E5E5E5;
    background-color: #FAFAFA;
    border-radius: 3px;
}
div#main {width: 100%;}
@media screen and (min-width: 750px) {
    div#main {width: 724px;}
}
</style>
</head>
<body>
<div id="main" style="margin: 0 auto">"#
    )?;
    ast_to_unwrapped_html(ast, &mut output)?;
    write!(
        output,
        "{}",
        r#"</div>
</body>
</html>
"#
    )?;

    Ok(())
}
