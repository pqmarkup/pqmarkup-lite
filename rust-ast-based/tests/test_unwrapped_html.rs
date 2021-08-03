use std::path::PathBuf;

use ast_pqlite::pqlite_to_unwrapped_html_string;

#[test]
fn test_from_tests_txt() {
    let mut path = PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap());
    path.push("../tests.txt");
    let data = std::fs::read_to_string(path).unwrap();
    let test_cases = data.split("|\n\n|");

    let mut failure = false;

    for case in test_cases {
        let (input, output) = case
            .split_once(" (()) ")
            .unwrap_or_else(|| panic!("badly formatted test case: {:?}", case));

        println!("Running test case {:?}", input);
        let actual_output = pqlite_to_unwrapped_html_string(input).unwrap();

        if actual_output != output {
            eprintln!(
                "test failure:\n expected: {:?}\n   actual: {:?}\nfor input: {:?}",
                output, actual_output, input
            );
            failure = true;
        }
    }
    if failure {
        panic!("one or more test cases from tests.txt failed.");
    }
}
