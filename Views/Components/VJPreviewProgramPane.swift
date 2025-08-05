// ... existing code ...
         case .color(let color, let name):
             Color(nsColor: color).overlay(Text(name))
         case .media(_, let player):
             FrameBasedVideoPlayerView(player: player)
         case .virtual(let camera):
             // Placeholder for virtual camera preview
             VStack {
// ... existing code ...