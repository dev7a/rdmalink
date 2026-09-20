//
//  HubSplit.swift
//
//  The body layout's draggable divider (UX_SPEC §2.3).
//
//  Written rather than taken from `HSplitView` because the spec asks for three
//  things `HSplitView` will not give: a *default* of 58 / 42 (it divides the
//  width evenly whatever ideal widths its children ask for), a position that is
//  remembered, and a `Reset View` that can put it back. Declaring the model the
//  hero and then letting the divider land wherever AppKit feels like is the
//  kind of near-miss the rest of this app is written to avoid.
//

import AppKit
import SwiftUI

struct HubSplit<Stage: View, Column: View>: View {
    /// The width the parent has already measured, so this view adds no second
    /// `GeometryReader` to the window.
    let availableWidth: CGFloat
    let stageMinimum: CGFloat
    let columnMinimum: CGFloat
    @ViewBuilder var stage: Stage
    @ViewBuilder var column: Column

    private static var dividerHitWidth: CGFloat { 9 }

    @AppStorage(AppSettings.stageSplitFraction) private var fraction = HubSplitDefaults.fraction
    /// The stage width the current drag started from, so the divider tracks the
    /// pointer instead of accumulating rounding error.
    @State private var dragOrigin: CGFloat?
    /// Whether *this* view has a cursor on AppKit's stack to pop.
    @State private var pushedCursor = false

    var body: some View {
        let stageWidth = resolvedStageWidth
        HStack(spacing: 0) {
            stage.frame(width: stageWidth)
            divider(from: stageWidth)
            column.frame(width: max(columnMinimum, availableWidth - stageWidth - 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The remembered fraction, clamped so neither side can be squeezed past
    /// its minimum however narrow the window gets.
    private var resolvedStageWidth: CGFloat {
        let ideal = availableWidth * fraction
        let widest = max(stageMinimum, availableWidth - columnMinimum - 1)
        return min(max(ideal, stageMinimum), widest)
    }

    private func divider(from stageWidth: CGFloat) -> some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: Self.dividerHitWidth)
                    .contentShape(.rect)
                    // Pushed and popped exactly once each. AppKit's cursor
                    // stack is app-wide, and the `false` callback never arrives
                    // for a view that is removed while the pointer is on it —
                    // §8.5's reflow removes this one every time the window
                    // crosses 900 pt — which would leave the resize cursor
                    // outranking §4.5's `.operationNotAllowed` for the rest of
                    // the session.
                    .onHover { isInside in
                        guard isInside != pushedCursor else { return }
                        pushedCursor = isInside
                        if isInside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .onDisappear {
                        guard pushedCursor else { return }
                        pushedCursor = false
                        NSCursor.pop()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let origin = dragOrigin ?? stageWidth
                                dragOrigin = origin
                                move(to: origin + value.translation.width)
                            }
                            .onEnded { _ in dragOrigin = nil }
                    )
            }
            .accessibilityHidden(true)
    }

    private func move(to width: CGFloat) {
        guard availableWidth > 0 else { return }
        let widest = max(stageMinimum, availableWidth - columnMinimum - 1)
        fraction = Double(min(max(width, stageMinimum), widest) / availableWidth)
    }
}


/// §2.3: "`Reset View` (⌘0) returns the split to 58/42 and the camera to its
/// resting pose." The camera half is `StageModel.reset()`; this is the other
/// half, and it lives outside the generic view so the View menu can call it.
enum HubSplitDefaults {
    /// "Default split: stage 58 %, column 42 %."
    static let fraction = 0.58

    static func reset() {
        UserDefaults.standard.set(fraction, forKey: AppSettings.stageSplitFraction)
    }
}
