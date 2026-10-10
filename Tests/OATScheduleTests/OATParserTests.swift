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

    func testRelativeCategoryLinksFromLiveSiteShape() throws {
        let html = """
        <html><body>
          <a href="groups/ul_lenina_24">Корпус 1 | ул. Ленина, 24</a>
          <a href="groups/ul_b_khmelnickogo_281a">Корпус 2 | ул. Б. Хмельницкого, 281а</a>
        </body></html>
        """
        let parsed = try parser.categories(from: html)
        XCTAssertEqual(parsed.validity, .success)
        XCTAssertEqual(parsed.value.map(\.slug), ["ul_lenina_24", "ul_b_khmelnickogo_281a"])
        XCTAssertEqual(parsed.value.first?.url.absoluteString, "https://www.oat.ru/timetable/groups/ul_lenina_24")
    }

    func testRelativeGroupRouteResolvesFromTimetableRoot() throws {
        let category = CollegeCategory(
            title: "Корпус 1",
            slug: "ul_lenina_24",
            url: URL(string: "https://www.oat.ru/timetable/groups/ul_lenina_24")!
        )
        let html = """
        <html><body>
          <a href="timetable/ul_lenina_24/%D0%9F%D0%A0116">ПР116</a>
        </body></html>
        """
        let parsed = try parser.groups(from: html, category: category)
        XCTAssertEqual(parsed.validity, .success)
        XCTAssertEqual(parsed.value.first?.name, "ПР116")
        XCTAssertEqual(
            parsed.value.first?.url.absoluteString,
            "https://www.oat.ru/timetable/timetable/ul_lenina_24/%D0%9F%D0%A0116"
        )
    }

    func testAbsoluteTeachingWeekMapsToTwoWeekTimetableCycle() throws {
        let week6 = """
        <html><body><h1>Расписание занятий (6 учебная неделя)</h1></body></html>
        """
        let week7 = """
        <html><body><h1>Расписание занятий (7 учебная неделя)</h1></body></html>
        """

        XCTAssertEqual(try parser.currentTeachingWeek(from: week6), 2)
        XCTAssertEqual(try parser.currentTeachingWeek(from: week7), 1)
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

    func testRenderedChangeDateLinksAreResolved() throws {
        let category = CollegeCategory(
            title: "Корпус 1",
            slug: "b1",
            url: URL(string: "https://www.oat.ru/timetable/Changes/b1")!
        )
        let html = """
        <html><body>
          <a href="07.10.2026">07.10.2026</a>
          <button>08.10.2026</button>
        </body></html>
        """

        let pages = try parser.changePages(from: html, category: category)
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(
            pages.contains {
                $0.url.absoluteString == "https://www.oat.ru/timetable/Changes/b1/07.10.2026"
            }
        )
        XCTAssertTrue(
            pages.contains {
                $0.url.absoluteString == "https://www.oat.ru/timetable/Changes/b1/08.10.2026"
            }
        )
    }

    func testLiveChangeDateLinksUseDirectServerPages() throws {
        let category = CollegeCategory(
            title: "Корпус 1",
            slug: "b1",
            url: URL(string: "https://www.oat.ru/timetable/Changes/b1")!
        )
        let html = """
        <html><body>
          <h2>Изменения в расписании на 12 октября (понедельник)</h2>
          <a class="choose-item" href="/timetable/Changes/b1/10.10.2026">10.10.2026</a>
          <a class="choose-item active" href="/timetable/Changes/b1/12.10.2026">12.10.2026</a>
        </body></html>
        """

        let pages = try parser.changePages(from: html, category: category)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(
            pages.first?.url.absoluteString,
            "https://www.oat.ru/timetable/Changes/b1/12.10.2026"
        )
    }

    func testChangePageDatePrefersActiveHeadingOverDatePicker() throws {
        let html = """
        <html><body>
          <h2 class="section-title">Изменения в расписании на 12 октября (понедельник)</h2>
          <a href="/timetable/Changes/b1/02.10.2026">02.10.2026</a>
          <a href="/timetable/Changes/b1/12.10.2026">12.10.2026</a>
        </body></html>
        """
        let date = try XCTUnwrap(parser.changePageDate(from: html))
        let components = OmskCalendar.calendar.dateComponents([.day, .month], from: date)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.month, 10)
    }

    func testRenderedChangePageDateSupportsRussianHeading() throws {
        let html = """
        <html><body><h1>Изменения в расписании на 07 октября (среда)</h1></body></html>
        """
        let date = try XCTUnwrap(parser.changePageDate(from: html))
        let components = OmskCalendar.calendar.dateComponents([.day, .month], from: date)
        XCTAssertEqual(components.day, 7)
        XCTAssertEqual(components.month, 10)
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
