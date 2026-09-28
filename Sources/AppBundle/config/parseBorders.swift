import Common

struct BordersConfig: ConvenienceMutable, Equatable, Sendable {
    var enabled: Bool = false
    /// "auto" follows the system accent color; otherwise an NSColor name.
    var color: String = "auto"
    /// Ring thickness in points, clamped to 1...16 at render time.
    var width: Int = 4
}

private let bordersParser: [String: any ParserProtocol<BordersConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "color": Parser(\.color, parseString),
    "width": Parser(\.width, parseInt),
]

func parseBorders(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> BordersConfig {
    parseTable(raw, BordersConfig(), bordersParser, backtrace, &c)
}
