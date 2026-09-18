//
//  NotepadCard.swift
//  Tolerance
//
//  The note-card thumbnail used by Home's grid and the Library/Chapter
//  browsing screens, so both share identical card UI. `NewNoteCard` is the
//  dashed "+" placeholder card shown alongside real notes to create one.
//  The thumbnail renders the note's actual first-page drawing rather than a
//  generic icon, falling back to the icon only for blank notes.
//

import SwiftUI
import SwiftData
#if os(iOS)
import PencilKit
#endif

struct NotepadCard: View {
    let notepad: Notepad
    let showDate: Bool

    /// The note has no color of its own, so its paper color stands in as
    /// the card's accent — a reasonable proxy for "subject" identity.
    private var accent: Color { PaperTheme.color(fromHex: notepad.paperColorHex) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NotepadThumbnail(notepad: notepad)

            // Bottom scrim guarantees the caption reads regardless of how
            // light the note's own paper color is.
            LinearGradient(
                colors: [.clear, .black.opacity(0.62)],
                startPoint: .center, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(notepad.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(notepad.pages.count) pg")
                    if showDate {
                        Text("·")
                        Text(notepad.lastEditedDate, format: .relative(presentation: .named))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
            }
            .padding(10)

            if let bookName = notepad.folder?.name {
                tagChip(bookName)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .aspectRatio(bookAspectRatio, contentMode: .fit)
        .cardChrome(accent: accent, cornerRadius: 12)
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
    }
}

struct NewNoteCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .foregroundStyle(.tertiary)
            .aspectRatio(bookAspectRatio, contentMode: .fit)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                    Text("New Note")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Thumbnail rendering

/// Renders the note's first page as a small raster thumbnail, matching the
/// paper color and falling back to a generic icon for blank notes or when
/// decoding fails.
struct NotepadThumbnail: View {
    let notepad: Notepad
    @State private var image: Image? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(paperColor)
            .overlay {
                if let image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "function")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .task(id: notepad.persistentModelID) {
                image = await Self.renderThumbnail(for: notepad)
            }
    }

    private var paperColor: Color { PaperTheme.color(fromHex: notepad.paperColorHex) }

    #if os(iOS)
    private static func renderThumbnail(for notepad: Notepad) async -> Image? {
        guard let page = notepad.orderedPages.first, !page.drawingData.isEmpty,
              let drawing = try? PKDrawing(data: page.drawingData),
              !drawing.bounds.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -12, dy: -12)

        // PencilCanvasView always draws with the canvas forced to
        // `.light` (see its top-of-file comment), and every ink color it
        // hands PencilKit is a fixed, non-adaptive UIColor resolved under
        // that same light trait collection. PKDrawing's own dark/light-aware
        // draw(in:...:darkUserInterfaceStyle:) still special-cases literal
        // black/white ink and will flip it (e.g. white → black) whenever the
        // flag doesn't match the interface style the stroke was created
        // under. Rendering here must therefore always pass `false` — the
        // paper's own color has nothing to do with that flag — so a stroke
        // renders in the exact color the user picked, whatever it is.
        //
        // The legacy UIGraphicsBeginImageContext/EndImageContext globals are
        // avoided here on purpose: they push/pop a *shared* context stack,
        // which isn't safe to hold across the `await` below (another task
        // could touch that same global stack while this one is suspended).
        // A CGContext we own directly has no such risk.
        let width  = max(1, Int(bounds.width.rounded(.up)))
        let height = max(1, Int(bounds.height.rounded(.up)))
        guard let cgContext = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // PencilKit's draw(in:...) expects a UIKit-style (top-left origin,
        // y-down) context, but a manually created CGContext defaults to the
        // Core Graphics convention (bottom-left origin, y-up) — flip it.
        cgContext.translateBy(x: 0, y: CGFloat(height))
        cgContext.scaleBy(x: 1, y: -1)

        await drawing.draw(in: cgContext,
                            frame: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                            from: bounds, darkUserInterfaceStyle: false)

        guard let cgImage = cgContext.makeImage() else { return nil }
        return Image(uiImage: UIImage(cgImage: cgImage))
    }
    #else
    private static func renderThumbnail(for notepad: Notepad) async -> Image? { nil }
    #endif
}
