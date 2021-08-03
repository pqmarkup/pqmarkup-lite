fn main() {
    let input = r#"‘[[[Scoping rules/]]]Code blocks’[./code-blocks]"#;
    let mut out = Vec::new();
    ast_pqlite::write_wrapped_html_from_pqlite(input, &mut out).unwrap();
    let out = std::str::from_utf8(&out).unwrap();
    println!("{}", out);
}
