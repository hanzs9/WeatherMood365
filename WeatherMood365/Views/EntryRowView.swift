import SwiftUI

struct EntryRowView: View {
    @EnvironmentObject private var store: EntryStore
    let entry: DailyEntry

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.date, format: .dateTime.year().month().day())
                    .font(.headline)

                HStack(spacing: 8) {
                    if let weather = entry.weather {
                        Text("\(weather.summary) \(weather.temperature, specifier: "%.0f")°C")
                    }

                    MoodTextView(mood: entry.mood, iconSize: 18)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = store.imageURL(for: entry) {
            CachedPhotoView(
                url: url,
                targetSize: CGSize(width: 64, height: 64),
                contentMode: .fill
            ) {
                thumbnailPlaceholder
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.secondary.opacity(0.18))
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}
