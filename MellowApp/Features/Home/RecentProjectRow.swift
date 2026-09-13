import SwiftUI

struct RecentProjectRow: View {
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let project: VlogProject
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 12) {
                    placeholder
                    details
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("project-\(project.id)")
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens this vlog")
            Menu {
                Button("Delete", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(project.displayName())")
            .accessibilityIdentifier("options-\(project.id)")
        }
        .padding(.vertical, 8)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(lineWidth: 2)
                .frame(width: project.orientation == .portrait9x16 ? 42 : 74,
                       height: project.orientation == .portrait9x16 ? 74 : 42)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RecentProjectDateFormatter.string(for: project.createdAt, locale: locale, timeZone: timeZone))
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                .accessibilityLabel(project.displayName(locale: locale, timeZone: timeZone))
                .accessibilityIdentifier("recentDate-\(project.id)")
            Text(project.orientation.displayTitle).font(.subheadline)
            Text("\(project.clips.count) clips")
                .font(.subheadline).foregroundStyle(MellowDesignSystem.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension ProjectOrientation {
    var displayTitle: String {
        switch self {
        case .portrait9x16: "9:16 Portrait"
        case .landscape16x9: "16:9 Landscape"
        }
    }
}

// Recent presentation only; the canonical domain display name remains unchanged.
private enum RecentProjectDateFormatter {
    static func string(for date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let day = DateFormatter()
        day.locale = locale
        day.timeZone = timeZone
        day.setLocalizedDateFormatFromTemplate("MMMd")

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        return "\(day.string(from: date)) · \(time.string(from: date))"
    }
}
