import Foundation
import SwiftData

@Model final class CanvasPhoto {
    var imageData: Data
    var x: Double           // center X in canvas view coordinates
    var y: Double           // center Y in canvas view coordinates
    var width: Double
    var height: Double
    var rotationDegrees: Double
    var page: Page?

    init(imageData: Data, x: Double, y: Double, width: Double, height: Double) {
        self.imageData       = imageData
        self.x               = x
        self.y               = y
        self.width           = width
        self.height          = height
        self.rotationDegrees = 0
    }
}
