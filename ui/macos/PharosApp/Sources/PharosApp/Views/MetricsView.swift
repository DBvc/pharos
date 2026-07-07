import SwiftUI

struct MetricsView: View {
    var body: some View {
        EmptyStateView(title: "Metrics arrive in M4", systemImage: "chart.xyaxis.line", message: "Track signal count, request conversion, review quality, false positives, and unapproved write attempts.")
        .navigationTitle("Metrics")
    }
}
