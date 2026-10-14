import SwiftUI

struct ContentView: View {
    @State private var isPresented = false
    @State private var selectedDetent: BottomSheetDetent? = .content
    @State private var blocks: [SheetBlock] = [
        SheetBlock(title: "Bloco 1", detail: "A sheet usa a altura deste conteúdo."),
        SheetBlock(title: "Bloco 2", detail: "Adicionar outro bloco faz a sheet crescer."),
    ]
    @State private var motion = BottomSheetMotion.resolvedFromLaunchArguments()

    private let autoplay = ProcessInfo.processInfo.arguments.contains("-BottomSheetAutoplay")

    private var configuration: BottomSheetConfiguration {
        var configuration = BottomSheetConfiguration()
        configuration.detents = [.content, .large]
        configuration.largestUndimmedDetent = .content
        configuration.prefersGrabberVisible = true
        configuration.preferredCornerRadius = 28
        configuration.prefersScrollingExpandsWhenScrolledToEdge = true
        return configuration
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Bottom sheet")
                    .font(.largeTitle.bold())
                Text("UISheetPresentationController no iOS 16+")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(detentTitle(selectedDetent))
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())

            Button("Mostrar bottom sheet") {
                selectedDetent = .content
                isPresented = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("show-sheet")

            Text("Com a sheet na altura do conteúdo, o fundo continua tocável.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .bottomSheet(
            isPresented: $isPresented,
            selectedDetent: $selectedDetent,
            configuration: configuration
        ) {
            GrowingSheet(blocks: $blocks, selectedDetent: $selectedDetent, motion: $motion)
        }
        .onAppear(perform: startAutoplayIfNeeded)
    }

    private func startAutoplayIfNeeded() {
        BottomSheetMotion.active = motion
        guard autoplay else { return }
        selectedDetent = .content
        isPresented = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            insert("Fundo", at: blocks.count)
            try? await Task.sleep(nanoseconds: 900_000_000)
            insert("Topo", at: 0)
            try? await Task.sleep(nanoseconds: 900_000_000)
            insert("Meio", at: blocks.count / 2)
            try? await Task.sleep(nanoseconds: 900_000_000)
            remove(at: 0)
            try? await Task.sleep(nanoseconds: 900_000_000)
            remove(at: blocks.count - 1)
            try? await Task.sleep(nanoseconds: 900_000_000)
            remove(at: blocks.count / 2)
        }
    }

    private func detentTitle(_ detent: BottomSheetDetent?) -> String {
        switch detent {
        case .content:
            return "Detent: conteúdo"
        case .medium:
            return "Detent: médio"
        case .large:
            return "Detent: grande"
        case .fraction(let value):
            return "Detent: \(Int(value * 100))%"
        case .height(let value):
            return "Detent: \(Int(value)) pt"
        case nil:
            return "Detent: automático"
        }
    }

    private func insert(_ name: String, at index: Int) {
        let block = SheetBlock(title: name, detail: "Inserido em \(name.lowercased()).")
        let clamped = min(max(index, 0), blocks.count)
        BottomSheetMotion.perform(motion) {
            blocks.insert(block, at: clamped)
        }
    }

    private func remove(at index: Int) {
        guard blocks.indices.contains(index) else { return }
        BottomSheetMotion.perform(motion) {
            blocks.remove(at: index)
        }
    }
}

private struct GrowingSheet: View {
    @Binding var blocks: [SheetBlock]
    @Binding var selectedDetent: BottomSheetDetent?
    @Binding var motion: BottomSheetMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conteúdo dinâmico")
                .font(.title2.bold())
            Text("Cada bloco aumenta a altura medida. A sheet usa a mesma curva do conteúdo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BottomSheetMotion.allCases) { item in
                        Button(item.title) {
                            motion = item
                            BottomSheetMotion.active = item
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(item == motion ? Color.accentColor : Color.secondary)
                        .accessibilityIdentifier("motion-\(item.rawValue)")
                    }
                }
            }
            .modifier(HiddenScrollEdgeEffect())

            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: 6) {
                    Text(block.title)
                        .font(.headline)
                    Text(block.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Em cima") { insertBlock(at: 0) }
                    Button("No meio") { insertBlock(at: max(blocks.count / 2, 0)) }
                    Button("Embaixo") { insertBlock(at: blocks.count) }
                }
                HStack(spacing: 8) {
                    Button("Tirar de cima") { removeBlock(at: 0) }
                    Button("Tirar do meio") { removeBlock(at: blocks.count / 2) }
                    Button("Tirar de baixo") { removeBlock(at: blocks.count - 1) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 12) {
                Button("Altura do conteúdo") {
                    selectedDetent = .content
                }
                Button("Tela cheia") {
                    selectedDetent = .large
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insertBlock(at index: Int) {
        let place = index == 0 ? "cima" : (index >= blocks.count ? "baixo" : "meio")
        let block = SheetBlock(title: "Novo \(place)", detail: "Entrou pela \(place).")
        let clamped = min(max(index, 0), blocks.count)
        BottomSheetMotion.perform(motion) {
            blocks.insert(block, at: clamped)
        }
    }

    private func removeBlock(at index: Int) {
        guard blocks.indices.contains(index) else { return }
        BottomSheetMotion.perform(motion) {
            blocks.remove(at: index)
        }
    }
}

/// The horizontal scroller otherwise draws the iOS 26 glass edge over the rows below it.
private struct HiddenScrollEdgeEffect: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true)
        } else {
            content
        }
    }
}

struct SheetBlock: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var detail: String
}

#Preview {
    ContentView()
}
