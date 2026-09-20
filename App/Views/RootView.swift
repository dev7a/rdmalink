//
//  RootView.swift
//
//  The one window: unified toolbar, stage on the left, assistant column on
//  the right (UX_SPEC §2.1–§2.3).
//

import SwiftUI

struct RootView: View {
    @State private var model = InventoryModel()
    @State private var showsWhatThisAllMeans = false
    @AppStorage(AppSettings.showTechnicalNames) private var showsTechnicalNames = false

    var body: some View {
        HSplitView {
            StagePlaceholder(archetype: model.hardware?.archetype)
                .frame(minWidth: 460, idealWidth: 580, maxWidth: .infinity, maxHeight: .infinity)
            AssistantColumn(model: model, showsTechnicalNames: showsTechnicalNames)
                .frame(minWidth: 380, idealWidth: 420, maxHeight: .infinity)
        }
        .frame(minWidth: 840, minHeight: 560)
        .navigationTitle("RDMALink")
        .navigationSubtitle(model.windowSubtitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ThisMacBadge()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Check Again", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .help("Re-runs the full probe.")
                Button("Help", systemImage: "questionmark.circle") {
                    showsWhatThisAllMeans = true
                }
            }
        }
        .sheet(isPresented: $showsWhatThisAllMeans) {
            WhatThisAllMeansSheet()
        }
        .task { await model.start() }
    }
}
