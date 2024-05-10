//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Markdown
import SwiftSyntax

extension StringProtocol {
  /// Trims whitespace from the end of a string, returning a new string with
  /// no trailing whitespace.
  ///
  /// If the string is only whitespace, an empty string is returned.
  ///
  /// - Returns: The string with trailing whitespace removed.
  func trimmingTrailingWhitespace() -> String {
    if isEmpty { return String() }
    let scalars = unicodeScalars
    var idx = scalars.index(before: scalars.endIndex)
    while scalars[idx].properties.isWhitespace {
      if idx == scalars.startIndex { return String() }
      idx = scalars.index(before: idx)
    }
    return String(String.UnicodeScalarView(scalars[...idx]))
  }
}

struct Comment {
  enum Kind {
    case line, docLine, block, docBlock

    /// The length of the characters starting the comment.
    var prefixLength: Int {
      switch self {
      // `//`, `/*`
      case .line, .block: return 2
      // `///`, `/**`
      case .docLine, .docBlock: return 3
      }
    }

    var prefix: String {
      switch self {
      case .line: return "//"
      case .block: return "/*"
      case .docBlock: return "/**"
      case .docLine: return "///"
      }
    }
  }

  let kind: Kind
  var text: [String]
  var length: Int

  init(kind: Kind, text: String) {
    self.kind = kind

    switch kind {
    case .line, .docLine:
      self.text = [text]
      self.text[0].removeFirst(kind.prefixLength)
      self.length = self.text.reduce(0, { $0 + $1.count + kind.prefixLength + 1 })

    case .block, .docBlock:
      var fulltext: String = text
      fulltext.removeFirst(kind.prefixLength)
      fulltext.removeLast(2)
      let lines = fulltext.split(separator: "\n", omittingEmptySubsequences: false)

      // The last line in a block style comment contains the "*/" pattern to end the comment. The
      // trailing space(s) need to be kept in that line to have space between text and "*/".
      var trimmedLines = lines.dropLast().map({ $0.trimmingTrailingWhitespace() })
      if let lastLine = lines.last {
        trimmedLines.append(String(lastLine))
      }
      self.text = trimmedLines
      self.length = self.text.reduce(0, { $0 + $1.count }) + kind.prefixLength + 3
    }
  }

  func print(indent: [Indent], availableWidth: Int, maxCommentWidth: Int, format: Bool) -> String {
    switch self.kind {
    case .docLine where format:
      let indentation = indent.indentation()
      let usableWidth = availableWidth - indentation.count
      let wrappedLines = markdownFormat(
        self.text, min(usableWidth - kind.prefixLength, maxCommentWidth))
      let emptyLinesTrimmed = wrappedLines.map {
        if $0.allSatisfy({ $0.isWhitespace }) {
          return kind.prefix
        } else {
          return kind.prefix + " " + $0
        }
      }
      return emptyLinesTrimmed.joined(separator: "\n" + indentation)
    case .line, .docLine:
      let separator = "\n" + indent.indentation() + kind.prefix
      // trailing whitespace is meaningful in Markdown, so we can't remove it
      // when formatting comments, but we can here
      let trimmedLines = self.text.map { $0.trimmingTrailingWhitespace() }
      return kind.prefix + trimmedLines.joined(separator: separator)
    case .block, .docBlock:
      let separator = "\n"
      return kind.prefix + self.text.joined(separator: separator) + "*/"
    }
  }

  mutating func addText(_ text: [String]) {
    for line in text {
      self.text.append(line)
      self.length += line.count + self.kind.prefixLength + 1
    }
  }
}

/// Feed the given text into the Markdown document formatter and return
/// the resulting formatted text.
///
/// - Parameters:
///   - lines: The lines of text to be formatted.
///   - maxLength: Maximum length of a line of formatted text.
/// - Returns: The Markdown-formatted lines.
fileprivate func markdownFormat(_ lines: [String], _ maxLength: Int) -> [String] {
  let document = Document(parsing: lines.joined(separator: "\n"), options: .disableSmartOpts)
  let lineLimit = MarkupFormatter.Options.PreferredLineLimit(
    maxLength: maxLength,
    breakWith: .softBreak
  )
  let formatterOptions = MarkupFormatter.Options(
    orderedListNumerals: .incrementing(start: 1),
    useCodeFence: .always,
    condenseAutolinks: false,
    preferredLineLimit: lineLimit
  )
  let output = document.format(options: formatterOptions)
  let lines = output.split(separator: "\n")
  return lines.map {
    // unfortunately we have to do a bit of post-processing; the formatter uses double-space
    // as a forced line break, but a lot of editors and formatters remove trailing whitespace.
    // replace the double-space with a trailing backslash, which is also a force line break
    if let last = $0.last, let secondLast = $0.dropLast().last,
      last.isWhitespace && secondLast.isWhitespace
    {
      return $0.trimmingTrailingWhitespace() + " \\"
    } else {
      return $0.trimmingTrailingWhitespace()
    }
  }
}
