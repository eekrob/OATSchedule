import SwiftUI
import Combine
import UIKit

@Observable @MainActor
final class ScheduleViewModel {
    var schedule: Schedule?
    var isLoading = false
    var error: String?
    var fetchedAt: Date?
    private let app: AppContainer
    private let selection: UserSelection
    init(app: AppContainer, selection: UserSelection) { self.app = app; self.selection = selection }
    func load(force: Bool = false) async {
        let key = "schedule|\(selection.group.id)"
        if !force, schedule == nil, let cached = app.store.read(Schedule.self, key: key) { schedule = cached; fetchedAt = cached.fetchedAt }
        isLoading = true; defer { isLoading = false }
        do {
            let fresh = try await app.scheduleService.loadSchedule(for: selection.group)
            schedule = fresh; fetchedAt = fresh.fetchedAt; app.store.write(fresh, key: key); error = nil
        } catch { self.error = error.localizedDescription }
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
            Group {
                if let model {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header(model)
                            weekPicker(model)
                            dayPicker
                            if let error = model.error, model.schedule == nil {
                                ContentUnavailableView("Не удалось загрузить расписание", systemImage: "wifi.exclamationmark", description: Text(error))
                            } else if let schedule = model.schedule {
                                if let banner = model.error { Label(banner, systemImage: "wifi.slash").font(.caption).foregroundStyle(.orange) }
                                currentLesson(schedule)
                                let dayLessons = lessons(schedule)
                                if dayLessons.isEmpty { ContentUnavailableView("На этот день занятий нет", systemImage: "sun.max") }
                                else { ForEach(dayLessons) { LessonCard(lesson: $0) } }
                            } else { ProgressView("Загружаю расписание…").frame(maxWidth: .infinity).padding(.top, 50) }
                        }.padding()
                    }
                    .refreshable { await model.load(force: true) }
                    .navigationTitle("Расписание")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { if model.isLoading { ProgressView() } } }
                }
            }
        }
        .task {
            if model == nil { model = ScheduleViewModel(app: app, selection: selection) }
            await model?.load()
            if selectedWeek == 0 { selectedWeek = model?.schedule?.currentWeek ?? 1 }
        }
        .onReceive(timer) { now = $0 }
    }

    private func header(_ model: ScheduleViewModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selection.group.name).font(.largeTitle.bold())
            Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU")).timeZone(OmskCalendar.timeZone)))
                .font(.title3).foregroundStyle(.secondary)
            if let fetchedAt = model.fetchedAt {
                Text("Обновлено \(fetchedAt.formatted(date: .omitted, time: .shortened)) · Омск").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func weekPicker(_ model: ScheduleViewModel) -> some View {
        HStack {
            Text("Учебная неделя").font(.subheadline.weight(.semibold))
            Spacer()
            Picker("Учебная неделя", selection: $selectedWeek) {
                Text("1").tag(1); Text("2").tag(2)
            }.pickerStyle(.segmented).frame(width: 120)
        }
    }
    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(0..<7, id: \.self) { offset in
                    let date = OmskCalendar.calendar.date(byAdding: .day, value: offset, to: weekStart) ?? selectedDate
                    Button {
                        withAnimation(.snappy) { selectedDate = date }
                    } label: {
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ru_RU")).timeZone(OmskCalendar.timeZone)).uppercased())
                                .font(.caption2.weight(.semibold))
                            Text(date.formatted(.dateTime.day().timeZone(OmskCalendar.timeZone))).font(.headline)
                        }
                        .foregroundStyle(isSelected(date) ? Color.white : Color.primary)
                        .frame(width: 43, height: 56)
                        .background(isSelected(date) ? Color.indigo : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func currentLesson(_ schedule: Schedule) -> some View {
        let current = lessons(schedule).first { interval($0).map { $0.contains(now) } ?? false }
        let next = lessons(schedule).first { interval($0).map { $0.start > now } ?? false }
        return Group {
            if let current, let period = interval(current) {
                let progress = min(1, max(0, now.timeIntervalSince(period.start) / max(1, period.duration)))
                VStack(alignment: .leading, spacing: 8) {
                    Label("Сейчас · \(current.subject)", systemImage: "bolt.fill").font(.headline)
                    ProgressView(value: progress).tint(.indigo)
                    Text("До конца \(max(0, Int(period.end.timeIntervalSince(now) / 60))) мин").font(.caption).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            } else if let next, let period = interval(next), period.start > now {
                Text("Следующая пара через \(max(0, Int(period.start.timeIntervalSince(now) / 60))) мин").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private func lessons(_ schedule: Schedule) -> [ScheduleLesson] {
        let weekday = OmskCalendar.calendar.component(.weekday, from: selectedDate)
        let week = selectedWeek == 0 ? schedule.currentWeek : selectedWeek
        return schedule.lessons.filter { $0.week == week && $0.weekday == weekday }.sorted { $0.number < $1.number }
    }
    private var weekStart: Date { OmskCalendar.calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate }
    private func isSelected(_ date: Date) -> Bool { OmskCalendar.calendar.isDate(date, inSameDayAs: selectedDate) }
    private func interval(_ lesson: ScheduleLesson) -> DateInterval? {
        let parts = lesson.start.split(separator: ":").compactMap { Int($0) }; let end = lesson.end.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, end.count == 2,
              let startDate = OmskCalendar.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: selectedDate),
              let endDate = OmskCalendar.calendar.date(bySettingHour: end[0], minute: end[1], second: 0, of: selectedDate) else { return nil }
        return DateInterval(start: startDate, end: endDate)
    }
}

private struct LessonCard: View {
    let lesson: ScheduleLesson
    private var period: String { lesson.start.isEmpty ? "" : "\(lesson.start) – \(lesson.end)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text("\(lesson.number) пара").font(.subheadline.weight(.semibold)); Spacer(); Text(period).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
            Text(lesson.subject).font(.title3.bold())
            if let subgroup = lesson.subgroup { Label(subgroup, systemImage: "person.2") }
            if let teacher = lesson.teacher { Label(teacher, systemImage: "person") }
            if let room = lesson.room { Label("Ауд. \(room)", systemImage: "door.left.hand.open") }
            if let extra = lesson.extra { Text(extra).font(.caption).foregroundStyle(.secondary) }
        }
        .font(.subheadline).padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .contextMenu {
            let shareText = [lesson.subject, period, lesson.teacher, lesson.room.map { "Ауд. \($0)" }].compactMap { $0 }.joined(separator: "\n")
            ShareLink(item: shareText) { Label("Поделиться", systemImage: "square.and.arrow.up") }
            Button { UIPasteboard.general.string = shareText } label: { Label("Скопировать", systemImage: "doc.on.doc") }
        }
        .accessibilityElement(children: .combine)
    }
}
