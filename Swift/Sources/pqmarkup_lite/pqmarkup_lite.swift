import Foundation

// MARK: - General Utilities

func printToStandardError(_ message: String) {
  FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
}

extension Array: ExpressibleByExtendedGraphemeClusterLiteral, ExpressibleByStringInterpolation,
  ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral
where Element == Unicode.Scalar {

  public init(extendedGraphemeClusterLiteral value: Character) {
    self.init(value.unicodeScalars)
  }

  public init(stringLiteral value: String) {
    self.init(value.unicodeScalars)
  }

  public init(unicodeScalarLiteral value: Unicode.Scalar) {
    self = [value]
  }
}

extension Collection where Element: Equatable {

  func count(of condition: Element) -> Int {
    return lazy.filter({ $0 == condition }).count
  }

  func firstOccurrence<T>(of searchTerm: T) -> SubSequence?
  where T: Collection, T.Element == Element {
    guard let start = indices.first(where: { self[$0...].starts(with: searchTerm) }) else {
      return nil
    }
    return self[start...].prefix(searchTerm.count)
  }

  func split<S>(separator: S) -> [SubSequence] where S: Collection, S.Element == Element {
    var result: [SubSequence] = []
    var cursor = startIndex
    while let next = self[cursor...].firstOccurrence(of: separator) {
      result.append(self[cursor..<next.startIndex])
      cursor = next.endIndex
    }
    result.append(self[cursor..<endIndex])
    return result
  }

  func splitAtFirst<S>(separator: S) -> (SubSequence, SubSequence)?
  where S: Collection, S.Element == Element {
    guard let first = firstOccurrence(of: separator) else {
      return nil
    }
    return (self[..<first.startIndex], self[first.endIndex...])
  }
}

extension DefaultStringInterpolation {

  mutating func appendInterpolation<S>(_ interpolation: S)
  where S: Collection, S.Element == Unicode.Scalar {
    appendInterpolation(String(interpolation))
  }
  mutating func appendInterpolation<S>(_ interpolation: S)
  where S: Collection, S.Element == Unicode.Scalar, S: CustomStringConvertible {
    appendInterpolation(String(interpolation))
  }
}

extension RangeReplaceableCollection where Element: Equatable {

  func replacingOccurrences<T, R>(of searchTerm: T, with replacement: R) -> Self
  where R: Collection, R.Element == Element, T: Collection, T.Element == Element {
    return Self(split(separator: searchTerm).lazy.joined(separator: replacement))
  }
}

extension String {

  init<S>(_ scalars: S) where S: Collection, S.Element == Unicode.Scalar {
    self.init(UnicodeScalarView(scalars))
  }
}

// MARK: - HTML Utilities

func escape<S>(text: S) -> S
where S: RangeReplaceableCollection, S.Element == Unicode.Scalar {
  return
    text
    .replacingOccurrences(of: "&".unicodeScalars, with: "&amp;".unicodeScalars)
    .replacingOccurrences(of: "<".unicodeScalars, with: "&lt;".unicodeScalars)
}
func escape<S>(attribute: S) -> S
where S: RangeReplaceableCollection, S.Element == Unicode.Scalar {
  return
    attribute
    .replacingOccurrences(of: "&".unicodeScalars, with: "&amp;".unicodeScalars)
    .replacingOccurrences(of: "\"".unicodeScalars, with: "&quot;".unicodeScalars)
}

// MARK: - Python Mimicry

extension Int {

  struct UnparsableNumber: Swift.Error {
    init<S>(source: S) where S: Collection, S.Element == Unicode.Scalar {
      self.source = String(String.UnicodeScalarView(source))
    }
    let source: String
  }

  init<S>(pythonInteger: S) throws where S: Collection, S.Element == Unicode.Scalar {
    let relevant = try pythonInteger.lazy.flatMap { (scalar) -> String in
      if scalar.properties.numericType == .decimal,
        let value: Int = scalar.properties.numericValue.flatMap({ Int(exactly: $0) })
      {
        return String(value)
      } else {
        switch scalar {
        case "+", "-":
          return String(scalar)
        case " ", "_":
          return ""
        default:
          throw UnparsableNumber(source: pythonInteger)
        }
      }
    }
    if let initialized = Int(String(relevant)) {
      self = initialized
    } else {
      throw UnparsableNumber(source: pythonInteger)
    }
  }
}

extension Unicode.Scalar {

  func isPythonDigit() -> Bool {
    return properties.numericType == .digit
      || properties.numericType == .decimal
  }
}

// MARK: - PQMarkup

struct Error: Swift.Error {

  let message: String
  let line: Int
  let column: Int
  let position: Int

  init<S>(message: S, line: Int, column: Int, position: Int)
  where S: Collection, S.Element == Unicode.Scalar {
    self.message = String(message)
    self.line = line
    self.column = column
    self.position = position
  }
}

class Parser {

  var outerPositionList: [Int]
  let full: Bool
  var source: [Unicode.Scalar]

  init(full: Bool) {
    self.outerPositionList = []
    self.full = full
    source = ""
  }

  func parse<S>(
    source: S,
    externalOffset: Int = 0
  ) throws -> [Unicode.Scalar]
  where S: Collection, S.Element == Unicode.Scalar {
    let source = [Unicode.Scalar](source)
    outerPositionList.append(externalOffset)

    var rendered: [Unicode.Scalar] = []

    if outerPositionList.count == 1 {
      self.source = source
    }

    func error(message: [Unicode.Scalar], position: Int) -> Error {
      var position = position
      position += outerPositionList.reduce(0, +)
      var line = 1
      var lineStart = -1
      for index in 0..<position {
        if self.source[index] == "\n" {
          line += 1
          lineStart = index
        }
      }
      return Error(message: message, line: line, column: position - lineStart, position: position)
    }

    var cursor = source.startIndex

    func next(offset: Int = 1) -> Unicode.Scalar? {
      let index = cursor + offset
      return index < source.endIndex ? source[index] : nil
    }

    func continues<S>(with string: S) -> Bool
    where S: Collection, S.Element == Unicode.Scalar {
      return source[cursor...].dropFirst().starts(with: string)
    }

    func previous(offset: Int = 1) -> Unicode.Scalar? {
      let index = cursor - offset
      return index >= source.startIndex ? source[index] : nil
    }

    var writingCursor = source.startIndex

    func write(upTo targetPosition: Int, andResetWritingCursorTo newCursor: Int) {
      rendered.append(contentsOf: escape(text: source[writingCursor..<targetPosition]))
      writingCursor = newCursor
    }

    func writeUpToCursor(appending appendix: [Unicode.Scalar], skipping skipCount: Int = 1) {
      write(upTo: cursor, andResetWritingCursorTo: cursor + skipCount)
      rendered.append(contentsOf: appendix)
    }

    func findQuotationMark(
      pairedWith openingQuotationMark: Int
    ) throws -> Array<Unicode.Scalar>.SubSequence {
      assert(source[openingQuotationMark] == "‘")
      var nestingLevel = 0
      for index in source[openingQuotationMark...].indices {
        let scalar = source[index]
        if scalar == "‘" {
          nestingLevel += 1
        } else if scalar == "’" {
          nestingLevel -= 1
          if nestingLevel == 0 {
            return source[index...index]
          }
        }
      }
      throw error(message: "Unpaired left single quotation mark", position: openingQuotationMark)
    }

    func findBracket<S>(
      in source: S,
      pairedWith openingBracket: S.Index,
      externalOffset: Int = 0
    ) throws -> S.SubSequence
    where S: Collection, S.Element == Unicode.Scalar {
      assert(source[openingBracket] == "[")
      var nestingLevel = 0
      for index in source[openingBracket...].indices {
        let scalar = source[index]
        if scalar == "[" {
          nestingLevel += 1
        } else if scalar == "]" {
          nestingLevel -= 1
          if nestingLevel == 0 {
            return source[index...index]
          }
        }
      }
      let internalOffset = source.distance(from: source.startIndex, to: openingBracket)
      throw error(message: "Unended comment started", position: externalOffset + internalOffset)
    }

    func removeComments<S>(
      from source: S,
      externalOffset: Int,
      level: Int = 3
    ) throws -> S
    where S: RangeReplaceableCollection, S.Element == Unicode.Scalar {
      var source = source
      var externalOffset = externalOffset
      let searchTerm = [Unicode.Scalar](repeating: "[", count: level)
      while let find = source.firstOccurrence(of: searchTerm) {
        let closingBracket = try findBracket(
          in: source,
          pairedWith: find.startIndex,
          externalOffset: externalOffset
        )
        externalOffset += source.distance(from: find.startIndex, to: closingBracket.endIndex)
        source.removeSubrange(find.startIndex..<closingBracket.endIndex)
      }
      return source
    }

    var link: [Unicode.Scalar] = ""

    func writeLink<R>(
      from location: R,
      quotationOffset: Int = 1,
      text: [Unicode.Scalar] = ""
    ) throws
    where R: RangeExpression, R.Bound == Array<Unicode.Scalar>.Index {
      let location = location.relative(to: source)
      var text = text

      var nestingLevel = 0
      cursor += 2

      var foundEnd = false
      for index in source[cursor...].indices {
        defer { cursor = index }
        let scalar = source[index]
        if scalar == "[" {
          nestingLevel += 1
        } else if scalar == "]" {
          if nestingLevel == 0 {
            foundEnd = true
            break
          }
          nestingLevel -= 1
        } else if scalar == " " {
          foundEnd = true
          break
        }
      }
      if !foundEnd {
        throw error(message: "Unended link", position: location.upperBound - 1 + quotationOffset)
      }

      link = escape(attribute: Array(source[location.upperBound + quotationOffset..<cursor]))
      var tag: [Unicode.Scalar] = #"<a href="\#(link)""#
      if link.starts(with: "./".unicodeScalars) {
        tag += #" target="_self""#
      }

      if source[cursor] == " " {
        tag += #" title=""#
        if next() == "‘" {
          let openingQuotationMark = source[source.index(after: cursor)...].prefix(1)
          let closingQuotationMark = try findQuotationMark(
            pairedWith: openingQuotationMark.startIndex
          )
          if source[closingQuotationMark.endIndex...].first != "]" {
            throw error(message: "Expected `]` after `’`", position: closingQuotationMark.endIndex)
          }
          tag += try escape(
            attribute: removeComments(
              from: source[openingQuotationMark.endIndex..<closingQuotationMark.startIndex],
              externalOffset: openingQuotationMark.endIndex
            )
          )
          cursor = closingQuotationMark.endIndex
        } else {
          let closingBracket = try findBracket(
            in: source,
            pairedWith: location.upperBound - 1 + quotationOffset
          )
          let start = cursor + 1
          tag += try escape(
            attribute: removeComments(
              from: source[start..<closingBracket.startIndex],
              externalOffset: start
            )
          )
          cursor = closingBracket.startIndex
        }
        tag += "\""
      }
      if next() == "[",
        next(offset: 2) == "-"
      {
        for index in source[cursor...].dropFirst(3).indices {
          if source[index] == "]" {
            cursor = index
            break
          }
          if !source[index].isPythonDigit() {
            break
          }
        }
      }
      if text == "" {
        write(upTo: location.lowerBound, andResetWritingCursorTo: cursor + 1)
        text = try self.parse(
          source: source[location.lowerBound + quotationOffset..<location.upperBound - 1],
          externalOffset: location.lowerBound + quotationOffset
        )
      }
      rendered.append(contentsOf: "\(tag)>\(text != "" ? text : link)</a>".unicodeScalars)
    }

    func writeAbbreviation(from location: Range<Int>, quotationOffset: Int = 1) throws {
      cursor += quotationOffset
      let openingQuotationMark = source[cursor...].dropFirst().prefix(1)
      let closingQuotationMark = try findQuotationMark(pairedWith: openingQuotationMark.startIndex)
      if source[closingQuotationMark.endIndex...].first != "]" {
        throw error(
          message: "Bracket ] should follow after ’",
          position: closingQuotationMark.endIndex
        )
      }
      write(upTo: location.lowerBound, andResetWritingCursorTo: closingQuotationMark.endIndex + 1)
      let title = try escape(
        attribute: removeComments(
          from: source[openingQuotationMark.endIndex..<closingQuotationMark.startIndex],
          externalOffset: openingQuotationMark.endIndex
        )
      )
      let contents = try escape(
        text: removeComments(
          from: source[location.lowerBound + quotationOffset..<location.upperBound - 1],
          externalOffset: location.lowerBound + quotationOffset
        )
      )
      rendered.append(
        contentsOf: #"<abbr title="\#(title)">\#(contents)</abbr>"#.unicodeScalars
      )
      cursor = closingQuotationMark.endIndex
    }

    var endingTags: [[Unicode.Scalar]] = []
    var newLineTag: [Unicode.Scalar]? = nil

    while cursor < source.endIndex {
      var scalar = source[cursor]
      if cursor == source.startIndex
        || previous() == "\n"
        || (cursor == writingCursor
          && !endingTags.isEmpty
          && ["</blockquote>", "</div>"].contains(endingTags.last)
          && ([">‘", "<‘", "!‘"] as [[Unicode.Scalar]])
            .contains(where: { $0.elementsEqual(source[..<cursor].suffix(2)) }))
      {
        if scalar == ".",
          next() == " "
        {
          writeUpToCursor(appending: "•")
        } else if scalar == " " {
          writeUpToCursor(appending: "&emsp;")
        } else if [">", "<"].contains(scalar),
          [" ", "‘", "["].contains(next())
        {
          write(upTo: cursor, andResetWritingCursorTo: cursor + 2)
          rendered.append(
            contentsOf: "<blockquote\(scalar == "<" ? #" class="re""# : "")>".unicodeScalars
          )
          if next() == " " {
            newLineTag = "</blockquote>"
          } else {
            if next() == "[" {
              if next(offset: 2) == "-",
                let possibleDigit = next(offset: 3),
                possibleDigit.isPythonDigit()
              {
                cursor =
                  source[cursor...].dropFirst(4).firstIndex(of: "]")
                  .map({ source.index(after: $0) })
                  ?? source.startIndex
                writingCursor = cursor + 2
              } else {
                cursor += 1
                let closingBracket = try findBracket(in: source, pairedWith: cursor)
                link = [Unicode.Scalar](source[cursor..<closingBracket.startIndex].dropFirst())
                if let space = link.firstIndex(of: " ") {
                  link = [Unicode.Scalar](link[..<space])
                }
                if link.count > 57 {
                  let slash = (link.prefix(47).lastIndex(of: "/") ?? link.startIndex) + 1
                  link = "\(link[..<slash])..."
                }
                try writeLink(
                  from: cursor...cursor,
                  quotationOffset: 0,
                  text: "<i>\(link)</i>"
                )
                cursor += 1
                if !source[cursor...].prefix(2).elementsEqual(":‘".unicodeScalars) {
                  let upToColon = link.prefix(while: { $0 != ":" })
                  throw error(
                    message:
                      "Quotation with url should always has :‘...’ after [\(upToColon)://url]",
                    position: cursor
                  )
                }
                rendered.append(contentsOf: ":<br />\n".unicodeScalars)
                writingCursor = cursor + 2
              }
            } else {
              let closingQuotationMark = try findQuotationMark(pairedWith: cursor + 1)
              if source[closingQuotationMark.endIndex...].first == "[" {
                let openingQuotationMark = source[cursor...].dropFirst().prefix(1)
                cursor = closingQuotationMark.startIndex
                rendered.append(contentsOf: "<i>".unicodeScalars)
                assert(writingCursor == openingQuotationMark.endIndex)
                writingCursor = openingQuotationMark.startIndex
                try writeLink(
                  from: openingQuotationMark.startIndex..<closingQuotationMark.endIndex
                )
                rendered.append(contentsOf: "</i>".unicodeScalars)
                cursor += 1
                if !source[cursor...].prefix(2).elementsEqual(":‘".unicodeScalars) {
                  let upToColon = link.prefix(while: { $0 != ":" })
                  throw error(
                    message:
                      "Quotation with url should always has :‘...’ after [\(upToColon)://url]",
                    position: cursor
                  )
                }
                rendered.append(contentsOf: ":<br />\n".unicodeScalars)
                writingCursor = cursor + 2
              } else if source[closingQuotationMark.endIndex...].first == ":" {
                rendered.append(
                  contentsOf:
                    "<i>\(source[cursor..<closingQuotationMark.startIndex].dropFirst(2))</i>:<br />\n"
                    .unicodeScalars
                )
                cursor = closingQuotationMark.endIndex
                if !source[cursor...].prefix(2).elementsEqual(":‘".unicodeScalars) {
                  throw error(
                    message:
                      "Quotation with author's name should be in the form >‘Author's name’:‘Quoted text.’",
                    position: cursor
                  )
                }
                writingCursor = cursor + 2
              }
            }
            endingTags.append("</blockquote>")
          }
          cursor += 2
          continue
        }
      }

      if scalar == "‘" {
        var previousIndex = cursor == source.startIndex ? nil : source.index(before: cursor)
        var previous = previousIndex.map { source[$0] }
        let openingQuotationMark = source[cursor...].prefix(1)
        let closingQuotationMark = try findQuotationMark(pairedWith: cursor)
        cursor = closingQuotationMark.startIndex
        var parenthesis: [Unicode.Scalar] = ""
        if previous == ")",
          let openingParenthesis = previousIndex.flatMap({ source[..<$0].lastIndex(of: "(") })
        {
          parenthesis = [Unicode.Scalar](
            source[openingParenthesis..<openingQuotationMark.startIndex].dropFirst().dropLast()
          )
          previousIndex = openingParenthesis - 1
          previous = previousIndex.map { source[$0] }
        }
        if continues(with: "[http".unicodeScalars)
          || continues(with: "[./".unicodeScalars)
        {
          try writeLink(from: openingQuotationMark.startIndex..<closingQuotationMark.endIndex)
        } else if continues(with: "[‘".unicodeScalars) {
          try writeAbbreviation(
            from: openingQuotationMark.startIndex..<closingQuotationMark.endIndex
          )
        } else if let previousIndex = previousIndex,
          ["0", "O", "О"].contains(previous)
        {
          write(upTo: previousIndex, andResetWritingCursorTo: closingQuotationMark.endIndex)
          rendered.append(
            contentsOf: escape(
              text: source[openingQuotationMark.endIndex..<closingQuotationMark.startIndex]
            )
            .replacingOccurrences(of: "\n".unicodeScalars, with: "<br />\n".unicodeScalars)
          )
        } else if let previousIndex = previousIndex,
          let prevc = previous,
          ["<", ">"].contains(prevc),
          ["<", ">"].contains(source[..<previousIndex].last)
        {
          let operatorStart = source.index(before: previousIndex)
          write(upTo: operatorStart, andResetWritingCursorTo: closingQuotationMark.endIndex)
          let attributeDictionary: [[Unicode.Scalar]: [Unicode.Scalar]] = [
            "<<": "left", ">>": "right", "><": "center", "<>": "justify",
          ]
          let attribute = attributeDictionary[[source[operatorStart], prevc]]!
          let contents = try self.parse(
            source: source[openingQuotationMark.endIndex..<closingQuotationMark.startIndex],
            externalOffset: openingQuotationMark.endIndex
          )
          rendered.append(
            contentsOf: #"<div align="\#(attribute)">\#(contents)</div>\#n"#.unicodeScalars
          )
          newLineTag = ""
        } else if continues(with: ":‘".unicodeScalars),
          try source[findQuotationMark(pairedWith: cursor + 2).endIndex...].first == "<"
        {
          let secondClosingQuotationMark = try findQuotationMark(pairedWith: cursor + 2)
          cursor = secondClosingQuotationMark.endIndex
          let afterPrevious = previousIndex.map({ source.index(after: $0) }) ?? source.startIndex
          write(upTo: afterPrevious, andResetWritingCursorTo: cursor + 1)
          let quotation = try self.parse(
            source: source[openingQuotationMark.endIndex..<closingQuotationMark.startIndex],
            externalOffset: openingQuotationMark.endIndex
          )
          let citation = source[
            closingQuotationMark.endIndex..<secondClosingQuotationMark.startIndex
          ].dropFirst(2)
          rendered.append(
            contentsOf:
              "<blockquote>\(quotation)<br />\n<div align='right'><i>\(citation)</i></div></blockquote>"
              .unicodeScalars
          )
          newLineTag = ""
        } else {
          cursor = openingQuotationMark.startIndex
          if let previous = previous,
            ["*", "_", "-", "~"].contains(previous)
          {
            write(upTo: cursor - 1, andResetWritingCursorTo: cursor + 1)
            let tagDictionary: [Unicode.Scalar: [Unicode.Scalar]] = [
              "*": "b", "_": "u", "-": "s", "~": "i",
            ]
            let tag = tagDictionary[previous]!
            rendered.append(contentsOf: "<\(tag)>".unicodeScalars)
            endingTags.append("</\(tag)>")
          } else if let previousIndex = previousIndex,
            ["H", "Н"].contains(previous)
          {
            write(upTo: previousIndex, andResetWritingCursorTo: cursor + 1)
            let parsedLevel = try parenthesis == "" ? 0 : Int(pythonInteger: parenthesis)
            let level: Int = min(max(3 - parsedLevel, 1), 6)
            let tag = "h\(level)"
            rendered.append(contentsOf: "<\(tag)>".unicodeScalars)
            endingTags.append("</\(tag)>")
          } else if let previousIndex = previousIndex,
            [("/", "\\"), ("\\", "/")]
              .contains(where: { $0 == (source[..<previousIndex].last, previous) })
          {
            write(upTo: previousIndex - 1, andResetWritingCursorTo: cursor + 1)
            let tag = (source[previousIndex - 1], previous) == ("/", "\\") ? "sup" : "sub"
            rendered.append(contentsOf: "<\(tag)>".unicodeScalars)
            endingTags.append("</\(tag)>")
          } else if let previousIndex = previousIndex,
            previous == "!"
          {
            write(upTo: previousIndex, andResetWritingCursorTo: cursor + 1)
            rendered.append(contentsOf: #"<div class="note">"#.unicodeScalars)
            endingTags.append("</div>")
          } else {
            endingTags.append("’")
          }
        }
      } else if scalar == "’" {
        write(upTo: cursor, andResetWritingCursorTo: cursor + 1)
        guard let last = endingTags.popLast() else {
          throw error(message: "Unpaired right single quotation mark", position: cursor)
        }
        rendered.append(contentsOf: last)
        if next() == "\n",
          last.starts(with: "</h".unicodeScalars)
            || ["</blockquote>", "</div>"].contains(last)
        {
          rendered.append("\n")
          cursor += 1
          writingCursor += 1
        }
      } else if scalar == "`" {
        let start = cursor
        cursor += 1
        cursor = source[cursor...].firstIndex(where: { $0 != "`" }) ?? source.endIndex
        guard
          let endGrave = source[cursor...]
            .firstOccurrence(of: [Unicode.Scalar](repeating: "`", count: cursor - start))
        else {
          throw error(message: "Unended ` started", position: start)
        }
        write(upTo: start, andResetWritingCursorTo: endGrave.endIndex)
        var contents = [Unicode.Scalar](source[cursor..<endGrave.startIndex])
        let unbalancedQuotationMarks = contents.count(of: "‘") - contents.count(of: "’")
        if unbalancedQuotationMarks > 0 {
          for _ in 0..<unbalancedQuotationMarks {
            endingTags.append("’")
          }
        } else {
          for _ in 0 ..< -unbalancedQuotationMarks {
            if endingTags.popLast() != "’" {
              throw error(
                message: "Unpaired single quotation mark found inside code block/span beginning",
                position: start
              )
            }
          }
        }
        contents = escape(text: contents)
        if !contents.contains("\n") {
          rendered.append(
            contentsOf: #"<pre class="inline_code">\#(contents)</pre>"#.unicodeScalars
          )
        } else {
          rendered.append(contentsOf: "<pre>\(contents)</pre>\n".unicodeScalars)
          newLineTag = ""
        }
        cursor = endGrave.endIndex - 1
      } else if scalar == "[" {
        if continues(with: "http".unicodeScalars)
          || continues(with: "./".unicodeScalars)
          || (continues(with: "‘".unicodeScalars)
            && !["\r", "\n", "\t", " ", nil].contains(previous()))
        {
          var start = cursor - 1
          while start >= writingCursor,
            !["\r", "\n", "\t", " ", "[", "{", "("].contains(source[start])
          {
            start -= 1
          }
          if continues(with: "‘".unicodeScalars) {
            try writeAbbreviation(from: start + 1..<cursor + 1, quotationOffset: 0)
          } else if continues(with: "http".unicodeScalars)
            || continues(with: "./".unicodeScalars)
          {
            try writeLink(from: start + 1..<cursor + 1, quotationOffset: 0)
          } else {
            assert(false)
          }
        } else if continues(with: "[[".unicodeScalars) {
          let commentStart = cursor
          var nestingLevel = 0
          var foundEnd = false
          for index in source[cursor...].indices {
            defer { cursor = index }
            scalar = source[index]
            if scalar == "[" {
              nestingLevel += 1
            } else if scalar == "]" {
              nestingLevel -= 1
              if nestingLevel == 0 {
                foundEnd = true
                break
              }
            } else if scalar == "‘" {
              endingTags.append("’")
            } else if scalar == "’" {
              let last = endingTags.popLast()
              assert(last == "’")
            }
          }
          if !foundEnd {
            throw error(message: "Unended comment started", position: commentStart)
          }
          write(upTo: commentStart, andResetWritingCursorTo: cursor + 1)
        } else {
          if self.full {
            writeUpToCursor(appending: #"<span class="sq"><span class="sq_brackets">[</span>"#)
          } else {
            writeUpToCursor(appending: "[")
          }
        }
      } else if scalar == "]" {
        if self.full {
          writeUpToCursor(appending: #"<span class="sq_brackets">]</span></span>"#)
        } else {
          writeUpToCursor(appending: "]")
        }
      } else if scalar == "{" {
        if self.full {
          writeUpToCursor(
            appending:
              #"<span class="cu_brackets" onclick="return spoiler(this, event)"><span class="cu_brackets_b">{</span><span>…</span><span class="cu" style="display: none">"#
          )
        } else {
          writeUpToCursor(appending: "{")
        }
      } else if scalar == "}" {
        if self.full {
          writeUpToCursor(appending: #"</span><span class="cu_brackets_b">}</span></span>"#)
        } else {
          writeUpToCursor(appending: "}")
        }
      } else if scalar == "\n" {
        let lineBreak: [Unicode.Scalar] = newLineTag ?? "<br />"
        let newLine: [Unicode.Scalar] = (newLineTag != "" ? "\n" : "")
        writeUpToCursor(appending: lineBreak + newLine)
        newLineTag = nil
      }

      cursor += 1
    }

    write(upTo: source.endIndex, andResetWritingCursorTo: 0)
    if !endingTags.isEmpty {
      throw error(
        message: "Unclosed left single quotation mark somewhere",
        position: source.endIndex
      )
    }

    let last = outerPositionList.popLast()
    assert(last == externalOffset)

    return rendered
  }
}

extension String {

  func renderedHTML(full: Bool = false) throws -> String {
    return try String(Parser(full: full).parse(source: [Unicode.Scalar](unicodeScalars)))
  }
}

@main struct PQMarkup {

  static func main() throws {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("-t") {
      let testFile = try String(contentsOf: URL(fileURLWithPath: "tests.txt"), encoding: .utf8)
      let tests = testFile.unicodeScalars.split(separator: "|\n\n|".unicodeScalars)
      for test in tests {
        if let (left, right) = test.splitAtFirst(separator: " (()) ".unicodeScalars) {
          if try !String(left).renderedHTML().unicodeScalars.elementsEqual(right) {
            printToStandardError("Error in test |\(test)|")
            exit(1)
          }
        } else {
          printToStandardError("A test is missing “ (()) ”:\n\(test)")
          exit(1)
        }
      }
      print("All of \(tests.count) tests are passed!")
      exit(0)
    }

    guard let inputPath = arguments.dropFirst().first,
      let outputPath = arguments.dropFirst(2).first
    else {
      print("Usage: pqmarkup_lite input-file output-file")
      exit(0)
    }

    let sourceFile: String
    do {
      let url = URL(fileURLWithPath: inputPath)
      sourceFile = try String(contentsOf: url, encoding: .utf8)
    } catch {
      printToStandardError("Can't open file '\(inputPath)'")
      exit(1)
    }

    let rendered: String
    do {
      rendered = try sourceFile.renderedHTML(full: true)
    } catch let e as Error {
      printToStandardError("\(e.message) at line \(e.line), column \(e.column)\n")
      exit(-1)
    }

    let html =
      """
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
      <div id="main" style="margin: 0 auto">
      \(rendered)</div>
      </body>
      </html>
      """

    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )
    let data = html.data(using: .utf8)!
    try data.write(to: url, options: [.atomic])
  }
}
