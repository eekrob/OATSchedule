import Foundation

struct CollegeCategory: Identifiable, Hashable, Codable {
    var id: String { slug }
    let title: String
    let slug: String
    let url: URL
}

struct StudentGroup: Identifiable, Hashable, Codable {
    var id: String { "\(categoryID)|\(name)" }
    let name: String
    let url: URL
    let categoryID: String
}

struct UserSelection: Codable, Hashable {
    let category: CollegeCategory
    let group: StudentGroup
}

struct ScheduleLesson: Identifiable, Codable, Hashable {
    var id: String { "\(week)-\(weekday)-\(number)-\(subject)-\(subgroup ?? "")" }
    let week: Int
    let weekday: Int // Calendar weekday: Monday = 2 … Sunday = 1
    let number: Int
    let start: String
    let end: String
    let subject: String
    let teacher: String?
    let room: String?
    let subgroup: String?
    let extra: String?
}

struct Schedule: Codable, Hashable {
    let groupName: String
    let lessons: [ScheduleLesson]
    let currentWeek: Int
    let fetchedAt: Date
}

struct ScheduleChange: Identifiable, Codable, Hashable {
    var id: String { stableID }
    let stableID: String
    let categoryID: String
    let group: String
    let date: Date
    let course: String?
    let oldLesson: Int?
    let oldRoom: String?
    let oldSubject: String?
    let oldTeacher: String?
    let reason: String?
    let newLesson: Int?
    let newRoom: String?
    let newSubject: String?
    let newTeacher: String?
    let rawText: String

    var isCancelled: Bool { [newRoom, newSubject, reason].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains("отмена") } }
    var isAdded: Bool { oldLesson == nil || [oldRoom, oldSubject, reason].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains("отмена") } }
}

enum ChangeDelta: Equatable {
    case added(ScheduleChange)
    case updated(old: ScheduleChange, new: ScheduleChange)
    case removed(ScheduleChange)
}

enum ParserValidity: Equatable { case success, emptyButValid, invalidStructure }

struct Parsed<Value> {
    let value: Value
    let validity: ParserValidity
}

enum AppFailure: LocalizedError {
    case badResponse, network, http(Int), invalidStructure, noData
    var errorDescription: String? {
        switch self {
        case .badResponse: "Не удалось прочитать ответ сайта."
        case .network: "Проверьте подключение к интернету и попробуйте ещё раз."
        case .http(403): "Сайт временно ограничил запросы. Попробуйте позже."
        case .http(404): "Страница не найдена. Обновите список групп."
        case .http(429): "Слишком много запросов. Попробуйте позже."
        case .http: "Сайт временно недоступен. Попробуйте позже."
        case .invalidStructure: "Структура страницы расписания изменилась. Кеш сохранён."
        case .noData: "Для выбранного раздела пока нет данных."
        }
    }
}

enum OmskCalendar {
    static let timeZone = TimeZone(identifier: "Asia/Omsk") ?? .gmt
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "ru_RU")
        value.timeZone = timeZone
        value.firstWeekday = 2
        return value
    }
}
