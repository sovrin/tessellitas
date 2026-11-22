//
//  ProfileEditor.swift
//  tessellitas
//

import SwiftUI

struct ProfileEditor: View {
    @Binding var profile: Profile
    let nameIsTaken: Bool
    let canDelete: Bool
    let onDelete: () -> Void

    @State private var zoneSelection: UUID?
    @State private var previewAspect = 21.0 / 9
    @State private var columnWeights = "1 3 1"
    @State private var rowWeights = "1"

    private static let previewAspects: [(String, Double)] = [
        ("16:10", 16.0 / 10), ("16:9", 16.0 / 9), ("21:9", 21.0 / 9), ("32:9", 32.0 / 9),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                canvasCard
                detailsCard
                zonesCard
            }
            .padding(20)
        }
        .navigationTitle(profile.name.isEmpty ? "Profile" : profile.name)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Halves") { apply(columns: [1, 1]) }
                    Button("Thirds") { apply(columns: [1, 1, 1]) }
                    Button("¼ · ½ · ¼") { apply(columns: [1, 2, 1]) }
                    Button("⅕ · ⅗ · ⅕") { apply(columns: [1, 3, 1]) }
                    Button("⅔ · ⅓") { apply(columns: [2, 1]) }
                    Divider()
                    Button("Top and bottom") { apply(columns: [1], rows: [1, 1]) }
                    Button("Quarters") { apply(columns: [1, 1], rows: [1, 1]) }
                    Button("Six-up grid") { apply(columns: [1, 1, 1], rows: [1, 1]) }
                } label: {
                    Label("Layouts", systemImage: "rectangle.split.3x1")
                }
                .help("Replace the zones with a preset layout")
            }
            ToolbarItem {
                Button(role: .destructive, action: onDelete) { Label("Delete Profile", systemImage: "trash") }
                    .disabled(!canDelete)
                    .help(canDelete ? "Delete this profile" : "Keep at least one profile")
            }
        }
        .onAppear { previewAspect = Self.defaultAspect(for: profile) }
    }

    // MARK: Canvas

    private var canvasCard: some View {
        Card(note: "Drag a zone to move it. Select it to show the corner handles and resize. Edges snap to 1/60 of the screen.") {
            ZoneCanvas(zones: $profile.zones, selection: $zoneSelection, aspect: previewAspect)
                .frame(maxHeight: 280)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            Picker("Preview as", selection: $previewAspect) {
                ForEach(Self.previewAspects, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Details

    private var detailsCard: some View {
        let isAutomatic = Binding(
            get: { profile.minAspectRatio != nil },
            set: { profile.minAspectRatio = $0 ? 2.0 : nil }
        )
        let ratio = Binding(
            get: { profile.minAspectRatio ?? 2.0 },
            set: { profile.minAspectRatio = max($0, 0.1) }
        )

        return Card(title: "Profile") {
            LabeledContent("Name") {
                TextField("Name", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            if nameIsTaken {
                Label("Another profile already uses this name.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            Toggle("Use automatically on wide displays", isOn: isAutomatic)
            if isAutomatic.wrappedValue {
                LabeledContent("Width ÷ height at least") {
                    TextField("", value: ratio, format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                }
                Text("16:9 is 1.78, 21:9 is 2.33, 32:9 is 3.56. You can still pin this profile to any display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            LabeledContent("Generate from sizes") {
                HStack(spacing: 8) {
                    Text("Columns").foregroundStyle(.secondary)
                    TextField("1 3 1", text: $columnWeights).frame(width: 84)
                    Text("Rows").foregroundStyle(.secondary)
                    TextField("1", text: $rowWeights).frame(width: 56)
                    Button("Apply") {
                        apply(columns: Self.parseWeights(columnWeights), rows: Self.parseWeights(rowWeights))
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: Zones

    private var zonesCard: some View {
        Card(title: "Zones",
             note: profile.zones.count >= 9 ? "Hotkeys cover the first nine zones." : "Zone numbers are the keys you press. Reorder to renumber.") {
            if profile.zones.isEmpty {
                Text("This profile has no zones yet. Add one, or pick a layout from the toolbar.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("")
                        ForEach(["X", "Y", "Width", "Height"], id: \.self) { title in
                            Text(title).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("")
                    }
                    ForEach($profile.zones) { $zone in
                        ZoneRow(zone: $zone,
                                number: (profile.zones.firstIndex { $0.id == zone.id } ?? 0) + 1,
                                isSelected: zone.id == zoneSelection,
                                canMoveUp: profile.zones.first?.id != zone.id,
                                canMoveDown: profile.zones.last?.id != zone.id,
                                select: { zoneSelection = zone.id },
                                move: { move(zone.id, by: $0) },
                                delete: { delete(zone.id) })
                    }
                }
            }
            Button {
                let zone = Zone(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                profile.zones.append(zone)
                zoneSelection = zone.id
            } label: { Label("Add Zone", systemImage: "plus") }
            .disabled(profile.zones.count >= 9)
        }
    }

    // MARK: Actions

    private func apply(columns: [Double], rows: [Double] = [1]) {
        profile.zones = Zone.grid(columns: columns, rows: rows)
        zoneSelection = nil
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = profile.zones.firstIndex(where: { $0.id == id }),
              profile.zones.indices.contains(index + offset) else { return }
        profile.zones.swapAt(index, index + offset)
    }

    private func delete(_ id: UUID) {
        profile.zones.removeAll { $0.id == id }
        if zoneSelection == id { zoneSelection = nil }
    }

    private static func parseWeights(_ text: String) -> [Double] {
        text.split(whereSeparator: { " ,:;/".contains($0) }).compactMap { Double($0) }.filter { $0 > 0 }
    }

    private static func defaultAspect(for profile: Profile) -> Double {
        switch profile.minAspectRatio ?? 0 {
        case 3...: 32.0 / 9
        case 2...: 21.0 / 9
        default: 16.0 / 9
        }
    }
}

private struct ZoneRow: View {
    @Binding var zone: Zone
    let number: Int
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let select: () -> Void
    let move: (Int) -> Void
    let delete: () -> Void

    var body: some View {
        GridRow {
            Text("\(number)")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .frame(width: 26, height: 22)
                .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
                .onTapGesture(perform: select)
            PercentField(value: $zone.x, zone: $zone)
            PercentField(value: $zone.y, zone: $zone)
            PercentField(value: $zone.width, zone: $zone)
            PercentField(value: $zone.height, zone: $zone)
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp).help("Move up (renumbers the zone)")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown).help("Move down (renumbers the zone)")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .help("Delete zone")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Edits one fraction of a zone as a percentage, then re-clamps the whole zone so it stays on screen.
private struct PercentField: View {
    @Binding var value: Double
    @Binding var zone: Zone

    var body: some View {
        let percent = Binding<Double>(
            get: { (value * 1000).rounded() / 10 },
            set: { newValue in
                value = newValue / 100
                zone = zone.clamped()
            }
        )
        TextField("", value: percent, format: .number.precision(.fractionLength(0...1)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
    }
}

#Preview("Profile editor") {
    @Previewable @State var profile = Profile.columns("Ultrawide 1-3-1", weights: [1, 3, 1], minAspectRatio: 2.0)
    NavigationStack {
        ProfileEditor(profile: $profile, nameIsTaken: false, canDelete: true, onDelete: {})
    }
    .frame(width: 700, height: 900)
}
