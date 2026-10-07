import SwiftUI
import Combine

@Observable @MainActor
final class ScheduleViewModel {
    var schedule: Schedule?
    var isLoading = false
    var error: String?
    var fetchedAt: Date?
    private let app: AppContainer
    private let selection: UserSelection

    init(app: AppContainer, selection: UserSelection) {
        self.app = app
        self.selection = selection
    }

    func load(force: Bool = false) async {
        let key = "schedule|\\(selection.group.id)"
        if !force, schedule == nil, let cached = app.store.read(Schedule.self, key: key) {
            schedule = cached
            fetchedAt = cached.fetchedAt
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fresh = try await app.scheduleService.loadSchedule(for: selection.group)
            schedule = fresh
            fetchedAt = fresh.fetchedAt
            app.store.write(fresh, key: key)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ScheduleView: View {
    @Environment(AppContainer.self) private var app
    let selection: UserSelection

    @State private var model: ScheduleViewModel?
    @State private var selectedDate = OmskCalendar.calendar.startOfDay(for: Date())
    @State private var selectedWeek = 0
    @State private var now = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                OATAppBackground()

                if let model {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header(model)
                            dayPicker

                            if let error = model.error, model.schedule == nil {
                                errorCard(error)
                            } else if let schedule = model.schedule {
                                if let banner = model.error {
                                    OATGlassStatusBanner(
                                        title: banner,
                                        systemImage: "wifi.slash",
                                        tint: .orange
                                    )
                                    .padding(.horizontal, -12)
                                }

                                let dayLessons = lessons(schedule)
                                if dayLessons.isEmpty {
                                    emptyDay
                                } else {
                                    currentLesson(schedule)

                                    Text("Дальше сегодня")
                                        .font(.headline)
                                        .padding(.horizontal, 2)

                                    ForEach(dayLessons) { lesson in
                                        LessonCard(lesson: lesson)
                                    }
                                }
                            } else {
                                loadingCard
                            }
                        }
                        .padding()
                    }
                    .scrollIndicators(.hidden)
                    .background(Color.clear)
                    .refreshable { await model.load(force: true) }
                    .navigationTitle("Расписание")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            if model.isLoading { ProgressView() }
                        }
                    }
                }
            }
        }
        .task {
            if model == nil {
                model = ScheduleViewModel(app: app, selection: selection)
            }
            await model?.load()
            if selectedWeek == 0 {
                selectedWeek = model?.schedule?.currentWeek ?? 1
            }
        }
        .onReceive(timer) { now = $0 }
    }

    private func header(_ model: ScheduleViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.group.name)
                        .font(.title2.bold())
                    Text(selection.category.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "airplane")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(OATTheme.blue)
                    .frame(width: 48, height: 48)
                    .oatGlassSurface(radius: 16, tint: OATTheme.blue.opacity(0.08))
            }

            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .foregroundStyle(OATTheme.blue)
                Text(formattedDate(selectedDate, pattern: "EEEE, d MMMM"))
                    .font(.subheadline.weight(.medium))
            }

            if let fetchedAt = model.fetchedAt {
                Text("Обновлено \\(fetchedAt.formatted(date: .omitted, time: .shortened)) · Омск")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .oatGlassSurface(radius: 24)
    }

    private var dayPicker: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    selectedDate = OmskCalendar.calendar.date(byAdding: .day, value: -7, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.left")
                }
                .oatGlassButton()

                Spacer()

                Text(weekRangeTitle)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    selectedDate = OmskCalendar.calendar.date(byAdding: .day, value: 7, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.right")
                }
                .oatGlassButton()
            }

            HStack(spacing: 6) {
                ForEach(0..<7, id: .self) { offset in
                    let date = OmskCalendar.calendar.date(byAdding: .day, value: offset, to: weekStart) ?? selectedDate

                    Button {
                        withAnimation(.snappy) {
                            selectedDate = date
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(formattedDate(date, pattern: "EEEEE").uppercased())
                                .font(.caption2.weight(.semibold))
                            Text(formattedDate(date, pattern: "d"))
                                .font(.headline)
                        }
                        .foregroundStyle(isSelected(date) ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected(date) ? OATTheme.blue : Color.clear)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .oatGlassSurface(radius: 22, interactive: true)
    }

    private var weekRangeTitle: String {
        let end = OmskCalendar.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\\(formattedDate(weekStart, pattern: \"d\"))–\\(formattedDate(end, pattern: \"d MMMM\"))"
    }

    private var emptyDay: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 46))
                .foregroundStyle(OATTheme.blue)
            Text("На сегодня занятий нет")
                .font(.title3.bold())
            Text("Ближайшие занятия — в следующий учебный день.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 18)
        .oatGlassSurface(radius: 24)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Загружаю расписание…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .oatGlassSurface(radius: 24)
    }

    private func errorCard(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("Не удалось загрузить расписание")
                .font(.title3.bold())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .oatGlassSurface(radius: 24, tint: .orange.opacity(0.06))
    }

    private func formattedDate(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = OmskCalendar.calendar
        formatter.timeZone = OmskCalendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func currentLesson(_ schedule: Schedule) -> some View {
        let current = lessons(schedule).first { interval($0).map { $0.contains(now) } ?? false }
        let next = lessons(schedule).first { interval($0).map { $0.start > now } ?? false }

        if let current, let period = interval(current) {
            let progress = min(1, max(0, now.timeIntervalSince(period.start) / max(1, period.duration)))

            VStack(alignment: .leading, spacing: 12) {
                Label("Сейчас", systemImage: "circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\\(current.number) пара")
                            .font(.headline)
                        Text("\\(current.start) – \\(current.end)")
                            .font(.subheadline.monospacedDigit())
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(current.subject)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                        if let teacher = current.teacher {
                            Text(teacher)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let room = current.room {
                            Text("каб. \\(room)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ProgressView(value: progress)
                    .tint(.green)

                Text("До конца \\(max(0, Int(period.end.timeIntervalSince(now) / 60))) мин")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .oatGlassSurface(radius: 22, tint: .green.opacity(0.08))
        } else if let next, let period = interval(next), period.start > now {
            Label(
                "Следующая пара через \\(max(0, Int(period.start.timeIntervalSince(now) / 60))) мин",
                systemImage: "clock"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .oatGlassSurface(radius: 18)
        }
    }

    private func lessons(_ schedule: Schedule) -> [ScheduleLesson] {
        let weekday = OmskCalendar.calendar.component(.weekday, from: selectedDate)
        let week = selectedWeek == 0 ? schedule.currentWeek : selectedWeek
        return schedule.lessons
            .filter { $0.week == week && $0.weekday == weekday }
            .sorted { $0.number < $1.number }
    }

    private var weekStart: Date {
        OmskCalendar.calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
    }

    private func isSelected(_ date: Date) -> Bool {
        OmskCalendar.calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func interval(_ lesson: ScheduleLesson) -> DateInterval? {
        let parts = lesson.start.split(separator: ":").compactMap { Int($0) }
        let end = lesson.end.split(separator: ":").compactMap { Int($0) }

        guard parts.count == 2,
              end.count == 2,
              let startDate = OmskCalendar.calendar.date(
                bySettingHour: parts[0],
                minute: parts[1],
                second: 0,
                of: selectedDate
              ),
              let endDate = OmskCalendar.calendar.date(
                bySettingHour: end[0],
                minute: end[1],
                second: 0,
                of: selectedDate
              )
        else { return nil }

        return DateInterval(start: startDate, end: endDate)
    }
}

private struct LessonCard: View {
    let lesson: ScheduleLesson

    private var period: String {
        lesson.start.isEmpty ? "" : "\\(lesson.start) – \\(lesson.end)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\\(lesson.number) пара")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(period)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(lesson.subject)
                .font(.title3.bold())

            if let subgroup = lesson.subgroup {
                Label(subgroup, systemImage: "person.2")
            }
            if let teacher = lesson.teacher {
                Label(teacher, systemImage: "person")
            }
            if let room = lesson.room {
                Label("Ауд. \\(room)", systemImage: "door.left.hand.open")
            }
            if let extra = lesson.extra {
                Text(extra)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oatGlassSurface(radius: 20, interactive: true)
        .contextMenu {
            let shareText = [
                lesson.subject,
                period,
                lesson.teacher,
                lesson.room.map { "Ауд. ($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            ShareLink(item: shareText) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
