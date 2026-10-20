//
//  Item.swift
//  Selno
//
//  Created by Waiting on 2026/10/20.
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
