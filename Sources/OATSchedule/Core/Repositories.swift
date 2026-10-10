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
    let http: HTTPClient
    let parser: OATParser
    private let root = URL(string: "https://www.oat.ru/timetable/Classes")!

    private var testMode: Bool { UserDefaults.standard.bool(forKey: "testMode") }

    func loadCategories() async throws -> [CollegeCategory] {
        if testMode { return [DemoData.category] }
        let html = try await http.html(from: root)
        let parsed = try parser.categories(from: html)
        guard parsed.validity != .invalidStructure else { throw AppFailure.invalidStructure }
        return parsed.value
    }

    func loadGroups(in category: CollegeCategory) async throws -> [StudentGroup] {
        if testMode || category.id == DemoData.category.id { return DemoData.groups }
        let html = try await http.html(from: category.url)
        let parsed = try parser.groups(from: html, category: category)
        guard parsed.validity != .invalidStructure else { throw AppFailure.invalidStructure }
        return parsed.value
    }

    func loadSchedule(for group: StudentGroup) async throws -> Schedule {
        if testMode || group.categoryID == DemoData.category.id { return DemoData.schedule(for: group) }
        let index = try await http.html(from: root)
        let week = try parser.currentTeachingWeek(from: index)
        let scheduleHTML = try await http.html(from: group.url)
        let parsed = try parser.schedule(from: scheduleHTML, group: group, currentWeek: week)
        guard parsed.validity == .success else { throw AppFailure.invalidStructure }
        return parsed.value
    }
}

struct OATChangesService: ChangesServiceProtocol {
    let http: HTTPClient
    let parser: OATParser
    private let root = URL(string: "https://www.oat.ru/timetable/ClassesChanges")!

    private var testMode: Bool { UserDefaults.standard.bool(forKey: "testMode") }
    private var demoGroupName: String {
        if let selectionData = UserDefaults.standard.data(forKey: "demoSelection"),
           let selection = try? JSONDecoder().decode(UserSelection.self, from: selectionData) {
            return selection.group.name
        }
        return DemoData.groups.first?.name ?? "ПР-116"
    }

    func loadCategories() async throws -> [CollegeCategory] {
        if testMode { return [DemoData.category] }
        let html = try await http.html(from: root)
        let parsed = try parser.changeCategories(from: html)
        guard parsed.validity != .invalidStructure else { throw AppFailure.invalidStructure }
        return parsed.value
    }

    func loadChanges(in category: CollegeCategory) async throws -> [ScheduleChange] {
        if testMode || category.id == DemoData.category.id {
            return DemoData.changes(categoryID: category.id, groupName: demoGroupName)
        }

        // The live OAT page exposes real date URLs directly:
        // /timetable/Changes/b1/12.10.2026
        // Each date URL returns the complete server-rendered table, so there is
        // no reason to emulate the Blazor WebSocket circuit in the app.
        let indexHTML = try await http.html(from: category.url)
        let pages = try parser.changePages(from: indexHTML, category: category)

        var all: [ScheduleChange] = []
        var successfulPages = 0
        var lastError: Error?

        // Also parse the category page itself. On oat.ru it already contains
        // the currently selected day's full table.
        if let currentDate = try parser.changePageDate(from: indexHTML) {
            do {
                let parsed = try parser.changes(
                    from: indexHTML,
                    category: category,
                    date: currentDate
                )
                if parsed.validity != .invalidStructure {
                    successfulPages += 1
                    all.append(contentsOf: parsed.value)
                }
            } catch {
                lastError = error
            }
        }

        for page in pages {
            do {
                let html = try await http.html(from: page.url)
                let parsed = try parser.changes(
                    from: html,
                    category: category,
                    date: page.date
                )
                guard parsed.validity != .invalidStructure else {
                    throw AppFailure.invalidStructure
                }

                successfulPages += 1
                all.append(contentsOf: parsed.value)
            } catch {
                lastError = error
                await NetworkDiagnosticsStore.shared.recordAppEvent(
                    "CHANGE PAGE FAILED",
                    details: "URL: \(page.url.absoluteString) · \(error.localizedDescription)"
                )
            }
        }

        guard successfulPages > 0 else {
            throw lastError ?? AppFailure.invalidStructure
        }

        let unique = Dictionary(
            all.map { ($0.stableID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return unique.values.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.group != $1.group { return $0.group < $1.group }
            return ($0.oldLesson ?? $0.newLesson ?? 0) < ($1.oldLesson ?? $1.newLesson ?? 0)
        }
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
    private func logicalKey(_ item: ScheduleChange) -> String {
        "\(item.categoryID)|\(item.group)|\(item.date.timeIntervalSince1970)|\(item.oldLesson ?? item.newLesson ?? 0)|\(item.reason ?? "")"
    }
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
        let client = HTTPClient()
        let parser = OATParser()
        self.scheduleService = scheduleService ?? OATScheduleService(http: client, parser: parser)
        self.changesService = changesService ?? OATChangesService(http: client, parser: parser)
        self.store = LocalStore(context: context)
        self.notifications = notificationService ?? LocalNotificationService()
    }

    func refresh(selection: UserSelection) async {
        if UserDefaults.standard.bool(forKey: "testMode"),
           let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: "demoSelection")
        }
        async let scheduleTask: Void = refreshSchedule(selection: selection)
        async let changesTask: Void = refreshChanges(selection: selection)
        _ = await (scheduleTask, changesTask)
    }

    private func refreshSchedule(selection: UserSelection) async {
        do {
            let schedule = try await scheduleService.loadSchedule(for: selection.group)
            store.write(schedule, key: "schedule|\(selection.group.id)")
        } catch {
            Logger(subsystem: "ru.oat.schedule", category: "schedule").error("Background refresh failed")
        }
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
            if previous?.isEmpty == false && fresh.isEmpty { return }
            store.write(fresh, key: key)
            guard let previous else { return }
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
        } catch {
            Logger(subsystem: "ru.oat.schedule", category: "changes").error("Changes refresh failed")
        }
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
