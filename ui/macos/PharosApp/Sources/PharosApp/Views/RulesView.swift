import SwiftUI

struct RulesView: View {
    var body: some View {
        EmptyStateView(title: "Rules are planned for M2", systemImage: "slider.horizontal.3", message: "Start with simple source, keyword, priority, and review-required rules. Do not turn this into a workflow editor yet.")
        .navigationTitle("Rules")
    }
}
