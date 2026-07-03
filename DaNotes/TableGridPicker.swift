//
//  TableGridPicker.swift
//  DaNotes
//
//  The row/column grid picker used when inserting a Markdown table from the
//  keyboard shortcuts bar (iPad only). Styled with the iOS 26 Liquid Glass
//  design.
//

#if os(iOS)
import SwiftUI

/// A grid the user drags across to pick the number of rows and columns for a
/// new Markdown table.
struct TableGridPicker: View {
    var onSelect: (_ rows: Int, _ columns: Int) -> Void

    @State private var rows = 1
    @State private var columns = 1

    // The cell size and gap scale with the user's Dynamic Type setting rather
    // than being fixed point values, so the picker matches the rest of the UI.
    // Every other measurement (spacing, padding, corner radius) is derived from
    // these two, so there are no standalone magic numbers.
    @ScaledMetric(relativeTo: .title3) private var cell: CGFloat = 28
    @ScaledMetric(relativeTo: .title3) private var gap: CGFloat = 6

    private let maxRows = 8
    private let maxColumns = 8

    var body: some View {
        VStack(spacing: gap * 3) {
            VStack {
                Text(.mdTable)
                    .font(.headline)
                Text(verbatim: "\(rows) × \(columns)")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: rows)
                    .animation(.snappy(duration: 0.2), value: columns)
            }

            grid

            Button {
                onSelect(rows, columns)
            } label: {
                Text(.insertButton)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
        }
        .padding(cell)
    }

    private var grid: some View {
        GlassEffectContainer(spacing: gap) {
            VStack(spacing: gap) {
                ForEach(1...maxRows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(1...maxColumns, id: \.self) { column in
                            let selected = row <= rows && column <= columns
                            RoundedRectangle(cornerRadius: cell / 4)
                                .fill(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let step = cell + gap
                    let newColumns = min(max(Int(value.location.x / step) + 1, 1), maxColumns)
                    let newRows = min(max(Int(value.location.y / step) + 1, 1), maxRows)
                    if newColumns != columns { columns = newColumns }
                    if newRows != rows { rows = newRows }
                }
        )
    }
}
#endif
