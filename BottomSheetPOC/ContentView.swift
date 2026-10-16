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

/// Grows and fades a block in layout, so the next rows are pushed instead of covered.
///
/// The height is stepped on the display link. SwiftUI's own insertion animation was
/// being cancelled by the sheet update, and it also drew the new card on top of the
/// rows that had not moved yet.
private struct GrowingBlock<Content: View>: View {
    var shown: Bool
    var startsCollapsed: Bool
    var motion: BottomSheetMotion
    /// Lets the owner drop `startsCollapsed`, so a reopened sheet does not replay the entrance.
    var onSettled: () -> Void
    var onCollapsed: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var natural: CGFloat = 0
    @State private var displayed: CGFloat
    @State private var didStartIntro = false
    @State private var collapsing = false
    @State private var didReportCollapse = false
    @State private var driver = BlockMotionDriver()

    init(
        shown: Bool,
        startsCollapsed: Bool,
        motion: BottomSheetMotion,
        onSettled: @escaping () -> Void,
        onCollapsed: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.shown = shown
        self.startsCollapsed = startsCollapsed
        self.motion = motion
        self.onSettled = onSettled
        self.onCollapsed = onCollapsed
        self.content = content
        _displayed = State(initialValue: 0)
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: layoutHeight, alignment: .top)
            .clipped()
            .opacity(reveal)
            .background {
                BlockHeightMeasurer(content: AnyView(content()), onHeight: noteHeight)
            }
            .onChange(of: shown, perform: noteShown)
    }

    /// `nil` keeps the first layout of a block that is already visible.
    private var layoutHeight: CGFloat? {
        if !startsCollapsed, displayed <= 1, natural <= 1 {
            return nil
        }
        return max(displayed, 0)
    }

    private var reveal: Double {
        guard natural > 1 else { return displayed > 1 ? 1 : 0 }
        return min(max(Double(displayed / natural), 0), 1)
    }

    private func noteHeight(_ value: CGFloat) {
        guard value > 1 else { return }
        let changed = abs(value - natural) > 0.5
        natural = value
        guard !collapsing else { return }
        if startsCollapsed, !didStartIntro {
            didStartIntro = true
            start(from: 0, to: value, removing: false)
            return
        }
        guard changed || abs(displayed - value) > 0.5 else { return }
        if driver.isRunning {
            start(from: displayed, to: value, removing: false)
        } else {
            displayed = value
        }
    }

    private func noteShown(_ isShown: Bool) {
        if isShown {
            collapsing = false
            didReportCollapse = false
            start(from: displayed, to: max(natural, displayed), removing: false)
        } else {
            collapsing = true
            start(from: displayed, to: 0, removing: true)
        }
    }

    private func start(from: CGFloat, to: CGFloat, removing: Bool) {
        driver.onChange = { value in
            displayed = value
        }
        driver.onFinish = {
            if removing {
                reportCollapsed()
            } else if startsCollapsed {
                onSettled()
            }
        }
        driver.start(from: from, to: to, motion: motion)
    }

    private func reportCollapsed() {
        guard !didReportCollapse else { return }
        didReportCollapse = true
        onCollapsed()
    }
}

/// Plays `BottomSheetMotion` by writing progress every frame, so the sheet can follow it.
private final class BlockMotionDriver {
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var from: CGFloat = 0
    private var to: CGFloat = 1
    private var motion: BottomSheetMotion = .spring
    var onChange: ((CGFloat) -> Void)?
    var onFinish: (() -> Void)?
    var isRunning: Bool { link != nil }

    func start(from: CGFloat, to: CGFloat, motion: BottomSheetMotion) {
        self.from = from
        self.to = to
        self.motion = motion
        startTime = CACurrentMediaTime()
        link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step() {
        let elapsed = CACurrentMediaTime() - startTime
        let unit = motion.unitProgress(elapsed: elapsed)
        onChange?(from + (to - from) * unit)
        guard elapsed >= motion.settlesAfter else { return }
        onChange?(to)
        link?.invalidate()
        link = nil
        let finish = onFinish
        onChange = nil
        onFinish = nil
        finish?()
    }

    deinit {
        link?.invalidate()
    }
}

/// Measures the block without adding that height to the sheet.
private struct BlockHeightMeasurer: UIViewRepresentable {
    var content: AnyView
    var onHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MeasureHost {
        let host = MeasureHost()
        host.onHeight = onHeight
        host.setContent(content)
        return host
    }

    func updateUIView(_ uiView: MeasureHost, context: Context) {
        uiView.onHeight = onHeight
        uiView.setContent(content)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MeasureHost, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: 0)
    }

    final class Coordinator {}
}

private final class MeasureHost: UIView {
    let hostingController = UIHostingController(rootView: AnyView(EmptyView()))
    var onHeight: (CGFloat) -> Void = { _ in }
    private var lastHeight: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        isAccessibilityElement = false
        hostingController.view.backgroundColor = .clear
        hostingController.view.isUserInteractionEnabled = false
        hostingController.view.alpha = 0
        addSubview(hostingController.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 0)
    }

    func setContent(_ content: AnyView) {
        hostingController.rootView = content
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 1 else { return }
        let height = hostingController.sizeThatFits(in: CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)).height
        guard height > 1, abs(height - lastHeight) > 0.5 else { return }
        lastHeight = height
        hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let report = onHeight
        DispatchQueue.main.async {
            report(height)
        }
    }
}

struct SheetBlock: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var detail: String
    var startsCollapsed: Bool = false
    var shown: Bool = true
}

#Preview {
    ContentView()
}
