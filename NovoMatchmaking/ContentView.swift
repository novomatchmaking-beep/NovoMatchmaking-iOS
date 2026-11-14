import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var model = WebViewModel()
    @ObservedObject private var push = PushManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            // Status-bar area (time, signal, Wi-Fi, battery) tinted with the colour
            // at the top of the page.
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Color.white
                    Color(uiColor: model.headerColor)
                        .frame(height: geo.safeAreaInsets.top)
                }
                .ignoresSafeArea()
            }

            // The page starts below the status bar and runs to the bottom edge, so
            // the website's own footer menu stays fully visible.
            NovoWebView(model: model)
                .opacity(model.hasLoadedOnce ? 1 : 0.01)
                .ignoresSafeArea(edges: .bottom)

            if model.hasLoadedOnce && model.isLoading && model.problem == nil {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(.novoBurgundy)
            }

            if model.showConnectionBanner && model.problem == nil {
                ConnectionBanner {
                    model.showConnectionBanner = false
                    model.retry()
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let problem = model.problem {
                ProblemView(problem: problem,
                            retry: { model.retry() },
                            openInSafari: { model.openInSafari() })
            }
        }
        .overlay {
            if !model.hasLoadedOnce && model.problem == nil {
                SplashView()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.hasLoadedOnce)
        .animation(.easeOut(duration: 0.25), value: model.showConnectionBanner)
        .onReceive(push.$pendingURL.compactMap { $0 }) { url in
            push.pendingURL = nil
            if AppConfig.staysInApp(url) { model.load(url) } else { UIApplication.shared.open(url) }
        }
        .onReceive(push.$deviceToken.compactMap { $0 }) { _ in
            model.injectPushToken()
        }
        .onReceive(model.$headerColor) { color in
            StatusBar.adapt(to: color)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            push.clearBadge()
            Task { await push.refreshStatus() }
        }
    }
}
