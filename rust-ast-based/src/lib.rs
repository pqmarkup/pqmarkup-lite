use std::{borrow::Cow, io};

pub mod parse;
pub mod print;

const OPEN_QUOTE: char = '‘';
const OPEN_QUOTE_STR: &str = "‘";
const CLOSE_QUOTE: char = '’';
const CLOSE_QUOTE_STR: &str = "’";

#[derive(Debug)]
pub enum PqLiteError {
    UnmatchedOpen {
        opening_at_index: usize,
        opening: &'static str,
        expected_close: &'static str,
    },
    Io(io::Error),
    Utf8(std::string::FromUtf8Error),
}
impl PqLiteError {
    fn unmatched(
        opening_at_index: usize,
        opening: &'static str,
        expected_close: &'static str,
    ) -> Self {
        PqLiteError::UnmatchedOpen {
            opening,
            opening_at_index,
            expected_close,
        }
    }
}
impl From<io::Error> for PqLiteError {
    fn from(e: io::Error) -> Self {
        PqLiteError::Io(e)
    }
}
impl From<std::string::FromUtf8Error> for PqLiteError {
    fn from(e: std::string::FromUtf8Error) -> Self {
        PqLiteError::Utf8(e)
    }
}

/// Utilize Rust's string slices to their fullest extent with an Ast.
///
/// We allocate Ast structs in memory, but critically, we never copy the
/// text! Every `&'a str` is a reference to the original string read in from
/// the input file. Rust's borrow checker ensures we never
///
/// Besides that, my main rationale for making an AST is to simplify the
/// parsing. With this, we can have a fairly simple initial parse, followed by
/// some postprocessing on the AST to handle each different kind of formatting.
///
/// This makes it easy to handle things like
/// ```
/// b‘hello world’[https://example.com]
/// ```
#[derive(Debug)]
pub enum Ast<'a> {
    Text(&'a str),
    CowText(Cow<'a, str>),
    NoBrText(&'a str),
    Root(Vec<Ast<'a>>),
    Quoted {
        original_text: &'a str,
        inner: Vec<Ast<'a>>,
    },
    Bracketed(Vec<Ast<'a>>),
    CurlyBraced(Vec<Ast<'a>>),
    BlockQuoted(Vec<Ast<'a>>),
    CodeQuoted(Vec<Ast<'a>>),
    TooltipText(Cow<'a, str>),
    ProcessedPrefixSuffix(&'static str, Vec<Ast<'a>>, &'static str),
    Header(
        /// A number, 1-6, to output.
        i32,
        /// The inner text
        Vec<Ast<'a>>,
    ),
    Tooltip {
        tooltip_text: Cow<'a, str>,
        inner: Vec<Ast<'a>>,
    },
    Link {
        link_location: &'a str,
        tooltip_text: Option<Cow<'a, str>>,
        inner: Vec<Ast<'a>>,
    },
}

pub fn write_wrapped_html_from_pqlite(
    input: &str,
    output: impl io::Write,
) -> Result<(), PqLiteError> {
    let ast = parse::parse_to_processed_ast(input)?;

    print::ast_to_wrapped_html(&ast, output)?;

    Ok(())
}

pub fn pqlite_to_unwrapped_html_string(input: &str) -> Result<String, PqLiteError> {
    let ast = parse::parse_to_processed_ast(input)?;

    let mut out = Vec::new();

    print::ast_to_unwrapped_html(&ast, &mut out)?;

    let out = String::from_utf8(out)?;

    Ok(out)
}
