import Foundation

/// Safe local data used only when oat.ru cannot provide any usable data.
/// Test mode is intentionally obvious in the UI so demo information is never
/// mistaken for the real college timetable.
enum DemoData {
    static let category = CollegeCategory(
        title: "ул. Ленина, 24",
        slug: "demo-lenina-24",
        url: URL(string: "https://www.oat.ru/timetable/groups/demo-lenina-24")!
    )

    static let groups: [StudentGroup] = ["ПР-116", "ПР-216", "ПР-316", "ПР-416"].map {
        StudentGroup(
            name: $0,
            url: URL(string: "https://www.oat.ru/timetable/group/demo-\($0.lowercased())")!,
            categoryID: category.id
        )
    }

    static func schedule(for group: StudentGroup) -> Schedule {
        Schedule(
            groupName: group.name,
            lessons: [
                lesson(weekday: 2, number: 1, start: "08:30", end: "10:00", subject: "Математика", teacher: "Иванов И.И.", room: "215"),
                lesson(weekday: 2, number: 2, start: "10:10", end: "11:40", subject: "Физика", teacher: "Петров А.А.", room: "304"),
                lesson(weekday: 2, number: 3, start: "12:20", end: "13:50", subject: "Информатика", teacher: "Сидоров С.П.", room: "302"),
                lesson(weekday: 3, number: 1, start: "08:30", end: "10:00", subject: "Английский язык", teacher: "Смирнова Е.В.", room: "210"),
                lesson(weekday: 3, number: 2, start: "10:10", end: "11:40", subject: "Математика", teacher: "Иванов И.И.", room: "215"),
                lesson(weekday: 3, number: 3, start: "12:20", end: "13:50", subject: "Основы программирования", teacher: "Кузнецов Д.А.", room: "307"),
                lesson(weekday: 4, number: 2, start: "10:10", end: "11:40", subject: "Физика", teacher: "Петров А.А.", room: "304"),
                lesson(weekday: 4, number: 3, start: "12:20", end: "13:50", subject: "Основы программирования", teacher: "Кузнецов Д.А.", room: "307"),
                lesson(weekday: 5, number: 1, start: "08:30", end: "10:00", subject: "Математика", teacher: "Иванов И.И.", room: "215"),
                lesson(weekday: 5, number: 2, start: "10:10", end: "11:40", subject: "Информатика", teacher: "Сидоров С.П.", room: "302"),
                lesson(weekday: 6, number: 2, start: "10:10", end: "11:40", subject: "Английский язык", teacher: "Смирнова Е.В.", room: "210")
            ],
            currentWeek: 1,
            fetchedAt: .now
        )
    }

    static func changes(categoryID: String, groupName: String) -> [ScheduleChange] {
        [
            ScheduleChange(
                stableID: "demo-change-1-\(normalized(groupName))",
                categoryID: categoryID,
                group: groupName,
                date: day(1),
                course: nil,
                oldLesson: 2,
                oldRoom: "215",
                oldSubject: "Математика",
                oldTeacher: "Иванов И.И.",
                reason: "Замена занятия",
                newLesson: 2,
                newRoom: "302",
                newSubject: "Информатика",
                newTeacher: "Сидоров С.П.",
                rawText: "Тестовое изменение расписания"
            ),
            ScheduleChange(
                stableID: "demo-change-2-\(normalized(groupName))",
                categoryID: categoryID,
                group: groupName,
                date: day(2),
                course: nil,
                oldLesson: 3,
                oldRoom: "304",
                oldSubject: "Физика",
                oldTeacher: "Петров А.А.",
                reason: "Отмена занятия",
                newLesson: nil,
                newRoom: nil,
                newSubject: nil,
                newTeacher: nil,
                rawText: "Тестовая отмена занятия"
            )
        ]
    }

    private static func lesson(
        weekday: Int,
        number: Int,
        start: String,
        end: String,
        subject: String,
        teacher: String,
        room: String
    ) -> ScheduleLesson {
        ScheduleLesson(
            week: 1,
            weekday: weekday,
            number: number,
            start: start,
            end: end,
            subject: subject,
            teacher: teacher,
            room: room,
            subgroup: nil,
            extra: nil
        )
    }

    private static func day(_ offset: Int) -> Date {
        let today = OmskCalendar.calendar.startOfDay(for: Date())
        return OmskCalendar.calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private static func normalized(_ value: String) -> String {
        value.filter { $0.isLetter || $0.isNumber }.lowercased()
    }
}

struct DemoScheduleService: ScheduleServiceProtocol {
    let categories: [CollegeCategory]
    let groups: [StudentGroup]

    func loadCategories() async throws -> [CollegeCategory] { categories }

    func loadGroups(in category: CollegeCategory) async throws -> [StudentGroup] {
        groups.filter { $0.categoryID == category.id }
    }

    func loadSchedule(for group: StudentGroup) async throws -> Schedule {
        DemoData.schedule(for: group)
    }
}

struct DemoChangesService: ChangesServiceProtocol {
    let categories: [CollegeCategory]
    let groupName: String

    func loadCategories() async throws -> [CollegeCategory] { categories }

    func loadChanges(in category: CollegeCategory) async throws -> [ScheduleChange] {
        DemoData.changes(categoryID: category.id, groupName: groupName)
    }
}
