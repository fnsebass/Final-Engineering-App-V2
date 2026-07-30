//
//  Item.swift
//  engineering app 1
//
//  Created by Sebastián buso on 7/30/26.
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
