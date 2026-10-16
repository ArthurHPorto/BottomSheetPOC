import SwiftUI
import UIKit

struct GrowingSheet: View {
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

            VStack(alignment: .leading, spacing: 0) {
                ForEach(blocks) { block in
                    GrowingBlock(
                        shown: block.shown,
                        startsCollapsed: block.startsCollapsed,
                        motion: motion,
                        onSettled: {
                            guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
                            blocks[index].startsCollapsed = false
                        }
                    ) {
                        blocks.removeAll { $0.id == block.id }
                    } content: {
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
                        .padding(.bottom, 16)
                    }
                }
            }
            .padding(.bottom, -16)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Em cima") { insertBlock(at: 0) }
                    Button("No meio") { insertBlock(at: max(visibleCount / 2, 0)) }
                    Button("Embaixo") { insertBlock(at: visibleCount) }
                }
                HStack(spacing: 8) {
                    Button("Tirar de cima") { removeBlock(at: 0) }
                    Button("Tirar do meio") { removeBlock(at: visibleCount / 2) }
                    Button("Tirar de baixo") { removeBlock(at: visibleCount - 1) }
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

    private var visibleCount: Int {
        blocks.filter(\.shown).count
    }

    private func insertBlock(at index: Int) {
        let visible = blocks.indices.filter { blocks[$0].shown }
        let clamped = min(max(index, 0), visible.count)
        let place = clamped == 0 ? "cima" : (clamped >= visible.count ? "baixo" : "meio")
        let block = SheetBlock(
            title: "Novo \(place)",
            detail: "Entrou pela \(place).",
            startsCollapsed: true
        )
        let realIndex = clamped < visible.count ? visible[clamped] : blocks.count
        BottomSheetMotion.perform(motion) {
            blocks.insert(block, at: realIndex)
        }
    }

    private func removeBlock(at index: Int) {
        let visible = blocks.indices.filter { blocks[$0].shown }
        guard visible.indices.contains(index) else { return }
        let realIndex = visible[index]
        BottomSheetMotion.perform(motion) {
            blocks[realIndex].shown = false
        }
    }
}

