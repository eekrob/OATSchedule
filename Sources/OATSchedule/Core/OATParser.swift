import Foundation
import SwiftSoup
import CryptoKit
import OSLog

struct OATParser {
    private let logger = Logger(subsystem: "ru.oat.schedule", category: "parser")
    private let base = URL(string: "https://www.oat.ru")!

    func categories(from html: String) throws -> Parsed<[CollegeCategory]> {
        let doc = try SwiftSoup.parse(html)
        let links = try doc.select("a[href*=/timetable/groups/]").array()
        var seen = Set<String>()
        let result = try links.compactMap { link -> CollegeCategory? in
            let url = try link.attr("href").absoluteURL(relativeTo: base)
            let slug = url.lastPathComponent
            guard !slug.isEmpty, seen.insert(slug).inserted else { return nil }
            let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return CollegeCategory(title: title, slug: slug, url: url)
        }
        return Parsed(value: result, validity: result.isEmpty ? .invalidStructure : .success)
    }

    func changeCategories(from html: String) throws -> Parsed<[CollegeCategory]> {
        let doc = try SwiftSoup.parse(html)
        let links = try doc.select("a[href*=/timetable/Changes/], [onclick*=/timetable/Changes/], [data-href*=/timetable/Changes/]").array()
        var seen = Set<String>()
        let result = try links.compactMap { link -> CollegeCategory? in
            let href = try link.attr("href")
            let rawTarget: String
            if !href.isEmpty { rawTarget = href }
            else if try link.hasAttr("data-href") { rawTarget = try link.attr("data-href") }
            else { rawTarget = try link.attr("onclick") }
            let target = rawTarget.range(of: #"/timetable/Changes/b\d+"#, options: .regularExpression).map { String(rawTarget[$0]) } ?? rawTarget
            guard target.contains("/timetable/Changes/") else { return nil }
            let url = try target.absoluteURL(relativeTo: base)
            let slug = url.pathComponents.last ?? ""
            guard slug.range(of: #"^b\d+$"#, options: .regularExpression) != nil,
                  seen.insert(slug).inserted else { return nil }
            let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return CollegeCategory(title: title, slug: slug, url: url)
        }
        return Parsed(value: result, validity: result.isEmpty ? .invalidStructure : .success)
    }

    func currentTeachingWeek(from html: String) throws -> Int {
        let text = try SwiftSoup.parse(html).text()
        let regex = try NSRegularExpression(pattern: #"Расписание занятий\s*\(\s*(\d+)\s+учебн"#, options: [.caseInsensitive])
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else { return 1 }
        return Int(ns.substring(with: match.range(at: 1))) ?? 1
    }

    func groups(from html: String, category: CollegeCategory) throws -> Parsed<[StudentGroup]> {
        let doc = try SwiftSoup.parse(html)
        let links = try doc.select("a[href*=/timetable/timetable/]").array()
        var seen = Set<String>()
        let groups = try links.compactMap { link -> StudentGroup? in
            let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return StudentGroup(name: name, url: try link.attr("href").absoluteURL(relativeTo: base), categoryID: category.slug)
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
