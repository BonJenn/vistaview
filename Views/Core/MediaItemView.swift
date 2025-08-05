// ... existing code ...
     @ObservedObject var thumbnailManager: MediaThumbnailManager
     let onMediaSelected: (MediaFile) -> Void
     let onMediaDropped: (MediaFile, CGPoint) -> Void
     
-    @State private var thumbnail: NSImage?
-    @State private var wasClicked = false
+    @State private var thumbnail: NSImage?
     
     var body: some View {
-        Button(action: {
-            wasClicked = true
-            print("🔥🔥🔥 MEDIAITEMVIEW: Button clicked for \(mediaFile.name)")
-            onMediaSelected(mediaFile)
-            print("🔥🔥🔥 MEDIAITEMVIEW: Called onMediaSelected")
-        }) {
+        Button(action: {
+            onMediaSelected(mediaFile)
+        }) {
             VStack(spacing: 4) {
                 // Thumbnail or icon
                 ZStack {
// ... existing code ...
                             .resizable()
                             .aspectRatio(contentMode: .fill)
                     } else {
                         Rectangle()
-                            .fill(wasClicked ? Color.green.opacity(0.5) : Color.gray.opacity(0.3))
+                            .fill(Color.gray.opacity(0.3))
                             .overlay(
                                 Image(systemName: mediaFile.fileType.icon)
                                     .font(.title2)
// ... existing code ...
                 .cornerRadius(4)
                 
                 // File name
-                Text(wasClicked ? "🔥 CLICKED!" : mediaFile.name)
+                Text(mediaFile.name)
                     .font(.caption2)
-                    .foregroundColor(wasClicked ? .red : .primary)
-                    .fontWeight(wasClicked ? .bold : .regular)
+                    .foregroundColor(.primary)
                     .lineLimit(2)
                     .multilineTextAlignment(.center)
                     .frame(height: 30)
// ... existing code ...
         }
         .buttonStyle(PlainButtonStyle())
         .frame(width: 100, height: 100)
-        .background(wasClicked ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
+        .background(Color.gray.opacity(0.1))
         .cornerRadius(8)
         .overlay(
             RoundedRectangle(cornerRadius: 8)
-                .strokeBorder(wasClicked ? Color.red : Color.blue.opacity(0.2), lineWidth: wasClicked ? 3 : 1)
+                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
         )
         .onAppear {
             Task {
                 thumbnail = await thumbnailManager.getThumbnail(for: mediaFile)
             }
         }
-        .onTapGesture {
-            onMediaSelected(mediaFile)
-        }
-        .draggable(mediaFile) {
-            // Drag preview
-            VStack(spacing: 4) {
-                if let thumbnail = thumbnail {
-                    Image(nsImage: thumbnail)
-                        .resizable()
-                        .aspectRatio(contentMode: .fill)
-                        .frame(width: 60, height: 34)
-                        .clipped()
-                        .cornerRadius(4)
-                } else {
-                    Rectangle()
-                        .fill(Color.gray.opacity(0.3))
-                        .frame(width: 60, height: 34)
-                        .cornerRadius(4)
-                        .overlay(
-                            Image(systemName: mediaFile.fileType.icon)
-                                .font(.body)
-                                .foregroundColor(.secondary)
-                        )
-                }
-                
-                Text(mediaFile.name)
-                    .font(.caption2)
-                    .foregroundColor(.white)
-                    .lineLimit(1)
-            }
-            .padding(8)
-            .background(Color.black.opacity(0.8))
-            .cornerRadius(8)
-        }
-    }
-}
-
-// MARK: - MediaFile Conformance to Transferable
-
-extension MediaFile: Transferable {
-    static var transferRepresentation: some TransferRepresentation {
-        CodableRepresentation(for: MediaFile.self, contentType: .data)
     }
 }
+
+extension MediaFile: Transferable {
+    static var transferRepresentation: some TransferRepresentation {
+        CodableRepresentation(for: MediaFile.self, contentType: .data)
+    }
+}