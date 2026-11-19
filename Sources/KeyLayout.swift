import CoreGraphics

/// Physical key layout used for the grid. Keys are identified by *virtual key code*,
/// which is tied to the physical position on the keyboard (ANSI layout), not the
/// character it types — so the grid matches where your fingers are, even on
/// Dvorak/Colemak/etc.
enum KeyLayout {
    struct Key {
        let code: CGKeyCode
        let label: String
    }

    static let rows: [[Key]] = [
        [Key(code: 18, label: "1"), Key(code: 19, label: "2"), Key(code: 20, label: "3"),
         Key(code: 21, label: "4"), Key(code: 23, label: "5"), Key(code: 22, label: "6"),
         Key(code: 26, label: "7"), Key(code: 28, label: "8"), Key(code: 25, label: "9"),
         Key(code: 29, label: "0")],
        [Key(code: 12, label: "Q"), Key(code: 13, label: "W"), Key(code: 14, label: "E"),
         Key(code: 15, label: "R"), Key(code: 17, label: "T"), Key(code: 16, label: "Y"),
         Key(code: 32, label: "U"), Key(code: 34, label: "I"), Key(code: 31, label: "O"),
         Key(code: 35, label: "P")],
        [Key(code: 0, label: "A"), Key(code: 1, label: "S"), Key(code: 2, label: "D"),
         Key(code: 3, label: "F"), Key(code: 5, label: "G"), Key(code: 4, label: "H"),
         Key(code: 38, label: "J"), Key(code: 40, label: "K"), Key(code: 37, label: "L"),
         Key(code: 41, label: ";")],
        [Key(code: 6, label: "Z"), Key(code: 7, label: "X"), Key(code: 8, label: "C"),
         Key(code: 9, label: "V"), Key(code: 11, label: "B"), Key(code: 45, label: "N"),
         Key(code: 46, label: "M"), Key(code: 43, label: ","), Key(code: 47, label: "."),
         Key(code: 44, label: "/")],
    ]

    static let rowCount = rows.count
    static let columnCount = rows[0].count
    static let homeRow = 2

    private static let positions: [CGKeyCode: (row: Int, col: Int)] = {
        var map: [CGKeyCode: (row: Int, col: Int)] = [:]
        for (r, row) in rows.enumerated() {
            for (c, key) in row.enumerated() { map[key.code] = (r, c) }
        }
        return map
    }()

    static func position(of code: CGKeyCode) -> (row: Int, col: Int)? { positions[code] }

    // Special keys
    static let escape: CGKeyCode = 53
    static let delete: CGKeyCode = 51
    static let space: CGKeyCode = 49
    static let returnKey: CGKeyCode = 36
    static let tab: CGKeyCode = 48
    static let leftCommand: CGKeyCode = 55
    static let rightCommand: CGKeyCode = 54
    static let leftControl: CGKeyCode = 59
    static let rightControl: CGKeyCode = 62
    static let leftShift: CGKeyCode = 56
    static let rightShift: CGKeyCode = 60
    static let leftOption: CGKeyCode = 58
    static let rightOption: CGKeyCode = 61

    /// Arrow keys → direction (an arrow then a key picks that half of its cell).
    static let arrows: [CGKeyCode: Grid.Direction] = [
        126: .up, 125: .down, 123: .left, 124: .right,
    ]
}
