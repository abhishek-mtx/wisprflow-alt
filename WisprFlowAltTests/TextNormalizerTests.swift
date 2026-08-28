import XCTest
@testable import WisprFlowAlt

final class TextNormalizerTests: XCTestCase {
    func testSpokenPunctuation() {
        let input = "hello comma world period"
        let output = TextNormalizer.normalize(input)
        XCTAssertEqual(output, "hello, world.")
    }

    func testDictionaryReplaceCaseInsensitive() {
        let entry = DictionaryReplacement(phrase: "wispr", replacement: "Wispr Flow", caseSensitive: false)
        let output = TextNormalizer.applyDictionary("I love wispr a lot", entries: [entry])
        XCTAssertEqual(output, "I love Wispr Flow a lot")
    }

    func testSnippetExpansion() {
        let snippet = SnippetReplacement(trigger: "my email", expansion: "me@example.com")
        let output = TextNormalizer.applySnippets("send to my email please", snippets: [snippet])
        XCTAssertEqual(output, "send to me@example.com please")
    }

    func testTransforms() {
        XCTAssertEqual(TextNormalizer.applyTransform("hello world", kind: .titleCase), "Hello World")
        XCTAssertEqual(TextNormalizer.applyTransform("Hello", kind: .upperCase), "HELLO")
        XCTAssertEqual(TextNormalizer.applyTransform("  x  ", kind: .trimWhitespace), "x")
    }

    func testWordCount() {
        XCTAssertEqual(TextNormalizer.wordCount("one two three"), 3)
    }
}

final class KeyShortcutTests: XCTestCase {
    func testConflictRequiresModifier() {
        let plain = KeyShortcut(keyCode: 0, modifiers: []) // A alone
        XCTAssertNotNil(plain.conflictsWithSystem())
    }

    func testOptionAloneAllowed() {
        let option = KeyShortcut(keyCode: 61, modifiers: [])
        XCTAssertNil(option.conflictsWithSystem())
    }

    func testFnAloneAllowed() {
        let fn = KeyShortcut(keyCode: 63, modifiers: [])
        XCTAssertNil(fn.conflictsWithSystem())
        XCTAssertEqual(fn.displayString, "Fn")
    }

    func testEncodeRoundTrip() {
        let original = KeyShortcut(keyCode: 8, modifiers: [.command, .control])
        let decoded = KeyShortcut.decode(original.encode())
        XCTAssertEqual(decoded, original)
    }
}
