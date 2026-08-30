//
//  ServiceKeysView.swift
//  Sonava
//
//  Where the owner's self-serve keys get pasted — the missing half of
//  `ServiceKeysStore`, which could read keys since the hub shipped but had
//  no screen that ever wrote one, so every "Key saved" card state was
//  unreachable by construction.
//
//  One screen, one field per service, saved locally and nowhere else. Each
//  hub card in the `ownerKey` state opens this sheet; the moment a key is
//  saved the card's state changes on its own, because both read the same
//  store.
//

import SwiftUI

struct ServiceKeysView: View {
    @ObservedObject private var store = ServiceKeysStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var values: [String: String] = [:]

    /// One key the owner can paste: where it lives in the store, what to
    /// call it, and where it comes from.
    private struct Entry: Identifiable {
        let name: String
        let title: LocalizedStringKey
        let hint: String
        var id: String { name }
    }

    private var entries: [Entry] {
        [
            Entry(name: JamendoService.clientIDKey,
                  title: "Jamendo · Client ID",
                  hint: String(localized: "Free self-serve key from devportal.jamendo.com — unlocks the Creative Commons catalogue with full playback.")),
            Entry(name: YouTubePlaylistImporter.apiKeyKey,
                  title: "YouTube · API key",
                  hint: String(localized: "A Google Cloud key with YouTube Data API v3 enabled — unlocks playlist import by link. Titles only, never audio.")),
            Entry(name: "tidal.clientID",
                  title: "TIDAL · Client ID",
                  hint: String(localized: "From developer.tidal.com — stored for the day TIDAL opens more than 30-second previews to third-party apps."))
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        Text("Owner keys for self-serve services. They stay on this device.")
                            .font(.system(.footnote))
                            .foregroundColor(Theme.textTertiary)

                        ForEach(entries) { entry in
                            field(for: entry)
                        }

                        Button {
                            save()
                            Haptics.success()
                            dismiss()
                        } label: {
                            Text("Save keys")
                        }
                        .buttonStyle(PrimaryCapsuleButtonStyle())
                        .accessibilityIdentifier("keys.save")
                    }
                    .padding(Space.screenMargin)
                    .padding(.bottom, 40)
                }
            }
            .foregroundColor(.white)
            .navigationTitle("Service keys")
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            for entry in entries where values[entry.name] == nil {
                values[entry.name] = store.key(entry.name) ?? ""
            }
        }
    }

    private func field(for entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Department(title: entry.title)
                if store.key(entry.name) != nil {
                    Text("Key saved")
                        .font(.sonavaFact)
                        .foregroundColor(Theme.accentSoft)
                }
            }
            Text(verbatim: entry.hint)
                .font(.system(.footnote))
                .foregroundColor(Theme.textTertiary)
            TextField("", text: binding(for: entry.name),
                      prompt: Text("Paste the key").foregroundColor(Theme.textTertiary))
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                .card(cornerRadius: Radius.control)
                .accessibilityIdentifier("keys.\(entry.name)")
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(get: { values[name] ?? "" },
                set: { values[name] = $0 })
    }

    private func save() {
        for entry in entries {
            let value = (values[entry.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            store.set(entry.name, to: value)
        }
    }
}
