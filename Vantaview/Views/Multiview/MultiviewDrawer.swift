import SwiftUI

struct MultiviewDrawer: View {
    @ObservedObject var viewModel: MultiviewViewModel
    @ObservedObject var productionManager: UnifiedProductionManager
    
    @State private var isDragging = false
    private let minHeight: CGFloat = 120
    private let maxHeight: CGFloat = 360
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Multiview", systemImage: "rectangle.grid.3x2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    viewModel.popOut()
                } label: {
                    Label("Pop Out", systemImage: "rectangle.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(LiquidGlassButton(accentColor: TahoeDesign.Colors.virtual, size: .small))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            grid
                .frame(height: viewModel.drawerHeight - 24)
                .clipped()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.md, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
                .overlay(keyCatcher)
            
            dragHandle
        }
        .padding(.horizontal, TahoeDesign.Spacing.sm)
        .padding(.bottom, TahoeDesign.Spacing.sm)
        .liquidGlassPanel(material: .thinMaterial, cornerRadius: TahoeDesign.CornerRadius.lg, shadowIntensity: .light)
        .task(id: viewModel.isOpen) {
            await viewModel.setOpen(viewModel.isOpen)
        }
        .animation(TahoeAnimations.panelSlide, value: viewModel.drawerHeight)
    }
    
    private var grid: some View {
        GeometryReader { geo in
            ScrollView {
                let cols = Int(max(1, floor(geo.size.width / 200)))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
                    ForEach(viewModel.tiles) { tile in
                        let singleTap = TapGesture(count: 1).onEnded {
                            Task { await viewModel.click(tile) }
                        }
                        let doubleTap = TapGesture(count: 2).onEnded {
                            Task { await viewModel.doubleClick(tile) }
                        }
                        
                        Group {
                            if let feed = viewModel.feed(for: tile) {
                                MultiviewTileLive(
                                    tile: tile,
                                    feed: feed,
                                    isProgram: viewModel.isProgram(tile),
                                    isPreview: viewModel.isPreview(tile)
                                )
                            } else {
                                MultiviewTile(
                                    tile: tile,
                                    image: viewModel.imageForTile(tile),
                                    isProgram: viewModel.isProgram(tile),
                                    isPreview: viewModel.isPreview(tile)
                                )
                            }
                        }
                        .highPriorityGesture(doubleTap)
                        .simultaneousGesture(singleTap)
                        .simultaneousGesture(
                            TapGesture().modifiers(.option).onEnded {
                                Task { await viewModel.optionClick(tile) }
                            }
                        )
                    }
                }
                .padding(8)
            }
        }
    }
    
    private var dragHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 60, height: 4)
            )
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDragging = true
                        let newHeight = viewModel.drawerHeight + (-value.translation.height)
                        viewModel.drawerHeight = min(max(newHeight, minHeight), maxHeight)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
    
    private var keyCatcher: some View {
        LocalKeyEventMonitor { event in
            guard viewModel.isOpen else { return }
            if let chars = event.charactersIgnoringModifiers, let first = chars.first {
                switch first {
                case "1"..."9":
                    if let digit = Int(String(first)) {
                        Task { await viewModel.hotkeySelect(index: digit) }
                    }
                case "\r":
                    Task { await viewModel.take() }
                case "d", "D":
                    Task { await viewModel.dissolve() }
                default:
                    break
                }
            }
        }
        .allowsHitTesting(false)
    }
}