import SwiftUI
import UIKit

struct ContentView: View {
    @State private var isPresented = false
    @State private var selectedDetent: BottomSheetDetent? = .content
    @State private var blocks: [SheetBlock] = [
        SheetBlock(title: "Bloco 1", detail: "A sheet usa a altura deste conteúdo."),
        SheetBlock(title: "Bloco 2", detail: "Adicionar outro bloco faz a sheet crescer."),
    ]
    @State private var motion = BottomSheetMotion.resolvedFromLaunchArguments()

    private let autoplay = ProcessInfo.processInfo.arguments.contains("-BottomSheetAutoplay")
    private let burst = ProcessInfo.processInfo.arguments.contains("-BottomSheetBurst")
    private let stress = ProcessInfo.processInfo.arguments.contains("-BottomSheetStress")
    private let step = ProcessInfo.processInfo.arguments.contains("-BottomSheetStep")
    private let detentTour = ProcessInfo.processInfo.arguments.contains("-BottomSheetDetents")

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
            selectedDetent: $selectedDetent
        ) {
            GrowingSheet(blocks: $blocks, selectedDetent: $selectedDetent, motion: $motion)
        }
        .onAppear(perform: startAutoplayIfNeeded)
    }

    private func startAutoplayIfNeeded() {
        BottomSheetMotion.active = motion
        guard autoplay || burst || stress || step || detentTour else { return }
        selectedDetent = .content
        isPresented = true
        if detentTour {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                selectedDetent = .large
                try? await Task.sleep(nanoseconds: 900_000_000)
                insert("Em tela cheia", at: visibleBlocks.count)
                try? await Task.sleep(nanoseconds: 900_000_000)
                selectedDetent = .content
                try? await Task.sleep(nanoseconds: 900_000_000)
                insert("De volta", at: 0)
                try? await Task.sleep(nanoseconds: 900_000_000)
                isPresented = false
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                selectedDetent = .content
                isPresented = true
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                remove(at: 0)
                try? await Task.sleep(nanoseconds: 900_000_000)
                insert("Reaberta", at: visibleBlocks.count / 2)
            }
            return
        }
        if step {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                blocks.append(SheetBlock(title: "Salto", detail: "Entrou sem animação."))
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                blocks.removeLast()
            }
            return
        }
        if stress {
            startStress()
            return
        }
        if burst {
            startBurst()
            return
        }
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
            remove(at: visibleBlocks.count - 1)
            try? await Task.sleep(nanoseconds: 900_000_000)
            remove(at: visibleBlocks.count / 2)
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

    private func startBurst() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            for index in 0..<4 {
                insert("Rápido \(index)", at: blocks.count)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            for _ in 0..<3 {
                insert("Topo", at: 0)
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            while visibleBlocks.count > 2 {
                remove(at: 0)
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
        }
    }

    private func startStress() {
        Task { @MainActor in
            var seed: UInt64 = 0x5EED
            func next(_ bound: Int) -> Int {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Int((seed >> 33) % UInt64(max(bound, 1)))
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            for step in 0..<40 {
                let count = visibleBlocks.count
                let grow = count < 2 || (count < 7 && next(10) < 6)
                let position = next(3)
                let index = position == 0 ? 0 : (position == 1 ? count / 2 : count)
                if grow {
                    insert("Estresse \(step)", at: index)
                } else {
                    remove(at: min(index, count - 1))
                }
                let delays: [UInt64] = [16, 40, 80, 120, 200, 350]
                try? await Task.sleep(nanoseconds: delays[next(delays.count)] * 1_000_000)
            }
        }
    }

    private var visibleBlocks: [SheetBlock] {
        blocks.filter(\.shown)
    }

    private func insert(_ name: String, at index: Int) {
        let block = SheetBlock(
            title: name,
            detail: "Inserido em \(name.lowercased()).",
            startsCollapsed: true
        )
        let visible = blocks.indices.filter { blocks[$0].shown }
        let clamped = min(max(index, 0), visible.count)
        let realIndex = clamped < visible.count ? visible[clamped] : blocks.count
        BottomSheetMotion.perform(motion) {
            blocks.insert(block, at: realIndex)
        }
    }

    private func remove(at index: Int) {
        let visible = blocks.indices.filter { blocks[$0].shown }
        guard visible.indices.contains(index) else { return }
        let realIndex = visible[index]
        BottomSheetMotion.perform(motion) {
            blocks[realIndex].shown = false
        }
    }
}

#Preview {
    ContentView()
}
