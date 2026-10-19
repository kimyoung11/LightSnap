import AppKit
import Carbon

enum Layout: String, CaseIterable, Codable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    case firstThird, middleThird, lastThird, leftTwoThirds, rightTwoThirds
    case cell1, cell2, cell3, cell4, cell5, cell6, maximize, restore

    var title: String {
        switch self {
        case .left: return "왼쪽 절반"; case .right: return "오른쪽 절반"
        case .top: return "위쪽 절반"; case .bottom: return "아래쪽 절반"
        case .topLeft: return "왼쪽 위"; case .topRight: return "오른쪽 위"
        case .bottomLeft: return "왼쪽 아래"; case .bottomRight: return "오른쪽 아래"
        case .firstThird: return "왼쪽 ⅓"; case .middleThird: return "가운데 ⅓"; case .lastThird: return "오른쪽 ⅓"
        case .leftTwoThirds: return "왼쪽 ⅔"; case .rightTwoThirds: return "오른쪽 ⅔"
        case .cell1: return "6분할 · 위 1"; case .cell2: return "6분할 · 위 2"; case .cell3: return "6분할 · 위 3"
        case .cell4: return "6분할 · 아래 1"; case .cell5: return "6분할 · 아래 2"; case .cell6: return "6분할 · 아래 3"
        case .maximize: return "최대화"; case .restore: return "원래 크기로 복원"
        }
    }
    // Coordinates use Accessibility's top-left origin. Round shared edges, not widths.
    func frame(in area: CGRect) -> CGRect {
        let r: (CGFloat, CGFloat, CGFloat, CGFloat)
        switch self {
        case .left: r = (0,0,0.5,1); case .right: r = (0.5,0,1,1)
        case .top: r = (0,0,1,0.5); case .bottom: r = (0,0.5,1,1)
        case .topLeft: r = (0,0,0.5,0.5); case .topRight: r = (0.5,0,1,0.5)
        case .bottomLeft: r = (0,0.5,0.5,1); case .bottomRight: r = (0.5,0.5,1,1)
        case .firstThird: r = (0,0,1/3,1); case .middleThird: r = (1/3,0,2/3,1); case .lastThird: r = (2/3,0,1,1)
        case .leftTwoThirds: r = (0,0,2/3,1); case .rightTwoThirds: r = (1/3,0,1,1)
        case .cell1: r = (0,0,1/3,0.5); case .cell2: r = (1/3,0,2/3,0.5); case .cell3: r = (2/3,0,1,0.5)
        case .cell4: r = (0,0.5,1/3,1); case .cell5: r = (1/3,0.5,2/3,1); case .cell6: r = (2/3,0.5,1,1)
        case .maximize, .restore: r = (0,0,1,1)
        }
        let x1 = (area.minX + area.width * r.0).rounded(), x2 = (area.minX + area.width * r.2).rounded()
        let y1 = (area.minY + area.height * r.1).rounded(), y2 = (area.minY + area.height * r.3).rounded()
        return CGRect(x: x1, y: y1, width: x2-x1, height: y2-y1)
    }
    var defaultShortcut: Shortcut? {
        let code: Int
        switch self {
        case .left: code = kVK_LeftArrow; case .right: code = kVK_RightArrow
        case .top: code = kVK_UpArrow; case .bottom: code = kVK_DownArrow
        case .topLeft: code = kVK_ANSI_U; case .topRight: code = kVK_ANSI_I
        case .bottomLeft: code = kVK_ANSI_J; case .bottomRight: code = kVK_ANSI_K
        case .firstThird: code = kVK_ANSI_D; case .middleThird: code = kVK_ANSI_F; case .lastThird: code = kVK_ANSI_G
        case .leftTwoThirds: code = kVK_ANSI_E; case .rightTwoThirds: code = kVK_ANSI_T
        case .cell1: code = kVK_ANSI_1; case .cell2: code = kVK_ANSI_2; case .cell3: code = kVK_ANSI_3
        case .cell4: code = kVK_ANSI_4; case .cell5: code = kVK_ANSI_5; case .cell6: code = kVK_ANSI_6
        case .maximize: code = kVK_Return; case .restore: code = kVK_Delete
        }
        return Shortcut(keyCode: UInt32(code), modifiers: UInt32(cmdKey | optionKey))
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        let names: [UInt32: String] = [123:"←",124:"→",125:"↓",126:"↑",36:"↩",51:"⌫",48:"⇥",49:"Space",53:"Esc",117:"⌦",115:"Home",119:"End",116:"PgUp",121:"PgDn"]
        let letters: [UInt32:String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",50:"`",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"]
        return s + (names[keyCode] ?? letters[keyCode] ?? "Key \(keyCode)")
    }
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var m: UInt32 = 0
        if event.modifierFlags.contains(.command) { m |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { m |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { m |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { m |= UInt32(shiftKey) }
        modifiers = m
    }
}
