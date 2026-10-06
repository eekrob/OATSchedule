import Foundation
import SwiftData
import Observation
import UserNotifications
import OSLog

@Model
final class CachedDocument {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date
    init(key: String, payload: Data, updatedAt: Date = .now) { self.key = key; self.payload = payload; self.updatedAt = updatedAt }
}

@MainActor
final class LocalStore {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    init(context: ModelContext) { self.context = context }

    func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let descriptor = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
        guard let record = try? context.fetch(descriptor).first else { return nil }
        return try? decoder.decode(T.self, from: record.payload)
    }
    func write<T: Encodable>(_ value: T, key: String) {
        guard let payload = try? encoder.encode(value) else { return }
        let descriptor = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
        if let record = try? context.fetch(descriptor).first {
            record.payload = payload; record.updatedAt = .now
        } else { context.insert(CachedDocument(key: key, payload: payload)) }
        try? context.save()
    }
    func remove(key: String) {
        let descriptor = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
        if let record = try? context.fetch(descriptor).first { context.delete(record); try? context.save() }
    }
}

protocol ScheduleServiceProtocol {
    func loadCategories() async throws -> [CollegeCategory]
    func loadGroups(in category: CollegeCategory) async throws -> [StudentGroup]
    func loadSchedule(for group: StudentGroup) async throws -> Schedule
}
protocol ChangesServiceProtocol {
    func loadCategories() async throws -> [CollegeCategory]
    func loadChanges(in category: CollegeCategory) async throws -> [ScheduleChange]
}
protocol NotificationServiceProtocol {
    func requestAuthorization() async -> Bool
    func notify(_ change: ScheduleChange) async
}

struct MockScheduleService: ScheduleServiceProtocol {
    let schedule: Schedule
    let categories: [CollegeCategory]
    let groups: [StudentGroup]
    func loadCategories() async throws -> [CollegeCategory] { categories }
    func loadGroups(in category: CollegeCategory) async throws -> [StudentGroup] { groups.filter { $0.categoryID == category.id } }
    func loadSchedule(for group: StudentGroup) async throws -> Schedule { schedule }
}

struct MockChangesService: ChangesServiceProtocol {
    let categories: [CollegeCategory]
    let changes: [ScheduleChange]
    func loadCategories() async throws -> [CollegeCategory] { categories }
    func loadChanges(in category: CollegeCategory) async throws -> [ScheduleChange] { changes.filter { $0.categoryID == category.id } }
}

struct MockNotificationService: NotificationServiceProtocol {
    func requestAuthorization() async -> Bool { true }
    func notify(_ change: ScheduleChange) async { }
}

struct OATScheduleService: ScheduleServiceProtocol {
    let http: HTTPClient; let parser: OATParser
    private let root = URL(string: "https://www.oat.ru/timetable/Classes")!
    func loadCategories() async throws -> [CollegeCategory] {
        let html = try await http.html(from: root)
        let parsed = try parser.categories(from: html)
        guard parsed.validity != .invalidStructure else { throw AppFailure.invalidStructure }
        return parsed.value
    }
    func loadGroups(in category: CollegeCategory) async throws -> [StudentGroup] {
        let html = try await http.html(from: category.url)
        let parsed = try parser.groups(from: html, category: category)
        guard parsed.validity != .invalidStructure else { throw AppFailure.invalidStructure }
        return parsed.value
    }
    func loadSchedule(for group: StudentGroup) async throws -> Schedule {
        let index = try await http.html(from: root)
        let week = try parser.currentTeachingWeek(from: index)
        let scheduleHTML = try await http.html(from: group.url)
        let parsed = try parser.schedule(from: scheduleHTML, group: group, currentWeek: week)
        guard parsed.validity == .success else { throw AppFailure.invalidStructure }
        return parsed.value
    }
}

struct OATChangesService: ChangesServiceProtocol {
    let http: HTTPClient; let parser: OATParser
    private let root = URL(string: "https://www.oat.ru/timetable/ClassesChanges")!
    func loadCategories() async throws -> [CollegeCategory] {
        let html = try await http.html(from: root)
        let parsed = try parser.changeCategories(from: html)
        guard parsed.validity != .invalidStructure else { throw AppFailure.invalidStructure }
        return parsed.value
    }
    func loadChanges(in category: CollegeCategory) async throws -> [ScheduleChange] {
        let indexHTML = try await http.html(from: category.url)
        let dates = try parser.changeDates(from: indexHTML, categoryID: category.slug)
        guard !dates.isEmpty else { throw AppFailure.invalidStructure }
        let base = URL(string: "https://www.oat.ru/timetable/Changes/\(category.slug)")!
        var all: [ScheduleChange] = []
        // Fetch only currently posted dates. Sequential requests avoid hammering the college site.
        for date in dates {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = OmskCalendar.timeZone; formatter.dateFormat = "dd.MM.yyyy"
            let url = base.appendingPathComponent(formatter.string(from: date))
            let html = try await http.html(from: url)
            let parsed = try parser.changes(from: html, category: category, date: date)
            guard parsed.validity != .invalidStructure else { throw AppFailure.invalidStructure }
            all.append(contentsOf: parsed.value)
        }
        return all
    }
}

struct ChangeDiffEngine {
    func diff(old: [ScheduleChange], new: [ScheduleChange]) -> [ChangeDelta] {
        let oldByID = Dictionary(old.map { (logicalKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(new.map { (logicalKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        var result: [ChangeDelta] = []
        for key in Set(oldByID.keys).union(newByID.keys).sorted() {
            switch (oldByID[key], newByID[key]) {
            case let (old?, new?) where old != new: result.append(.updated(old: old, new: new))
            case let (nil, new?): result.append(.added(new))
            case let (old?, nil): result.append(.removed(old))
            default: break
            }
        }
        return result
    }
    private func logicalKey(_ item: ScheduleChange) -> String { "\(item.categoryID)|\(item.group)|\(item.date.timeIntervalSince1970)|\(item.oldLesson ?? item.newLesson ?? 0)|\(item.reason ?? "")" }
}

@MainActor
@Observable
final class AppContainer {
    let scheduleService: any ScheduleServiceProtocol
    let changesService: any ChangesServiceProtocol
    let store: LocalStore
    let notifications: any NotificationServiceProtocol
    init(
        context: ModelContext,
        scheduleService: (any ScheduleServiceProtocol)? = nil,
        changesService: (any ChangesServiceProtocol)? = nil,
        notificationService: (any NotificationServiceProtocol)? = nil
    ) {
        let client = HTTPClient(); let parser = OATParser()
        self.scheduleService = scheduleService ?? OATScheduleService(http: client, parser: parser)
        self.changesService = changesService ?? OATChangesService(http: client, parser: parser)
        self.store = LocalStore(context: context)
        self.notifications = notificationService ?? LocalNotificationService()
    }

    func refresh(selection: UserSelection) async {
        async let scheduleTask: Void = refreshSchedule(selection: selection)
        async let changesTask: Void = refreshChanges(selection: selection)
        _ = await (scheduleTask, changesTask)
    }

    private func refreshSchedule(selection: UserSelection) async {
        do {
            let schedule = try await scheduleService.loadSchedule(for: selection.group)
            store.write(schedule, key: "schedule|\(selection.group.id)")
        } catch { Logger(subsystem: "ru.oat.schedule", category: "schedule").error("Background refresh failed") }
    }

    private func refreshChanges(selection: UserSelection) async {
        do {
            let scheduleCategories = try await scheduleService.loadCategories()
            let changeCategories = try await changesService.loadCategories()
            guard let index = scheduleCategories.firstIndex(where: { $0.id == selection.category.id }), changeCategories.indices.contains(index) else { return }
            let category = changeCategories[index]
            let key = "changes|\(category.id)"
            let fresh = try await changesService.loadChanges(in: category)
            let previous = store.read([ScheduleChange].self, key: key)
            if previous?.isEmpty == false && fresh.isEmpty { return } // A suddenly empty page is suspicious; keep the last good snapshot.
            store.write(fresh, key: key)
            guard let previous else { return } // First load is a quiet baseline.
            let groupKey = selection.group.name.filter { $0.isLetter || $0.isNumber }.uppercased()
            let deltas = ChangeDiffEngine().diff(old: previous, new: fresh)
            for delta in deltas {
                let change: ScheduleChange
                switch delta {
                case .added(let value): change = value
                case .updated(_, let value): change = value
                case .removed: continue
                }
                guard change.group.filter({ $0.isLetter || $0.isNumber }).uppercased() == groupKey else { continue }
                let sentKey = "notified|\(change.stableID)"
                guard store.read(Bool.self, key: sentKey) != true else { continue }
                await notifications.notify(change)
                store.write(true, key: sentKey)
            }
        } catch { Logger(subsystem: "ru.oat.schedule", category: "changes").error("Changes refresh failed") }
    }
}

struct LocalNotificationService: NotificationServiceProtocol {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    func notify(_ change: ScheduleChange) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Изменение расписания · \(change.group)"
        let lesson = change.newLesson ?? change.oldLesson ?? 0
        if change.isCancelled { content.body = "\(lesson)-я пара отменена" }
        else if let subject = change.newSubject { content.body = "\(lesson)-я пара · \(subject)" }
        else { content.body = "\(lesson)-я пара · \(change.reason ?? "есть обновление")" }
        content.sound = .default
        content.userInfo = ["changeID": change.stableID, "group": change.group]
        let request = UNNotificationRequest(identifier: change.stableID, content: content, trigger: nil)
        try? await center.add(request)
    }
}

