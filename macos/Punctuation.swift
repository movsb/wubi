struct ChinesePunctuation {
    private var doubleQuoteOpening = true
    private var singleQuoteOpening = true

    private static let symbols: [String: String] = [
        ",": "，", ".": "。", "?": "？", "!": "！",
        ":": "：", ";": "；", "\\": "、",
        "(": "（", ")": "）", "[": "【", "]": "】",
        "<": "《", ">": "》", "^": "……", "_": "——",
        "$": "￥", "~": "～", "`": "·",
    ]

    mutating func convert(_ text: String) -> String? {
        switch text {
        case "\"":
            defer { doubleQuoteOpening.toggle() }
            return doubleQuoteOpening ? "“" : "”"
        case "'":
            defer { singleQuoteOpening.toggle() }
            return singleQuoteOpening ? "‘" : "’"
        default:
            return Self.symbols[text]
        }
    }

    mutating func reset() { self = Self() }
}
