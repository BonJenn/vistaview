import SwiftUI
import UniformTypeIdentifiers

struct DropCatcherView: View {
    @Binding var droppedFiles: [URL]

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers -> Bool in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                        DispatchQueue.main.async {
                            if let data = item as? Data,
                               let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? {
                                droppedFiles.append(url)
                            }
                        }
                    }
                }
                return true
            }
    }
}

