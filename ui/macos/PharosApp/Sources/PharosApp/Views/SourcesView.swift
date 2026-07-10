import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var sources: [SourceConfig] = []
    @State private var scopeDrafts: [String: String] = [:]
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading, sources.isEmpty {
                ProgressView("Loading Sources")
            }

            Section("P0 Sources") {
                ForEach(sources) { source in
                    SourceConfigRow(
                        source: source,
                        scopeText: Binding(
                            get: { scopeDrafts[source.id] ?? source.scopeJson },
                            set: { scopeDrafts[source.id] = $0 }
                        ),
                        onEnabled: { value in patch(source, enabled: value) },
                        onReadEnabled: { value in patch(source, readEnabled: value) },
                        onWriteEnabled: { value in patch(source, writeEnabled: value) },
                        onSaveScope: { value in patch(source, scopeJson: value) }
                    )
                }
            }
        }
        .navigationTitle("Sources")
        .task { await loadSources() }
        .toolbar {
            Button {
                Task { await loadSources() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    private func loadSources() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await appState.api.sources()
            sources = response.sources
            scopeDrafts = Dictionary(uniqueKeysWithValues: response.sources.map { ($0.id, $0.scopeJson) })
            appState.errorMessage = nil
        } catch {
            appState.errorMessage = readable(error)
        }
    }

    private func patch(
        _ source: SourceConfig,
        enabled: Bool? = nil,
        readEnabled: Bool? = nil,
        writeEnabled: Bool? = nil,
        scopeJson: String? = nil
    ) {
        updateLocal(source.id) { current in
            if let enabled { current.enabled = enabled }
            if let readEnabled { current.readEnabled = readEnabled }
            if let writeEnabled { current.writeEnabled = writeEnabled }
            if let scopeJson { current.scopeJson = scopeJson }
        }

        Task {
            do {
                let response = try await appState.api.patchSource(
                    id: source.id,
                    payload: SourcePatchPayload(
                        enabled: enabled,
                        readEnabled: readEnabled,
                        writeEnabled: writeEnabled,
                        scopeJson: scopeJson
                    )
                )
                replace(response.source)
                scopeDrafts[response.source.id] = response.source.scopeJson
                appState.errorMessage = nil
            } catch {
                appState.errorMessage = readable(error)
                await loadSources()
            }
        }
    }

    private func updateLocal(_ id: String, mutate: (inout SourceConfig) -> Void) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sources[index])
    }

    private func replace(_ source: SourceConfig) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else {
            sources.append(source)
            return
        }
        sources[index] = source
    }

    private func readable(_ error: Error) -> String {
        if let apiError = error as? APIErrorResponse { return apiError.error }
        return error.localizedDescription
    }
}

private struct SourceConfigRow: View {
    let source: SourceConfig
    @Binding var scopeText: String
    let onEnabled: (Bool) -> Void
    let onReadEnabled: (Bool) -> Void
    let onWriteEnabled: (Bool) -> Void
    let onSaveScope: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(source.kind.label)
                    .font(.headline)
                StatusBadge(text: source.enabled ? "ON" : "OFF")
                Spacer()
                Text(source.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                Toggle("Enabled", isOn: Binding(get: { source.enabled }, set: onEnabled))
                Toggle("Read", isOn: Binding(get: { source.readEnabled }, set: onReadEnabled))
                Toggle("Write", isOn: Binding(get: { source.writeEnabled }, set: onWriteEnabled))
            }
            .toggleStyle(.switch)

            Text("External writes still require review even when write permission is enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("{}", text: $scopeText)
                    .font(.system(.caption, design: .monospaced))
                Button {
                    onSaveScope(scopeText)
                } label: {
                    Label("Save scope", systemImage: "square.and.arrow.down")
                }
            }

            HStack(spacing: 12) {
                Text("Last sync: \(source.lastSyncAt ?? "never")")
                if let lastError = source.lastError, !lastError.isEmpty {
                    Text("Last error: \(lastError)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
