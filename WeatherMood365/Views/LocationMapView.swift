import MapKit
import SwiftUI

struct LocationMapView: View {
    @EnvironmentObject private var store: EntryStore

    private var entriesWithLocation: [DailyEntry] {
        store.sortedEntries.filter { $0.photoLocation != nil }
    }

    private var initialPosition: MapCameraPosition {
        guard let anchorLocation = anchorEntry?.photoLocation else {
            return .automatic
        }

        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: anchorLocation.latitude,
                longitude: anchorLocation.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        ))
    }

    private var anchorEntry: DailyEntry? {
        entriesWithLocation.first { Calendar.current.isDateInToday($0.date) } ?? entriesWithLocation.first
    }

    var body: some View {
        NavigationStack {
            if entriesWithLocation.isEmpty {
                ContentUnavailableView(
                    "还没有照片位置",
                    systemImage: "map",
                    description: Text("只有照片本身带有定位信息时，记录才会显示在地图上。")
                )
                .navigationTitle("地图")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                Map(initialPosition: initialPosition) {
                    ForEach(entriesWithLocation) { entry in
                        if let location = entry.photoLocation {
                            Annotation(
                                entry.date.formatted(.dateTime.month().day()),
                                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                            ) {
                                NavigationLink {
                                    EntryDetailView(date: entry.date)
                                } label: {
                                    MapPhotoMarker(entry: entry, photoURL: store.imageURL(for: entry))
                                }
                                .buttonStyle(.pressableCard(
                                    cornerRadius: AppRadius.primary,
                                    pressedScale: 0.97,
                                    overlayColor: .black.opacity(0.08),
                                    shadowColor: .black.opacity(0.12),
                                    shadowRadius: 10,
                                    shadowY: 4
                                ))
                            }
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("地图")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct MapPhotoMarker: View {
    let entry: DailyEntry
    let photoURL: URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let photoURL {
                    CachedPhotoView(
                        url: photoURL,
                        targetSize: CGSize(width: 72, height: 72),
                        contentMode: .fill
                    ) {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.standard))

            LinearGradient(
                colors: [.clear, .black.opacity(0.58)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.standard))

            Text(entry.date.formatted(.dateTime.month().day()))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .padding(.bottom, 5)
        }
        .frame(width: 72, height: 72)
        .background(.white, in: RoundedRectangle(cornerRadius: AppRadius.primary))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.primary)
                .stroke(.white, lineWidth: 3)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.primary))
        .shadow(color: .black.opacity(0.25), radius: 7, x: 0, y: 4)
        .accessibilityLabel("\(entry.date.formatted(.dateTime.month().day()))的位置记录")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.75), .cyan.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "camera.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
