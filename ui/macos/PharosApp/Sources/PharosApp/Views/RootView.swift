import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: SidebarItem? = .today

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Today", systemImage: "sun.max").tag(SidebarItem.today)
                Label("Sources", systemImage: "antenna.radiowaves.left.and.right").tag(SidebarItem.sources)
                Label("Rules", systemImage: "slider.horizontal.3").tag(SidebarItem.rules)
                Label("Metrics", systemImage: "chart.xyaxis.line").tag(SidebarItem.metrics)
            }
            .navigationTitle("Pharos")
        } detail: {
            switch selection {
            case .today, .none:
                TodayView()
            case .sources:
                SourcesView()
            case .rules:
                RulesView()
            case .metrics:
                MetricsView()
            }
        }
        .sheet(isPresented: $appState.showCapture) {
            CaptureView()
                .environmentObject(appState)
        }
        .toolbar {
            Button {
                appState.showCapture = true
            } label: {
                Label("Capture", systemImage: "plus")
            }
            Button {
                Task { await appState.refreshToday() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .overlay(alignment: .bottom) {
            if let error = appState.errorMessage {
                Text(error)
                    .font(.callout)
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
        }
    }
}

enum SidebarItem: Hashable {
    case today
    case sources
    case rules
    case metrics
}
