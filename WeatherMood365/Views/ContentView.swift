import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .today
    @State private var calendarJumpToken = 0

    var body: some View {
        TabView(selection: tabSelection) {
            TodayView()
                .tabItem {
                    Label("今天", systemImage: "camera.fill")
                }
                .tag(AppTab.today)

            YearCalendarView(targetDate: Date(), jumpToken: calendarJumpToken)
                .tabItem {
                    Label("日历", systemImage: "calendar")
                }
                .tag(AppTab.calendar)

            LocationMapView()
                .tabItem {
                    Label("地图", systemImage: "map")
                }
                .tag(AppTab.map)
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding {
            selectedTab
        } set: { newValue in
            if newValue == .calendar {
                calendarJumpToken += 1
            }

            selectedTab = newValue
        }
    }
}

private enum AppTab: Hashable {
    case today
    case calendar
    case map
}

private struct TodayView: View {
    @EnvironmentObject private var store: EntryStore
    @State private var isCameraPresented = false
    @State private var pendingCapturedPhoto: PickedPhoto?
    @State private var isCapturedEditorActive = false

    private var todayEntry: DailyEntry? {
        store.entry(for: Date())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        todaySummary

                        Button {
                            isCameraPresented = true
                        } label: {
                            Label(todayEntry == nil ? "记录今天" : "更新今天", systemImage: "camera.fill")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(red: 1.0, green: 0.82, blue: 0.24))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                }

                Section("最近记录") {
                    if store.sortedEntries.isEmpty {
                        ContentUnavailableView(
                            "还没有记录",
                            systemImage: "calendar.badge.plus",
                            description: Text("从今天开始，留下每天的天气、照片和一句话。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        ForEach(Array(store.sortedEntries.prefix(7))) { entry in
                            NavigationLink {
                                EntryDetailView(date: entry.date)
                            } label: {
                                EntryRowView(entry: entry)
                            }
                        }
                    }
                }
            }
            .navigationTitle("今天")
            .navigationDestination(isPresented: $isCapturedEditorActive) {
                EntryEditorView(entry: todayEntry ?? DailyEntry(), initialPickedPhoto: pendingCapturedPhoto, shouldFetchCurrentLocationForInitialPhoto: true)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        EntryEditorView(entry: DailyEntry())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("记录今天")
                }
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                CameraPickerView { pickedPhoto in
                    pendingCapturedPhoto = pickedPhoto
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isCapturedEditorActive = true
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var todaySummary: some View {
        if let todayEntry {
            VStack(alignment: .leading, spacing: 14) {
                CachedPhotoView(
                    url: store.imageURL(for: todayEntry),
                    targetSize: CGSize(width: 720, height: 520),
                    contentMode: .fill
                ) {
                    Color.secondary.opacity(0.12)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    Text(todayEntry.date, format: .dateTime.year().month().day().weekday())
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        MoodTextView(mood: todayEntry.mood, iconSize: 18)
                            .lineLimit(1)

                        if let weather = todayEntry.weather {
                            HStack(spacing: 5) {
                                Image(systemName: weather.symbol)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 20, height: 20)

                                Text("\(weather.summary) \(weather.temperature, specifier: "%.0f")°C")
                                    .lineLimit(1)
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                    if !todayEntry.note.isEmpty {
                        Text(todayEntry.note)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("今天还没有记录")
                    .font(.title2.weight(.semibold))

                Text("拍一张照片，保存今天的天气和心情。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(EntryStore())
}
