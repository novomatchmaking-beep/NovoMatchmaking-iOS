import SwiftUI

/// Matches the launch screen exactly (same logo, same size, centred), so the
/// hand-off from iOS's launch screen to the app is seamless.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)
                .accessibilityLabel("Novo Matchmaking")
            ProgressView()
                .tint(.novoBurgundy)
                .offset(y: 170)
        }
    }
}

struct ProblemView: View {
    let problem: WebViewModel.Problem
    let retry: () -> Void
    let openInSafari: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image("NovoLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 150, maxHeight: 150)

            Image(systemName: icon)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Color.novoBurgundy)

            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Color.novoBurgundy)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: retry) {
                Text("Try Again").frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .tint(.novoBurgundy)
            .controlSize(.large)

            if problem != .offline {
                Button("Open in Safari", action: openInSafari)
                    .buttonStyle(.bordered)
                    .tint(.novoBurgundy)
            }

            if case .loadFailed(let detail) = problem {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var icon: String {
        switch problem {
        case .offline: return "wifi.slash"
        case .loadFailed: return "exclamationmark.triangle"
        case .emptyPage: return "doc"
        case .renderingStopped: return "arrow.clockwise.circle"
        }
    }

    private var title: String {
        switch problem {
        case .offline: return "You're offline"
        case .loadFailed: return "We couldn't load the page"
        case .emptyPage: return "The page came back empty"
        case .renderingStopped: return "Something went wrong"
        }
    }

    private var message: String {
        switch problem {
        case .offline:
            return "Check your Wi-Fi or mobile data. We'll reconnect automatically when you're back online."
        case .loadFailed:
            return "Please check your connection and try again."
        case .emptyPage:
            return "Our website didn't return any content. Please try again in a moment."
        case .renderingStopped:
            return "The page stopped unexpectedly. Tap Try Again to reload it."
        }
    }
}

/// Small, non-blocking message shown when a page change fails but the
/// current page is still visible.
struct ConnectionBanner: View {
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            Label("Connection problem · Tap to retry", systemImage: "wifi.exclamationmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.novoBurgundy))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}
