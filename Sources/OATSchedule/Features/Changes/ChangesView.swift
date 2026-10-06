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
    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    VStack(spacing: 0) {
                        Picker("Фильтр", selection: $scope) {
                            Text("Моя группа").tag(0); Text("Все").tag(1)
                        }.pickerStyle(.segmented).padding(.horizontal).padding(.top, 10).padding(.bottom, 6)
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
                                            }
                                        }.padding(.horizontal).padding(.vertical, 8)
                                    }.background(Color(uiColor: .systemGroupedBackground))
                                        .onChange(of: deepLinkedChangeID) { _, id in scroll(to: id, proxy: proxy) }
                                        .onChange(of: model.changes) { _, _ in scroll(to: deepLinkedChangeID, proxy: proxy) }
                                }
                                if let error = model.error { Label(error, systemImage: "wifi.slash").font(.caption).foregroundStyle(.orange).padding() }
                            }
                        }
                    }
                    .refreshable { await model.load(force: true) }
                    .navigationTitle("Изменения")
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
        let filtered = scope == 0 ? values.filter { $0.group.localizedCaseInsensitiveCompare(selection.group.name) == .orderedSame } : values
        return filtered.sorted { $0.date == $1.date ? ($0.oldLesson ?? 0) < ($1.oldLesson ?? 0) : $0.date > $1.date }
    }
    private func scroll(to id: String?, proxy: ScrollViewProxy) {
        guard let id, model?.changes.contains(where: { $0.stableID == id }) == true else { return }
        scope = 1
        Task { try? await Task.sleep(for: .milliseconds(200)); withAnimation { proxy.scrollTo(id, anchor: .center) } }
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
        .padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(isHighlighted ? Color.indigo : .clear, lineWidth: 2))
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

