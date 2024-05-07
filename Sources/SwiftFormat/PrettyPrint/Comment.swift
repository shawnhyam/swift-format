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
  /// Trims whitespace from the end of a string, returning a new string with no trailing whitespace.
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

  func findBreakIndex(_ maxWidth: Int) -> Self.Index {
    let baseIndex = self.index(self.startIndex, offsetBy: maxWidth)
    let substr = self[..<baseIndex]

    if let sliceIdx = substr.lastIndex(where: { $0.isWhitespace }), sliceIdx != substr.firstIndex(where: { $0.isWhitespace }) {
      return sliceIdx
    } else if let sliceIdx = self[endIndex...].firstIndex(where: { $0.isWhitespace }) {
      return sliceIdx
    } else {
      return self.endIndex
    }
  }

  func canFlowInto() -> Bool {
    if #available(macOS 13.0, *) {
      return !self.trimmingPrefix(while: { $0.isWhitespace }).starts(with: "-")
    } else {
      // Fallback on earlier versions
      return false
    }
  }

  var indent: Int {
    if let prefix = self.firstIndex(where: { !$0.isWhitespace }) {
      if self[prefix...prefix] == "-" {
        return self[..<prefix].count + 1
      }
    }
    return 0
  }
}

fileprivate extension Array where Element == String {
  func markdownFormat(_ usableWidth: Int, linePrefix: String = "") -> [String] {
    let linePrefix = linePrefix + " "
    let document = Document(parsing: self.joined(separator: "\n"), options: .disableSmartOpts)
    let lineLimit = MarkupFormatter.Options.PreferredLineLimit(
      maxLength: usableWidth,
      breakWith: .softBreak
    )
    let formatterOptions = MarkupFormatter.Options(
      orderedListNumerals: .incrementing(start: 1),
      useCodeFence: .onlyWhenLanguageIsPresent,
      condenseAutolinks: false,
      preferredLineLimit: lineLimit,
      customLinePrefix: linePrefix
    )
    let output = document.format(options: formatterOptions)
    let lines = output.split(separator: "\n")
    if lines.isEmpty {
      return [linePrefix]
    }
    return lines.map { String($0) }
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

  func print(indent: [Indent], width: Int, wrap: Bool) -> String {
    switch self.kind {
    case .line, .docLine:
      if wrap {
        let indentation = indent.indentation()
        let usableWidth = width - indentation.count
        let wrappedLines = self.text.markdownFormat(usableWidth, linePrefix: kind.prefix)
        return wrappedLines.joined(separator: "\n" + indentation)
      } else {
        let separator = "\n" + indent.indentation() + kind.prefix
        // trailing whitespace is meaningful in Markdown, so we can't remove it
        // when formatting comments, but we can here
        let trimmedLines = self.text.map { $0.trimmingTrailingWhitespace() }
        return kind.prefix + trimmedLines.joined(separator: separator)
      }
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
