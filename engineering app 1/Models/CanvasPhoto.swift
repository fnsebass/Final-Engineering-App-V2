import Foundation
import SwiftData

@Model final class CanvasPhoto {
    var imageData: Data = Data()
    var x: Double = 0           // center X in canvas view coordinates
    var y: Double = 0           // center Y in canvas view coordinates
    var width: Double = 0
    var height: Double = 0
    var rotationDegrees: Double = 0
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
