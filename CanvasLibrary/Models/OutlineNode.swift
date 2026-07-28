//
//  OutlineNode.swift
//  Canvas Library
//

import Foundation

struct OutlineNode: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: Kind
    let line: Int
    let column: Int
    var children: [OutlineNode]

    enum Kind: String, Hashable {
        case component   // PascalCase / known component
        case element     // lowercase HTML-like tag
        case fragment    // <> or <React.Fragment>
        case selfClosing

        var symbol: String {
            switch self {
            case .component: return "cube"
            case .element: return "chevron.left.forwardslash.chevron.right"
            case .fragment: return "rectangle.on.rectangle"
            case .selfClosing: return "arrow.down.left.and.arrow.up.right"
            }
        }
    }

    var lineLabel: String { "L\(line)" }
}
