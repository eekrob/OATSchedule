import Foundation
import SwiftSoup
import CryptoKit
import OSLog

struct OATParser {
    private let logger = Logger(subsystem: "ru.oat.schedule", category: "parser")
    private let base = URL(string: "https://www.oat.ru")!
    private let timetableBase = URL(string: "https://www.oat.ru/timetable/")!
    private let classesPage = URL(string: "https://www.oat.ru/timetable/Classes")!
    private let changesPage = URL(string: "https://www.oat.ru/timetable/ClassesChanges")!

    func categories(from html: String) throws -> Parsed<[CollegeCategory]> {
        let doc = try SwiftSoup.parse(html)
        var seen = Set<String>()
        var result: [CollegeCategory] = []

        func append(title rawTitle: String, target rawTarget: String) {
            let title = normalize(rawTitle)
            guard !title.isEmpty,
                  !title.localizedCaseInsensitiveContains("выберите")
            else { return }

            guard let url = categoryURL(from: rawTarget) else { return }
            let slug = stableIdentifier(from: url, fallback: rawTarget + "|" + title)
            guard !slug.isEmpty, seen.insert(slug).inserted else { return }
            result.append(CollegeCategory(title: title, slug: slug, url: url))
        }

        // Old layout and any newer link/button layout.
        for element in try doc.select("a[href], [data-href], [data-url], [onclick]").array() {
            let title = try element.text()
            for target in try navigationTargets(from: element) where looksLikeCategoryTarget(target) {
                append(title: title, target: target)
            }
        }

        // Newer timetable pages may render buildings as <option> values and
        // navigate via JavaScript instead of exposing /timetable/groups links.
        let selects = try doc.select("select").array()
        for select in selects {
            let descriptor = [
                try select.attr("id"),
                try select.attr("name"),
                try select.attr("class")
            ].joined(separator: " ").lowercased()

            let options = try select.select("option").array()
            let values = try options.map { try $0.attr("value") }
            let relevant = descriptor.contains("group")
                || descriptor.contains("building")
                || descriptor.contains("corpus")
                || descriptor.contains("address")
                || descriptor.contains("class")
                || descriptor.contains("timetable")
                || values.contains(where: { looksLikeCategoryTarget($0) })
                || selects.count == 1

            guard relevant else { continue }

            for option in options {
                let value = try option.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)
                let title = try option.text()
                guard !value.isEmpty, value != "0", value != "-1" else { continue }
                append(title: title, target: value)
            }
        }

        return Parsed(value: result, validity: result.isEmpty ? .invalidStructure : .success)
    }

    func changeCategories(from html: String) throws -> Parsed<[CollegeCategory]> {
        let doc = try SwiftSoup.parse(html)
        var seen = Set<String>()
        var result: [CollegeCategory] = []

        for element in try doc.select("a[href], [data-href], [data-url], [onclick]").array() {
            let title = normalize(try element.text())
            guard !title.isEmpty else { continue }

            for rawTarget in try navigationTargets(from: element) {
                let lower = rawTarget.lowercased()
                guard lower.contains("changes/") else { continue }
                guard let url = resolve(rawTarget, relativeTo: changesPage) else { continue }

                let slug = url.pathComponents.last ?? ""
                guard slug.range(of: #"^b\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil,
                      seen.insert(slug.lowercased()).inserted
                else { continue }

                result.append(CollegeCategory(title: title, slug: slug, url: url))
            }
        }

        return Parsed(value: result, validity: result.isEmpty ? .invalidStructure : .success)
    }

    func currentTeachingWeek(from html: String) throws -> Int {
        let text = try SwiftSoup.parse(html).text()
        let regex = try NSRegularExpression(
            pattern: #"Расписание занятий\s*\(\s*(\d+)\s+учебн"#,
            options: [.caseInsensitive]
        )
        let ns = text as NSString
        guard let match = regex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: ns.length)
        ),
        match.numberOfRanges > 1,
        let absoluteWeek = Int(ns.substring(with: match.range(at: 1)))
        else {
            return 1
        }

        // The site header shows the absolute teaching week (for example 6),
        // while the timetable itself is split into alternating week 1 / week 2.
        // Convert 1,3,5... -> 1 and 2,4,6... -> 2.
        return ((max(1, absoluteWeek) - 1) % 2) + 1
    }

    func groups(from html: String, category: CollegeCategory) throws -> Parsed<[StudentGroup]> {
        let doc = try SwiftSoup.parse(html)
        var seen = Set<String>()
        var groups: [StudentGroup] = []

        func append(name rawName: String, target rawTarget: String) {
            let name = normalize(rawName)
            guard looksLikeGroupName(name), seen.insert(name).inserted else { return }
            guard let url = groupURL(from: rawTarget, category: category) else { return }
            groups.append(StudentGroup(name: name, url: url, categoryID: category.slug))
        }

        for element in try doc.select("a[href], [data-href], [data-url], [onclick]").array() {
            let name = try element.text()
            guard looksLikeGroupName(name) else { continue }
            let targets = try navigationTargets(from: element)
            for target in targets where looksLikeScheduleTarget(target) {
                append(name: name, target: target)
            }
        }

        let selects = try doc.select("select").array()
        for select in selects {
            let descriptor = [
                try select.attr("id"),
                try select.attr("name"),
                try select.attr("class")
            ].joined(separator: " ").lowercased()
            let options = try select.select("option").array()
            let relevant = descriptor.contains("group")
                || descriptor.contains("class")
                || descriptor.contains("schedule")
                || descriptor.contains("timetable")
                || selects.count == 1
            guard relevant else { continue }

            for option in options {
                let value = try option.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)
                let name = try option.text()
                guard !value.isEmpty, value != "0", value != "-1" else { continue }
                append(name: name, target: value)
            }
        }

        return Parsed(value: groups, validity: groups.isEmpty ? .invalidStructure : .success)
    }

    func schedule(from html: String, group: StudentGroup, currentWeek: Int = 1) throws -> Parsed<Schedule> {
        let doc = try SwiftSoup.parse(html)
        let tables = try doc.select("table").array()
        guard tables.count >= 2 else { throw AppFailure.invalidStructure }
        var lessons: [ScheduleLesson] = []
        for (tableIndex, table) in tables.prefix(2).enumerated() {
            let rows = try table.select("tr").array()
            guard let header = rows.first else { throw AppFailure.invalidStructure }
            let headers = try header.select("th,td").array().map { try $0.text() }
            guard headers.contains(where: { $0.localizedCaseInsensitiveContains("Понедельник") }) else { continue }
            let week = weekNumber(in: headers, fallback: tableIndex + 1)
            let weekdayColumns = headers.enumerated().compactMap { index, text -> (Int, Int)? in
                guard let day = weekday(from: text) else { return nil }
                return (index, day)
            }
            for row in rows.dropFirst() {
                let cells = try row.select("th,td").array()
                guard cells.count >= 3 else { continue }
                let number = Int(try cells[0].text().filter(\.isNumber)) ?? 0
                guard number > 0 else { continue }
                let times = try timeRanges(in: cells[1])
                for (column, weekday) in weekdayColumns where column < cells.count {
                    let items = try cellLines(cells[column])
                    guard !items.isEmpty else { continue }
                    let chunks = chunkLessons(items)
                        for chunk in chunks {
                        let time = times.first
                        let subject = chunk.first(where: { !looksLikeTeacher($0) && !looksLikeRoom($0) && !$0.localizedCaseInsensitiveContains("подгруппа") }) ?? chunk.first ?? "Занятие"
                        let teacher = chunk.first(where: looksLikeTeacher)
                        let room = chunk.first(where: looksLikeRoom)
                        let subgroup = chunk.first(where: { $0.localizedCaseInsensitiveContains("подгруппа") })
                        let extras = chunk.filter { $0 != subject && $0 != teacher && $0 != room && $0 != subgroup }
                        lessons.append(ScheduleLesson(week: week, weekday: weekday, number: number, start: time?.0 ?? "", end: time?.1 ?? "", subject: subject, teacher: teacher, room: room, subgroup: subgroup, extra: extras.isEmpty ? nil : extras.joined(separator: " · ")))
                    }
                }
            }
        }
        guard !lessons.isEmpty else { throw AppFailure.invalidStructure }
        return Parsed(value: Schedule(groupName: group.name, lessons: lessons, currentWeek: currentWeek, fetchedAt: Date()), validity: .success)
    }

    func changes(from html: String, category: CollegeCategory, date: Date) throws -> Parsed<[ScheduleChange]> {
        let doc = try SwiftSoup.parse(html)
        guard let table = try doc.select("table").array().first(where: { table in
            ((try? table.text()) ?? "").localizedCaseInsensitiveContains("Группа")
        }) else {
            let documentText = try doc.text()
            if documentText.localizedCaseInsensitiveContains("Изменения в расписании на") {
                return Parsed(value: [], validity: .emptyButValid)
            }
            throw AppFailure.invalidStructure
        }
        let rows = try table.select("tr").array()
        guard let header = rows.first else { throw AppFailure.invalidStructure }
        let headers = try header.select("th,td").array().map { normalize(try $0.text()).lowercased() }
        guard headers.contains(where: { $0.contains("групп") }), headers.contains(where: { $0.contains("причин") }) else { throw AppFailure.invalidStructure }
        func column(_ fragment: String, occurrence: Int = 0) -> Int? {
            let matches = headers.indices.filter { headers[$0].contains(fragment) }
            return matches.indices.contains(occurrence) ? matches[occurrence] : nil
        }
        let lessonColumns = headers.indices.filter { headers[$0].contains("пара") }
        let roomColumns = headers.indices.filter { headers[$0].contains("аудит") }
        let subjectColumns = headers.indices.filter { headers[$0].contains("дисциплин") }
        let teacherColumns = headers.indices.filter { headers[$0].contains("преподав") }
        guard let groupColumn = column("групп"), let reasonColumn = column("причин"),
              let oldLessonColumn = lessonColumns.first else { throw AppFailure.invalidStructure }
        let newLessonColumn = lessonColumns.dropFirst().first
        var records: [ScheduleChange] = []
        for row in rows.dropFirst() {
            let cells = try row.select("th,td").array().map { normalize(try $0.text()) }
            guard cells.count >= 8 else { continue }
            func value(_ index: Int) -> String? { index < cells.count && !cells[index].isEmpty ? cells[index] : nil }
            let group = value(groupColumn) ?? ""
            guard !group.isEmpty else { continue }
            let oldNo = intCell(value(oldLessonColumn))
            let oldRoom = roomColumns.first.flatMap(value)
            let oldSubject = subjectColumns.first.flatMap(value)
            let oldTeacher = teacherColumns.first.flatMap(value)
            let reason = value(reasonColumn)
            let newNo = newLessonColumn.flatMap(value).flatMap(intCell)
            let newRoom = roomColumns.dropFirst().first.flatMap(value)
            let newSubject = subjectColumns.dropFirst().first.flatMap(value)
            let newTeacher = teacherColumns.dropFirst().first.flatMap(value)
            let raw = cells.joined(separator: " | ")
            let key = [category.slug, dateKey(date), group, String(oldNo ?? newNo ?? 0), raw].joined(separator: "|")
            let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            records.append(ScheduleChange(stableID: digest, categoryID: category.slug, group: group, date: date, course: column("курс").flatMap(value), oldLesson: oldNo, oldRoom: oldRoom, oldSubject: oldSubject, oldTeacher: oldTeacher, reason: reason, newLesson: newNo, newRoom: newRoom, newSubject: newSubject, newTeacher: newTeacher, rawText: raw))
        }
        logger.debug("Parsed \(records.count) changes")
        return Parsed(value: records, validity: records.isEmpty ? .emptyButValid : .success)
    }

    func changeDates(from html: String, categoryID: String) throws -> [Date] {
        let doc = try SwiftSoup.parse(html)
        let links = try doc.select("a").array()
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = OmskCalendar.timeZone; parser.dateFormat = "dd.MM.yyyy"
        return Array(Set(try links.compactMap { link -> Date? in
            let text = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            return parser.date(from: text)
        })).sorted()
    }

    private func navigationTargets(from element: Element) throws -> [String] {
        let attributes = ["href", "data-href", "data-url", "value", "onclick"]
        var result: [String] = []

        for attribute in attributes {
            let raw = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }

            if attribute == "onclick" {
                if let range = raw.range(
                    of: #"https?://[^'"\s]+|/timetable/[^'";)\s]+"#,
                    options: .regularExpression
                ) {
                    result.append(String(raw[range]))
                }
            } else {
                result.append(raw)
            }
        }

        return Array(Set(result))
    }

    private func looksLikeCategoryTarget(_ raw: String) -> Bool {
        let value = raw.lowercased()
        guard !value.isEmpty else { return false }
        if value.contains("/timetable/classeschanges") { return false }
        if value.contains("/timetable/classes") && !value.contains("group") { return false }
        return value.contains("group")
            || value.contains("/timetable/") && (value.contains("building") || value.contains("corpus") || value.contains("address"))
    }

    private func looksLikeScheduleTarget(_ raw: String) -> Bool {
        let value = raw.lowercased()
        guard !value.isEmpty else { return false }
        if value.contains("/timetable/classeschanges") || value.contains("/timetable/classeschanges") { return false }
        if value.contains("/timetable/classes") && !value.contains("group") { return false }
        return value.contains("timetable/")
            || value.contains("group")
            || value.contains("schedule")
    }

    private func categoryURL(from raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.lowercased().hasPrefix("http") || value.hasPrefix("/") {
            return resolve(value, relativeTo: classesPage)
        }

        // oat.ru currently returns links such as "groups/ul_lenina_24"
        // instead of "/timetable/groups/ul_lenina_24".
        if value.lowercased().hasPrefix("groups/") {
            return resolve(value, relativeTo: timetableBase)
        }

        if value.contains("/") || value.hasPrefix(".") {
            return resolve(value, relativeTo: classesPage)
        }

        // A plain option value is treated as a building slug.
        guard value.range(of: #"^[A-Za-zА-Яа-яЁё0-9_.-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return timetableBase
            .appendingPathComponent("groups")
            .appendingPathComponent(value)
    }

    private func groupURL(from raw: String, category: CollegeCategory) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.lowercased().hasPrefix("http") || value.hasPrefix("/") {
            return resolve(value, relativeTo: category.url)
        }

        // A common server-rendered form is "timetable/<building>/<group>".
        // Resolve that from /timetable/ rather than from /timetable/groups/....
        if value.lowercased().hasPrefix("timetable/") {
            return resolve(value, relativeTo: timetableBase)
        }

        if value.contains("/") || value.hasPrefix(".") {
            return resolve(value, relativeTo: category.url)
        }

        guard value.range(of: #"^[A-Za-zА-Яа-яЁё0-9_.-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return timetableBase
            .appendingPathComponent("timetable")
            .appendingPathComponent(category.slug)
            .appendingPathComponent(value)
    }

    private func resolve(_ raw: String, relativeTo page: URL) -> URL? {
        URL(string: raw, relativeTo: page)?.absoluteURL
    }

    private func stableIdentifier(from url: URL, fallback: String) -> String {
        let last = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = ["groups", "group", "classes", "timetable", "schedule"]
        if !last.isEmpty, !generic.contains(last.lowercased()) {
            return last
        }

        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = items.compactMap(\.value).first(where: { !$0.isEmpty }) {
            return value
        }

        let normalized = fallback
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(normalized).split(separator: "-").filter { !$0.isEmpty }.joined(separator: "-")
    }

    private func looksLikeGroupName(_ text: String) -> Bool {
        let value = normalize(text)
        guard !value.isEmpty,
              !value.localizedCaseInsensitiveContains("выберите")
        else { return false }
        return value.contains(where: \.isLetter) && value.contains(where: \.isNumber)
    }

    private func weekday(from header: String) -> Int? {
        let value = header.lowercased()
        let names = [("понедельник", 2), ("вторник", 3), ("среда", 4), ("четверг", 5), ("пятница", 6), ("суббота", 7), ("воскресенье", 1)]
        return names.first(where: { value.contains($0.0) })?.1
    }
    private func weekNumber(in headers: [String], fallback: Int) -> Int { headers.first(where: { $0.contains("-") })?.split(separator: "-").last.flatMap { Int($0) } ?? fallback }
    private func timeRanges(in cell: Element) throws -> [(String, String)] {
        let markup = try cell.html().replacingOccurrences(of: #">\s*<"#, with: "> <", options: .regularExpression)
        let text = try SwiftSoup.parseBodyFragment(markup).text()
        let regex = try NSRegularExpression(pattern: #"\d{1,2}:\d{2}"#)
        let ns = text as NSString
        let values = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        return stride(from: 0, to: values.count - 1, by: 2).map { (values[$0], values[$0 + 1]) }
    }
    private func cellLines(_ cell: Element) throws -> [String] {
        var html = try cell.html()
        html = html.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "__OAT_LINE__", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?i)</(div|p|li)>"#, with: "__OAT_LINE__", options: .regularExpression)
        let clean = try SwiftSoup.parseBodyFragment(html).body()?.text() ?? ""
        return clean.components(separatedBy: "__OAT_LINE__").map(normalize).filter { !$0.isEmpty }
    }
    private func chunkLessons(_ lines: [String]) -> [[String]] {
        guard lines.count > 3, lines.contains(where: { $0.localizedCaseInsensitiveContains("подгруппа") }) else { return [lines] }
        let subject = lines.first(where: { !$0.localizedCaseInsensitiveContains("подгруппа") && !looksLikeTeacher($0) && !looksLikeRoom($0) }) ?? "Занятие"
        let markers = lines.indices.filter { lines[$0].localizedCaseInsensitiveContains("подгруппа") }
        return markers.enumerated().map { index, start in
            let end = index + 1 < markers.count ? markers[index + 1] : lines.endIndex
            return [subject] + Array(lines[start..<end])
        }
    }
    private func looksLikeTeacher(_ text: String) -> Bool { text.range(of: #"^[А-ЯЁ][а-яё]+\s+[А-ЯЁ]\.\s*[А-ЯЁ]?\.?$"#, options: .regularExpression) != nil }
    private func looksLikeRoom(_ text: String) -> Bool { text.range(of: #"^(\d{2,4}[а-яА-Я]?\+?|спортзал|стадион)$"#, options: [.regularExpression, .caseInsensitive]) != nil }
    private func normalize(_ text: String) -> String { text.replacingOccurrences(of: "\u{00a0}", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
    private func intCell(_ text: String?) -> Int? { text.flatMap { Int($0.filter(\.isNumber)) } }
    private func dateKey(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = OmskCalendar.timeZone; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
}

private extension String {
    func absoluteURL(relativeTo baseURL: URL) throws -> URL {
        guard let url = URL(string: self, relativeTo: baseURL)?.absoluteURL else { throw AppFailure.badResponse }
        return url
    }
}
