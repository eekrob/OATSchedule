import SwiftUI
import UIKit

@Observable @MainActor
final class ChangesViewModel {
    var changes: [ScheduleChange] = []
    var isLoading = false
    var error: String?
    private let app: AppContainer
    private let selection: UserSelection
    init(app: AppContainer, selection: UserSelection) { self.app = app; self.selection = selection }

    func load(force: Bool = false) async {
        let key = "changes|selection|\(selection.category.id)"
        if !force, changes.isEmpty, let cached = app.store.read([ScheduleChange].self, key: key) { changes = cached }
        isLoading = true; defer { isLoading = false }
        do {
            let scheduleCategories = try await app.scheduleService.loadCategories()
            let changeCategories = try await app.changesService.loadCategories()
            guard let index = scheduleCategories.firstIndex(where: { $0.id == selection.category.id }), changeCategories.indices.contains(index) else { throw AppFailure.invalidStructure }
            let fresh = try await app.changesService.loadChanges(in: changeCategories[index])
            let categoryKey = "changes|\(changeCategories[index].id)"
            let previous = app.store.read([ScheduleChange].self, key: categoryKey)
            if previous?.isEmpty == false && fresh.isEmpty {
                error = "Сайт вернул пустой список. Показана последняя сохранённая версия."
                return
            }
            if let previous {
                let normalizedGroup = selection.group.name.filter { $0.isLetter || $0.isNumber }.uppercased()
                for delta in ChangeDiffEngine().diff(old: previous, new: fresh) {
                    let change: ScheduleChange
                    switch delta { case .added(let item): change = item; case .updated(_, let item): change = item; case .removed: continue }
                    guard change.group.filter({ $0.isLetter || $0.isNumber }).uppercased() == normalizedGroup else { continue }
                    let sentKey = "notified|\(change.stableID)"
                    if app.store.read(Bool.self, key: sentKey) != true {
                        await app.notifications.notify(change)
                        app.store.write(true, key: sentKey)
                    }
                }
            }
            app.store.write(fresh, key: categoryKey)
            app.store.write(fresh, key: key)
            changes = fresh; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ChangesView: View {
    @Environment(AppContainer.self) private var app
    let selection: UserSelection
    @Binding var deepLinkedChangeID: String?
    @State private var model: ChangesViewModel?
    @State private var scope = 0
    @State private var selectedDateKey = "__AUTO__"
    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    VStack(spacing: 0) {
                        Picker("Фильтр", selection: $scope) {
                            Text("Моя группа").tag(0)
                            Text("Все группы").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .animation(.snappy, value: scope)

                        if !availableDates(model.changes).isEmpty {
                            datePicker(for: model.changes)
                                .padding(.bottom, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if let error = model.error, model.changes.isEmpty {
                            ContentUnavailableView("Не удалось загрузить изменения", systemImage: "wifi.exclamationmark", description: Text(error))
                        } else {
                            let items = visibleChanges(model.changes)
                            if items.isEmpty {
                                ContentUnavailableView("Изменений нет", systemImage: "checkmark.circle", description: Text(scope == 0 ? "Для \(selection.group.name) пока всё по расписанию." : "Для выбранного корпуса пока нет опубликованных изменений."))
                            } else {
                                ScrollViewReader { proxy in
                                    ScrollView {
                                        LazyVStack(spacing: 12) {
                                            ForEach(items) { change in
                                                ChangeCard(change: change, isHighlighted: deepLinkedChangeID == change.stableID)
                                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                            }
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 10)
                                        .animation(.snappy, value: items.map(\.stableID))
                                    }.background(Color(uiColor: .systemGroupedBackground))
                                        .onChange(of: deepLinkedChangeID) { _, id in scroll(to: id, proxy: proxy) }
                                        .onChange(of: model.changes) { _, _ in scroll(to: deepLinkedChangeID, proxy: proxy) }
                                }
                                if let error = model.error { Label(error, systemImage: "wifi.slash").font(.caption).foregroundStyle(.orange).padding() }
                            }
                        }
                    }
                    .refreshable { await model.load(force: true) }
                    .onAppear { resolveInitialDate(from: model.changes) }
                    .onChange(of: model.changes) { _, values in
                        resolveInitialDate(from: values)
                    }
                    .navigationTitle("Изменения")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar { if model.isLoading { ToolbarItem(placement: .topBarTrailing) { ProgressView() } } }
                } else { ProgressView() }
            }
        }
        .task {
            if model == nil { model = ChangesViewModel(app: app, selection: selection) }
            await model?.load()
        }
    }
    private func visibleChanges(_ values: [ScheduleChange]) -> [ScheduleChange] {
        var filtered = scope == 0
            ? values.filter { $0.group.localizedCaseInsensitiveCompare(selection.group.name) == .orderedSame }
            : values

        if selectedDateKey != "__ALL__", selectedDateKey != "__AUTO__" {
            filtered = filtered.filter { dateKey($0.date) == selectedDateKey }
        }

        return filtered.sorted {
            $0.date == $1.date
                ? ($0.oldLesson ?? $0.newLesson ?? 0) < ($1.oldLesson ?? $1.newLesson ?? 0)
                : $0.date > $1.date
        }
    }

    private func availableDates(_ values: [ScheduleChange]) -> [Date] {
        let calendar = OmskCalendar.calendar
        let unique = Dictionary(
            grouping: values,
            by: { calendar.startOfDay(for: $0.date) }
        )
        return unique.keys.sorted(by: >)
    }

    @ViewBuilder
    private func datePicker(for values: [ScheduleChange]) -> some View {
        let dates = availableDates(values)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                dateChip(title: "Все дни", key: "__ALL__")

                ForEach(dates, id: \.self) { date in
                    dateChip(
                        title: OmskCalendar.calendar.isDateInToday(date) ? "Сегодня" : chipDate(date),
                        key: dateKey(date)
                    )
                }
            }
            .padding(.horizontal)
        }
        .animation(.snappy, value: selectedDateKey)
    }

    private func dateChip(title: String, key: String) -> some View {
        let selected = selectedDateKey == key
        return Button {
            withAnimation(.snappy) {
                selectedDateKey = key
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    selected ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(Color.secondary.opacity(selected ? 0 : 0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func resolveInitialDate(from values: [ScheduleChange]) {
        let dates = availableDates(values)
        guard !dates.isEmpty else {
            selectedDateKey = "__ALL__"
            return
        }

        let availableKeys = Set(dates.map(dateKey))
        if selectedDateKey != "__AUTO__",
           selectedDateKey == "__ALL__" || availableKeys.contains(selectedDateKey) {
            return
        }

        let today = dateKey(Date())
        selectedDateKey = availableKeys.contains(today)
            ? today
            : dateKey(dates[0])
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = OmskCalendar.calendar
        formatter.timeZone = OmskCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func chipDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = OmskCalendar.calendar
        formatter.timeZone = OmskCalendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func scroll(to id: String?, proxy: ScrollViewProxy) {
        guard let id,
              let change = model?.changes.first(where: { $0.stableID == id })
        else { return }

        withAnimation(.snappy) {
            scope = 1
            selectedDateKey = dateKey(change.date)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
        }
    }
}

private struct ChangeCard: View {
    let change: ScheduleChange
    var isHighlighted = false
    private var color: Color { change.isCancelled ? .red : change.isAdded ? .green : .orange }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(change.isCancelled ? "Отмена" : change.isAdded ? "Добавление" : "Изменение")
                    .font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
                Spacer()
                Text(formattedDate).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(change.group).font(.headline)
            HStack(alignment: .top, spacing: 12) {
                changeSide(title: "Было", lesson: change.oldLesson, room: change.oldRoom, subject: change.oldSubject, teacher: change.oldTeacher, faded: false)
                Rectangle().fill(.quaternary).frame(width: 1)
                changeSide(title: "Стало", lesson: change.newLesson, room: change.newRoom, subject: change.newSubject, teacher: change.newTeacher, faded: change.isCancelled)
            }.fixedSize(horizontal: false, vertical: true)
            if let reason = change.reason { Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(15).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(isHighlighted ? Color.blue : color.opacity(0.12), lineWidth: isHighlighted ? 2 : 1))
        .accessibilityElement(children: .combine)
        .id(change.id)
    }
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = OmskCalendar.calendar
        formatter.timeZone = OmskCalendar.timeZone
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: change.date)
    }
    private func changeSide(title: String, lesson: Int?, room: String?, subject: String?, teacher: String?, faded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            if let lesson { Text("\(lesson)-я пара").font(.caption.weight(.medium)) }
            if let subject, !subject.isEmpty { Text(subject).font(.subheadline.bold()) }
            if let room, !room.isEmpty { Text("Ауд. \(room)").font(.caption) }
            if let teacher, !teacher.isEmpty { Text(teacher).font(.caption).foregroundStyle(.secondary) }
            if title == "Стало", change.isCancelled { Text("Пара отменена").font(.subheadline.bold()).foregroundStyle(.red) }
            if title == "Было", change.isAdded { Text("Пары не было").font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).opacity(faded ? 0.75 : 1)
    }
}
