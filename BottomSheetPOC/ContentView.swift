import SwiftUI

struct ContentView: View {
    @State private var isPresented = false
    @State private var selectedDetent: BottomSheetDetent? = .content
    @State private var blocks: [SheetBlock] = [
        SheetBlock(title: "Bloco 1", detail: "A sheet usa a altura deste conteúdo."),
        SheetBlock(title: "Bloco 2", detail: "Adicionar outro bloco faz a sheet crescer."),
    ]

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
            GrowingSheet(blocks: $blocks, selectedDetent: $selectedDetent)
        }
        .onAppear(perform: startAutoplayIfNeeded)
    }

    private func startAutoplayIfNeeded() {
        guard autoplay else { return }
        selectedDetent = .content
        isPresented = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            blocks.append(SheetBlock(title: "Bloco 3", detail: "Crescimento animado pelo detent de conteúdo."))
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            blocks.append(SheetBlock(title: "Bloco 4", detail: "A altura nova entra em invalidateDetents."))
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            blocks.append(SheetBlock(title: "Bloco 5", detail: "O fundo só escurece no detent large."))
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            selectedDetent = .large
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            selectedDetent = .content
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            blocks.removeLast()
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
}

private struct GrowingSheet: View {
    @Binding var blocks: [SheetBlock]
    @Binding var selectedDetent: BottomSheetDetent?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conteúdo dinâmico")
                .font(.title2.bold())
            Text("Cada bloco aumenta a altura medida. A sheet anima até essa altura.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

            HStack(spacing: 12) {
                Button("Adicionar") {
                    let number = blocks.count + 1
                    blocks.append(
                        SheetBlock(
                            title: "Bloco \(number)",
                            detail: "Novo conteúdo. A bottom sheet cresce com animação."
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("add-block")

                Button("Remover") {
                    guard blocks.count > 1 else { return }
                    blocks.removeLast()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("remove-block")
            }

            HStack(spacing: 12) {
                Button("Altura do conteúdo") {
                    selectedDetent = .content
                }
                .buttonStyle(.bordered)

                Button("Tela cheia") {
                    selectedDetent = .large
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
