import XCTest
@testable import OATSchedule

final class OATParserTests: XCTestCase {
    private let parser = OATParser()
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testCategoriesAndGroupsComeFromSiteLinks() throws {
        let categories = try parser.categories(from: fixture("classes"))
        XCTAssertEqual(categories.validity, .success)
        XCTAssertEqual(categories.value.map(\.slug), ["ul_lenina_24", "ul_b_khmelnickogo_281a"])
        let groups = try parser.groups(from: fixture("groups"), category: categories.value[0])
        XCTAssertEqual(groups.value.map(\.name), ["ПР116", "КС215"])
        XCTAssertEqual(try parser.currentTeachingWeek(from: fixture("classes")), 2)
    }

    func testScheduleParsesWeeksTimesSubgroupsAndEmptyDays() throws {
        let category = CollegeCategory(title: "Корпус", slug: "ul_lenina_24", url: URL(string: "https://www.oat.ru/timetable/groups/ul_lenina_24")!)
        let group = StudentGroup(name: "ПР116", url: URL(string: "https://www.oat.ru/timetable/timetable/ul_lenina_24/ПР116")!, categoryID: category.id)
        let parsed = try parser.schedule(from: fixture("schedule"), group: group, currentWeek: 2)
        XCTAssertEqual(parsed.validity, .success)
        XCTAssertEqual(parsed.value.currentWeek, 2)
        XCTAssertEqual(parsed.value.lessons.first?.start, "08:00")
        XCTAssertEqual(parsed.value.lessons.first?.end, "09:30")
        let tuesday = parsed.value.lessons.filter { $0.week == 1 && $0.weekday == 3 }
        XCTAssertEqual(tuesday.count, 2)
        XCTAssertEqual(tuesday.map(\.subgroup), ["Подгруппа 1", "Подгруппа 2"])
        XCTAssertFalse(parsed.value.lessons.contains { $0.week == 1 && $0.weekday == 5 })
    }

    func testChangesIncludeReplacementAndCancellation() throws {
        let category = CollegeCategory(title: "Корпус 1", slug: "b1", url: URL(string: "https://www.oat.ru/timetable/Changes/b1")!)
        let parsed = try parser.changes(from: fixture("changes"), category: category, date: Date(timeIntervalSince1970: 1_791_331_200))
        XCTAssertEqual(parsed.value.count, 2)
        XCTAssertEqual(parsed.value[0].group, "ПР116")
        XCTAssertEqual(parsed.value[0].oldSubject, "Физика")
        XCTAssertEqual(parsed.value[0].newSubject, "Матем")
        XCTAssertTrue(parsed.value[1].isCancelled)
    }

    func testSnapshotDiffRecognizesUpdatedLesson() {
        let date = Date(timeIntervalSince1970: 1_791_331_200)
        func item(_ subject: String, _ room: String) -> ScheduleChange {
            ScheduleChange(stableID: "\(subject)-\(room)", categoryID: "b1", group: "ПР116", date: date, course: "1", oldLesson: 3, oldRoom: "304", oldSubject: subject, oldTeacher: "Иванов И.И.", reason: "пр/н", newLesson: 3, newRoom: room, newSubject: subject, newTeacher: "Иванов И.И.", rawText: "")
        }
        let diff = ChangeDiffEngine().diff(old: [item("Физика", "304")], new: [item("Математика", "215")])
        guard let first = diff.first, case let .updated(old, new) = first else { return XCTFail("Expected updated entry") }
        XCTAssertEqual(old.oldSubject, "Физика")
        XCTAssertEqual(new.newRoom, "215")
    }
}
