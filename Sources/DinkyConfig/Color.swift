/// A colour from config, written `'#rrggbb'` or `'#rrggbbaa'`. Components are 0...1.
public struct Color: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(hex: String) throws(ConfigError) {
        let digits = hex.dropFirst()
        guard hex.hasPrefix("#"), digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
              var value = UInt32(digits, radix: 16) else {
            throw ConfigError("'\(hex)' is not a colour, expected '#rrggbb' or '#rrggbbaa'")
        }
        if digits.count == 6 { value = value << 8 | 0xFF }
        func component(_ shift: UInt32) -> Double { Double(value >> shift & 0xFF) / 255 }
        self.init(red: component(24), green: component(16), blue: component(8), alpha: component(0))
    }
}
