import Foundation
import Testing
@testable import Where

struct SearchNormalizerTests {
    @Test(arguments: [
        ("  Cable  ", "cable"),
        ("MiXeD CaSe", "mixed case"),
        ("cafe\u{301}", "café"),
        ("  Ｃａｂｌｅ  ", "cable"),
        (" 旅行 ", "旅行"),
        (" \n\t ", ""),
    ])
    func normalizesSearchText(input: String, expected: String) {
        #expect(SearchNormalizer.normalize(input) == expected)
    }
}
