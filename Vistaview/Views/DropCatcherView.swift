// DropCatcherView.swift
import SwiftUI
import UniformTypeIdentifiers

struct DropCatcherView: NSViewRepresentable {
    var onDrop: (URL) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = InternalDropView()
        view.onDrop = onDrop
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class InternalDropView: NSView {
        var onDrop: ((URL) -> Void)?

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            .copy
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            true
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let pasteboard = sender.draggingPasteboard
            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  let first = urls.first,
                  UTType(filenameExtension: first.pathExtension)?.conforms(to: .movie) == true else {
                return false
            }

            onDrop?(first)
            return true
        }
    }
}
