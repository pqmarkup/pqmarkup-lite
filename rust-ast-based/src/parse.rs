use std::borrow::Cow;

use crate::{Ast, PqLiteError, CLOSE_QUOTE, CLOSE_QUOTE_STR, OPEN_QUOTE, OPEN_QUOTE_STR};

impl<'a> Ast<'a> {
    fn visit_direct_subnodes_mut<E>(
        &mut self,
        mut f: impl FnMut(&mut Ast<'a>) -> Result<(), E>,
    ) -> Result<(), E> {
        match self.children_mut() {
            Some(children) => {
                for node in children {
                    f(node)?;
                }
            }
            _ => (),
        }
        Ok(())
    }

    /// If this Ast node contains children nodes, return a list of them.
    fn children_mut(&mut self) -> Option<&mut Vec<Ast<'a>>> {
        match self {
            Ast::Root(nodes)
            | Ast::Quoted { inner: nodes, .. }
            | Ast::Bracketed(nodes)
            | Ast::CurlyBraced(nodes)
            | Ast::BlockQuoted(nodes)
            | Ast::CodeQuoted(nodes)
            | Ast::ProcessedPrefixSuffix(_, nodes, _)
            | Ast::Header(_, nodes)
            | Ast::Tooltip { inner: nodes, .. }
            | Ast::Link { inner: nodes, .. } => Some(nodes),
            Ast::Text(_) | Ast::CowText(_) | Ast::NoBrText(_) | Ast::TooltipText(_) => None,
        }
    }
}

/// Retrieves the first character in a string. Panics if the string is empty.
fn first_char(s: &str) -> char {
    s.chars().next().unwrap()
}

fn parse_to_unprocessed_ast<'a>(input: &'a str) -> Result<Ast<'a>, PqLiteError> {
    Ok(Ast::Root(parse_to_ast_inner(input, &mut 0, None)?))
}

fn parse_comment<'a>(
    input: &'a str,
    index: &mut usize,
    opening_index: usize,
) -> Result<(), PqLiteError> {
    // find 3 closing brackets
    let mut remaining = 3;
    while remaining > 0 {
        let next_i = *index
            + input[*index..]
                .find(&['[', ']'][..])
                .ok_or(PqLiteError::unmatched(opening_index, "[[[", "]"))?;
        let next_c = first_char(&input[next_i..]);
        match next_c {
            '[' => remaining += 1,
            ']' => remaining -= 1,
            _ => unreachable!(),
        }
        *index = next_i + next_c.len_utf8();
    }
    Ok(())
}

fn parse_code_block<'a>(
    input: &'a str,
    index: &mut usize,
    closing: &str,
) -> Result<Option<Ast<'a>>, PqLiteError> {
    let next_i = *index
        + match input[*index..].find(closing) {
            Some(i) => i,
            None => return Ok(None),
        };
    let inner = &input[*index..next_i];
    *index = next_i + closing.len();
    Ok(Some(Ast::CodeQuoted(vec![Ast::NoBrText(inner)])))
}

fn parse_to_ast_inner<'a>(
    input: &'a str,
    index: &mut usize,
    ending: Option<&'static str>,
) -> Result<Vec<Ast<'a>>, PqLiteError> {
    let mut parsed = Vec::new();
    while *index < input.len() {
        // first, let's find the next noteworth character
        let next_i = {
            let mut searched_through = *index;
            loop {
                let arr_with_ending_first_char;
                let search_chars = match ending {
                    Some(ending) => {
                        arr_with_ending_first_char =
                            [OPEN_QUOTE, '[', '{', '>', '`', first_char(ending)];
                        &arr_with_ending_first_char[..]
                    }
                    None => &[OPEN_QUOTE, '[', '{', '>', '`'][..],
                };
                let candidate = match input[searched_through..].find(search_chars) {
                    Some(i) => searched_through + i,
                    None => break None,
                };
                // we _actually_ want to search for "> ", not just ">", so let's
                // filter out any ">" that aren't followed by " ". We'll get
                // ">‘" later on, when post-processing the AST.
                if input[candidate..].starts_with('>') && !input[candidate..].starts_with("> ") {
                    searched_through = candidate + first_char(&input[candidate..]).len_utf8();
                    continue;
                }
                // same for ending
                if let Some(ending) = ending {
                    if input[candidate..].starts_with(first_char(ending))
                        && !input[candidate..].starts_with(ending)
                    {
                        searched_through = candidate + first_char(&input[candidate..]).len_utf8();
                        continue;
                    }
                }
                break Some(candidate);
            }
        };
        let next_i = match next_i {
            Some(i) => i,
            None => {
                // we have searched to the end of the string, and found nothing.
                // just push the rest of the string as plaintext.
                parsed.push(Ast::Text(&input[*index..]));
                *index = input.len();
                break;
            }
        };

        // push all the text up to the next interesting char as plaintext.
        parsed.push(Ast::Text(&input[*index..next_i]));
        *index = next_i;

        let next_s = {
            let next_c = first_char(&input[next_i..]);
            match next_c {
                OPEN_QUOTE => OPEN_QUOTE_STR,
                '[' => {
                    if input[next_i..].starts_with("[[[") {
                        "[[["
                    } else {
                        "["
                    }
                }
                '{' => "{",
                '`' => {
                    if input[next_i..].starts_with("```") {
                        "```"
                    } else if input[next_i..].starts_with("``") {
                        "``"
                    } else {
                        "`"
                    }
                }
                '>' => "> ",
                _ => {
                    let ending = ending.unwrap();
                    assert!(input[next_i..].starts_with(ending));
                    ending
                }
            }
        };

        if Some(next_s) == ending {
            // if the next interesting char is the closing char for our parent,
            // just exit now and let them deal with the rest.
            break;
        }

        *index += next_s.len();

        // otherwise, find our closing string.
        let closing_s = match next_s {
            OPEN_QUOTE_STR => CLOSE_QUOTE_STR,
            "[" => "]",
            "[[[" => "]]]",
            "{" => "}",
            "`" => "`",
            "``" => "``",
            "```" => "```",
            "> " => "\n",
            _ => unreachable!(),
        };

        if next_s == "[[[" {
            // we don't care about inner structures inside a comment.
            // we also don't care about adding the comment to the AST.
            parse_comment(input, index, next_i)?;
        } else if next_s.starts_with('`') {
            // we similarly don't care about inner structures of a code block.
            // but we _do_ care about the contents.
            match parse_code_block(input, index, closing_s)? {
                Some(c) => parsed.push(c),
                None => parsed.push(Ast::Text(next_s)),
            }
        } else {
            // now, we'll delegate finding all inner structures (and our closing
            // string) to a new invocation.
            let inner_ast = parse_to_ast_inner(input, index, Some(closing_s))?;

            if *index == input.len() {
                // we're missing a closing piece. We're a forgiving parser, so
                // what we'll do is put the starting string back in, then
                // just go on.
                parsed.push(Ast::Text(next_s));
                parsed.extend(inner_ast);
                break;
            } else {
                // if the inner invocation exited with input left, it should have
                // found our closing stirng. Verify this is the case (and panic
                // out otherwise).
                assert!(input[*index..].starts_with(closing_s));
                // we've processed the closing string.
                *index += closing_s.len();

                let ast = match next_s {
                    OPEN_QUOTE_STR => Ast::Quoted {
                        original_text: &input[next_i..*index],
                        inner: inner_ast,
                    },
                    "[" => Ast::Bracketed(inner_ast),
                    "{" => Ast::CurlyBraced(inner_ast),
                    "`" | "``" | "```" => Ast::CodeQuoted(inner_ast),
                    "> " => Ast::BlockQuoted(inner_ast),
                    _ => unreachable!(),
                };
                parsed.push(ast);
            }
        }
    }
    Ok(parsed)
}

// ---
// AST Processing Functions
// ---

/// Minimizes the AST by removing empty text nodes.
/// Necessay for some subsequent processing to work.
fn remove_empty_text(ast: &mut Ast<'_>) -> Result<(), PqLiteError> {
    // process inner nodes first
    ast.visit_direct_subnodes_mut(remove_empty_text)?;
    if let Some(children) = ast.children_mut() {
        children.retain(|child| match child {
            Ast::Text(s) => !s.is_empty(),
            _ => true,
        });
    }
    Ok(())
}

fn process_ast_quotes(ast: &mut Ast<'_>) -> Result<(), PqLiteError> {
    // process inner nodes first
    ast.visit_direct_subnodes_mut(process_ast_quotes)?;
    if let Some(children) = ast.children_mut() {
        'children_loop: for i in 1..children.len() {
            let split_to_access_children = children.split_at_mut(i);
            let child1 = &mut split_to_access_children.0[i - 1];
            let child2 = &mut split_to_access_children.1[0];
            if let (Ast::Text(pre), Ast::Quoted { inner, .. }) = (&mut *child1, &mut *child2) {
                const SIMPLE_RULES: &[(&str, &str, &str)] = &[
                    ("*", "<b>", "</b>"),
                    ("_", "<u>", "</u>"),
                    ("-", "<s>", "</s>"),
                    ("~", "<i>", "</i>"),
                    (">", "<blockquote>", "</blockquote>"),
                    ("H", "<h3>", "</h3>"),
                    ("/\\", "<sup>", "</sup>"),
                    ("\\/", "<sub>", "</sub>"),
                ];
                for (start, prefix, postfix) in SIMPLE_RULES {
                    if pre.ends_with(start) {
                        // remove formatting character from text before
                        *child1 = Ast::Text(&pre[0..pre.len() - start.len()]);
                        // replace quoted block with prefix+suffix'd block
                        *child2 =
                            Ast::ProcessedPrefixSuffix(prefix, std::mem::take(inner), postfix);
                        // skip all remaining transforms for this child1, child2 pairing
                        continue 'children_loop;
                    }
                }
                // test for Header
                if pre.ends_with(')') {
                    if let Some(h_idx) = pre.rfind("H(") {
                        let header_number_as_str =
                            &pre[h_idx + "H(".len()..pre.len() - ')'.len_utf8()];
                        if let Ok(header_number) = header_number_as_str.parse::<i32>() {
                            // H0 or H in the source is <h3> in output.
                            // additionally, negative input results in a
                            // smaller header, which means a larger number
                            // in the output
                            let h = 3 - header_number;
                            if h >= 1 && h <= 6 {
                                *child1 = Ast::Text(&pre[0..h_idx]);
                                *child2 = Ast::Header(h, std::mem::take(inner))
                            }
                            // even if the number wasn't valid, we've found
                            // the prefix _was_ supposed to be a header.
                            // Let's thus stop.
                            continue 'children_loop;
                        }
                    }
                }
            }
        }
    }
    Ok(())
}

fn process_spoilers(ast: &mut Ast<'_>) -> Result<(), PqLiteError> {
    // process inner nodes first
    ast.visit_direct_subnodes_mut(process_spoilers)?;
    if let Some(children) = ast.children_mut() {
        for child in children {
            if let Ast::CurlyBraced(inner) = child {
                let prefix = r#"<span class="cu_brackets" onclick="return spoiler(this, event)"><span class="cu_brackets_b">{</span><span>…</span><span class="cu" style="display: none">"#;
                let postfix = r#"</span><span class="cu_brackets_b">}</span></span>"#;
                *child = Ast::ProcessedPrefixSuffix(prefix, std::mem::take(inner), postfix);
            }
        }
    }
    Ok(())
}

fn is_url_tooltip(child2: &Ast<'_>) -> bool {
    let bracketed_ast = match child2 {
        Ast::Bracketed(v) => v,
        _ => return false,
    };
    let tooltip = match bracketed_ast.last() {
        Some(Ast::Quoted { .. }) => true,
        Some(Ast::TooltipText(_)) => true,
        _ => false,
    };
    let url = match bracketed_ast.first() {
        Some(Ast::Text(_)) => true,
        _ => false,
    };
    match (tooltip, url, bracketed_ast.len()) {
        (true, false, 1) | (false, true, 1) | (true, true, 2) => true,
        _ => false,
    }
}

fn bracket_child_to_url_and_tooltip<'a>(
    child2: Ast<'a>,
) -> (Option<&'a str>, Option<Cow<'a, str>>) {
    let bracketed_ast = match child2 {
        Ast::Bracketed(v) => v,
        _ => return (None, None),
    };
    let mut iter = bracketed_ast.into_iter();
    let first = iter.next();
    let second = iter.next();
    if iter.next().is_some() {
        return (None, None);
    }
    match (first, second) {
        (Some(Ast::TooltipText(tooltip)), None) => (None, Some(tooltip)),
        (Some(Ast::Text(url)), Some(Ast::TooltipText(tooltip))) => {
            (Some(url.trim_end()), Some(tooltip))
        }
        (Some(Ast::Text(url)), None) => (Some(url.trim_end()), None),
        _ => (None, None),
    }
}

/// This is a necessary repetition of other comment removal, as regular comment
/// removal happens alongside parsing the entire source into an AST tree, and
/// that makes other adjustments such as equating syntactically-equivalent
/// source bits.
fn remove_comments_for_tooltip(original_text: &str) -> Result<Cow<'_, str>, PqLiteError> {
    let mut result = String::new();
    let mut index = 0;
    while index < original_text.len() {
        let next_i = match original_text[index..].find("[[[") {
            Some(i) => index + i,
            None => {
                if index == 0 {
                    return Ok(original_text.into());
                } else {
                    result.push_str(&original_text[index..]);
                    break;
                }
            }
        };
        result.push_str(&original_text[index..next_i]);
        index = next_i + "[[[".len();
        parse_comment(original_text, &mut index, next_i)?;
    }
    Ok(result.into())
}

/// Replace tooltip text with TooltipText element to prevent further processing
/// of text inside.
fn pull_out_tooltip_text(ast: &mut Ast<'_>) -> Result<(), PqLiteError> {
    if let Some(children) = ast.children_mut() {
        for child in children {
            if is_url_tooltip(&child) {
                let bracketed_ast = match child {
                    Ast::Bracketed(v) => v,
                    _ => unreachable!(),
                };
                let inner_last = match bracketed_ast.last_mut() {
                    Some(v) => v,
                    None => continue,
                };
                match inner_last {
                    Ast::Quoted { original_text, .. } => {
                        *inner_last = Ast::TooltipText(remove_comments_for_tooltip(
                            original_text
                                .trim_start_matches(OPEN_QUOTE)
                                .trim_end_matches(CLOSE_QUOTE),
                        )?)
                    }
                    _ => continue,
                }
            }
        }
    }
    // process inner nodes last
    ast.visit_direct_subnodes_mut(pull_out_tooltip_text)?;
    Ok(())
}

// match child1 {
//     Ast::Text(s) if s.split_ascii_whitespace().next().is_none() => return false,
//     _ => (),
// }
fn process_brackets(ast: &mut Ast<'_>) -> Result<(), PqLiteError> {
    // process inner nodes first
    ast.visit_direct_subnodes_mut(process_brackets)?;
    if let Some(children) = ast.children_mut() {
        let mut i = 0;
        while i < children.len() {
            let split_to_access_children = children.split_at_mut(i);
            let mut child1 = match i {
                0 => None,
                _ => Some(&mut split_to_access_children.0[i - 1]),
            };
            let child2 = &mut split_to_access_children.1[0];
            if is_url_tooltip(&child2) {
                let child2_owned = std::mem::replace(child2, Ast::Text(""));
                let (url, tooltip) = bracket_child_to_url_and_tooltip(child2_owned);
                let (extra_text, inner) = if let Some(child1) = &mut child1 {
                    let child1_owned = std::mem::replace(*child1, Ast::Text(""));
                    match child1_owned {
                        Ast::Text(s) => match s.rsplit_once(|c: char| c.is_ascii_whitespace()) {
                            None => (None, vec![Ast::Text(s)]),
                            Some((_, after)) if after.is_empty() => (
                                Some(Ast::Text(s)),
                                vec![Ast::CowText(
                                    url.map(Cow::from).or_else(|| tooltip.clone()).unwrap(),
                                )],
                            ),
                            Some((before, after)) => {
                                (Some(Ast::Text(before)), vec![Ast::Text(after)])
                            }
                        },
                        Ast::Quoted { inner, .. } => (None, inner),
                        other => (None, vec![other]),
                    }
                } else {
                    (
                        None,
                        vec![Ast::CowText(
                            url.map(Cow::from).or_else(|| tooltip.clone()).unwrap(),
                        )],
                    )
                };
                let applied = match (tooltip, url) {
                    (Some(tooltip_text), None) => Ast::Tooltip {
                        tooltip_text,
                        inner,
                    },
                    (tooltip_text, Some(url)) => Ast::Link {
                        link_location: url,
                        tooltip_text,
                        inner,
                    },
                    _ => unreachable!(),
                };
                *child2 = applied;
                if let Some(child1) = child1 {
                    match extra_text {
                        Some(extra_text) => *child1 = extra_text,
                        None => {
                            children.remove(i - 1);
                            i -= 1;
                        }
                    }
                }
            }
            i += 1;
        }
    }
    Ok(())
}

fn process_ast(ast: &mut Ast<'_>) -> Result<(), PqLiteError> {
    remove_empty_text(ast)?;
    pull_out_tooltip_text(ast)?;
    process_ast_quotes(ast)?;
    process_spoilers(ast)?;
    process_brackets(ast)?;
    Ok(())
}

pub fn parse_to_processed_ast<'a>(input: &'a str) -> Result<Ast<'a>, PqLiteError> {
    let mut ast = parse_to_unprocessed_ast(input)?;
    process_ast(&mut ast)?;
    Ok(ast)
}
