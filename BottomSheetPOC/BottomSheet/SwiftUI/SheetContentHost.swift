import Combine
import SwiftUI

final class HeightRelay: ObservableObject {
    var onChange: (CGFloat) -> Void = { _ in }
    @Published var grabberInset: CGFloat = 0
    @Published var bottomInset: CGFloat = 0
}

struct BottomSheetHeightProbe<Content: View>: View {
    var grabberInset: CGFloat
    var bottomInset: CGFloat
    var content: Content

    var body: some View {
        content
            .padding(.top, grabberInset)
            .padding(.bottom, bottomInset)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct BottomSheetRoot<Content: View>: View {
    var content: Content
    @ObservedObject var relay: HeightRelay

    var body: some View {
        ScrollView {
            content
                .padding(.top, relay.grabberInset)
                .padding(.bottom, relay.bottomInset)
                .fixedSize(horizontal: false, vertical: true)
                .background(heightReader)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// `onPreferenceChange` stops delivering once the sheet resizes inside its callback
    /// (the sheet stalled at a stale height while rows kept growing). `onChange` on the
    /// reader's own size keeps firing every frame.
    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    relay.onChange(proxy.size.height)
                }
                .onChange(of: proxy.size.height) { value in
                    relay.onChange(value)
                }
        }
    }
}
