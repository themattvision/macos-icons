//
//  Item.swift
//  MacOS Icons
//
//  Created by Matteo Zampieri on 14/09/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
