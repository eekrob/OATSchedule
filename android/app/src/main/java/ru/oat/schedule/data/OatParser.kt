package ru.oat.schedule.data

import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import ru.oat.schedule.model.CollegeCategory
import ru.oat.schedule.model.Schedule
import ru.oat.schedule.model.ScheduleChange
import ru.oat.schedule.model.ScheduleLesson
import ru.oat.schedule.model.StudentGroup
import ru.oat.schedule.model.stableHash
import java.net.URI
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

class OatParser {
    private val base = URI("https://www.oat.ru/")
    private val timetableBase = URI("https://www.oat.ru/timetable/")
    private val classesPage = URI("https://www.oat.ru/timetable/Classes")
    private val omskZone = ZoneId.of("Asia/Omsk")

    fun categories(html: String): List<CollegeCategory> {
        val doc = Jsoup.parse(html)
        val seen = mutableSetOf<String>()

        return doc.select("a[href]").mapNotNull { link ->
            val title = normalize(link.text())
            val href = link.attr("href").trim()
            val lower = href.lowercase()

            if (!lower.contains("groups/") || title.isBlank()) return@mapNotNull null

            val url = when {
                href.startsWith("http", true) -> href
                href.startsWith("/") -> base.resolve(href).toString()
                href.startsWith("groups/", true) -> timetableBase.resolve(href).toString()
                else -> classesPage.resolve(href).toString()
            }

            val slug = URI(url).path.substringAfterLast("/")
            if (slug.isBlank() || !seen.add(slug)) return@mapNotNull null
            CollegeCategory(title = title, slug = slug, url = url)
        }
    }

    fun groups(html: String, category: CollegeCategory): List<StudentGroup> {
        val doc = Jsoup.parse(html)
        val seen = mutableSetOf<String>()

        return doc.select("a[href]").mapNotNull { link ->
            val name = normalize(link.text())
            val href = link.attr("href").trim()
            if (!looksLikeGroupName(name)) return@mapNotNull null

            val lower = href.lowercase()
            if (!lower.contains("timetable") && !lower.contains("group")) return@mapNotNull null

            val url = when {
                href.startsWith("http", true) -> href
                href.startsWith("/") -> base.resolve(href).toString()
                href.startsWith("timetable/", true) -> timetableBase.resolve(href).toString()
                else -> URI(category.url).resolve(href).toString()
            }

            if (!seen.add(name.uppercase(Locale.ROOT))) return@mapNotNull null
            StudentGroup(name = name, url = url, categoryId = category.slug)
        }
    }

    fun currentTeachingWeek(html: String): Int {
        val text = Jsoup.parse(html).text()
        val absolute = Regex(
            """Расписание\s+занятий\s*\(\s*(\d+)\s+учебн""",
            RegexOption.IGNORE_CASE
        ).find(text)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 1

        return ((absolute.coerceAtLeast(1) - 1) % 2) + 1
    }

    fun schedule(
        html: String,
        group: StudentGroup,
        currentWeek: Int
    ): Schedule {
        val doc = Jsoup.parse(html)
        val lessons = mutableListOf<ScheduleLesson>()

        doc.select("table").take(2).forEachIndexed { tableIndex, table ->
            val rows = table.select("tr")
            val header = rows.firstOrNull() ?: return@forEachIndexed
            val headers = header.select("th,td").map { normalize(it.text()) }

            if (headers.none { it.contains("Понедельник", true) }) return@forEachIndexed

            val week = weekNumber(headers, tableIndex + 1)
            val weekdayColumns = headers.mapIndexedNotNull { index, title ->
                weekday(title)?.let { index to it }
            }

            rows.drop(1).forEach { row ->
                val cells = row.select("th,td")
                if (cells.size < 3) return@forEach

                val number = cells[0].text().filter(Char::isDigit).toIntOrNull() ?: return@forEach
                val times = timeRanges(cells[1])
                val time = times.firstOrNull()

                weekdayColumns.forEach { (column, weekday) ->
                    if (column >= cells.size) return@forEach
                    val lines = cellLines(cells[column])
                    if (lines.isEmpty()) return@forEach

                    chunkLessons(lines).forEach { chunk ->
                        val subject = chunk.firstOrNull {
                            !looksLikeTeacher(it) &&
                                !looksLikeRoom(it) &&
                                !it.contains("подгруппа", true)
                        } ?: chunk.firstOrNull() ?: "Занятие"

                        val teacher = chunk.firstOrNull(::looksLikeTeacher)
                        val room = chunk.firstOrNull(::looksLikeRoom)
                        val subgroup = chunk.firstOrNull { it.contains("подгруппа", true) }
                        val extras = chunk.filter {
                            it != subject && it != teacher && it != room && it != subgroup
                        }

                        lessons += ScheduleLesson(
                            week = week,
                            weekday = weekday,
                            number = number,
                            start = time?.first.orEmpty(),
                            end = time?.second.orEmpty(),
                            subject = subject,
                            teacher = teacher,
                            room = room,
                            subgroup = subgroup,
                            extra = extras.takeIf { it.isNotEmpty() }?.joinToString(" · ")
                        )
                    }
                }
            }
        }

        if (lessons.isEmpty()) error("Структура страницы расписания изменилась")

        return Schedule(
            groupName = group.name,
            lessons = lessons,
            currentWeek = currentWeek
        )
    }

    fun changePages(html: String, buildingUrl: String): List<ChangePage> {
        val doc = Jsoup.parse(html)
        val seen = mutableSetOf<String>()

        return doc.select("a.choose-item[href], .months a[href], a[href*=/timetable/Changes/]")
            .mapNotNull { link ->
                val href = link.attr("href").trim()
                val rawDate = DATE_REGEX.find(link.text())?.value
                    ?: DATE_REGEX.find(href)?.value
                    ?: return@mapNotNull null

                val date = parseNumericDate(rawDate) ?: return@mapNotNull null
                val url = when {
                    href.startsWith("http", true) -> href
                    href.startsWith("/") -> base.resolve(href).toString()
                    else -> URI(buildingUrl.trimEnd('/') + "/").resolve(href).toString()
                }

                val key = "$date|$url"
                if (!seen.add(key)) return@mapNotNull null
                ChangePage(date, url)
            }
            .sortedByDescending { it.date }
    }

    fun currentChangeDate(html: String): LocalDate? {
        val doc = Jsoup.parse(html)
        val heading = doc.select("h1,h2,.section-title").joinToString(" ") { it.text() }

        val russian = Regex(
            """(?i)\b(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)\b"""
        ).find(heading)

        if (russian != null) {
            val day = russian.groupValues[1].toInt()
            val month = MONTHS[russian.groupValues[2].lowercase()] ?: return null
            val year = DATE_REGEX.find(doc.text())?.value
                ?.let(::parseNumericDate)
                ?.year
                ?: LocalDate.now(omskZone).year
            return LocalDate.of(year, month, day)
        }

        return DATE_REGEX.find(heading)?.value?.let(::parseNumericDate)
    }

    fun changes(
        html: String,
        categoryId: String,
        date: LocalDate
    ): List<ScheduleChange> {
        val doc = Jsoup.parse(html)
        val table = doc.select("table").firstOrNull {
            val text = it.text()
            text.contains("Группа", true) && text.contains("причина", true)
        } ?: return emptyList()

        val rows = table.select("tr")
        val header = rows.firstOrNull() ?: return emptyList()
        val headers = header.select("th,td").map { normalize(it.text()).lowercase() }

        fun columns(fragment: String): List<Int> =
            headers.indices.filter { headers[it].contains(fragment) }

        val groupColumn = columns("групп").firstOrNull() ?: return emptyList()
        val courseColumn = columns("курс").firstOrNull()
        val reasonColumn = columns("причин").firstOrNull() ?: return emptyList()
        val lessonColumns = columns("пара")
        val roomColumns = columns("аудит")
        val subjectColumns = columns("дисциплин")
        val teacherColumns = columns("преподав")

        val oldLessonColumn = lessonColumns.firstOrNull() ?: return emptyList()
        val newLessonColumn = lessonColumns.getOrNull(1)

        return rows.drop(1).mapNotNull { row ->
            val cells = row.select("th,td").map { normalize(it.text()) }
            if (cells.size < 8) return@mapNotNull null

            fun value(index: Int?): String? =
                index?.takeIf { it in cells.indices }
                    ?.let { cells[it] }
                    ?.takeIf { it.isNotBlank() }

            val group = value(groupColumn) ?: return@mapNotNull null
            val oldLesson = intCell(value(oldLessonColumn))
            val newLesson = intCell(value(newLessonColumn))
            val raw = cells.joinToString(" | ")

            val key = listOf(
                categoryId,
                date.toString(),
                group,
                (oldLesson ?: newLesson ?: 0).toString(),
                raw
            ).joinToString("|")

            ScheduleChange(
                stableId = stableHash(key),
                categoryId = categoryId,
                group = group,
                date = date.toString(),
                course = value(courseColumn),
                oldLesson = oldLesson,
                oldRoom = value(roomColumns.getOrNull(0)),
                oldSubject = value(subjectColumns.getOrNull(0)),
                oldTeacher = value(teacherColumns.getOrNull(0)),
                reason = value(reasonColumn),
                newLesson = newLesson,
                newRoom = value(roomColumns.getOrNull(1)),
                newSubject = value(subjectColumns.getOrNull(1)),
                newTeacher = value(teacherColumns.getOrNull(1)),
                rawText = raw
            )
        }
    }

    private fun parseNumericDate(value: String): LocalDate? =
        runCatching {
            LocalDate.parse(
                value,
                DateTimeFormatter.ofPattern("d.M.uuuu", Locale.US)
            )
        }.getOrNull()

    private fun weekday(value: String): Int? {
        val lower = value.lowercase()
        return when {
            "понедельник" in lower -> 1
            "вторник" in lower -> 2
            "среда" in lower -> 3
            "четверг" in lower -> 4
            "пятница" in lower -> 5
            "суббота" in lower -> 6
            "воскресенье" in lower -> 7
            else -> null
        }
    }

    private fun weekNumber(headers: List<String>, fallback: Int): Int {
        headers.forEach { header ->
            Regex("""-(\d+)\s*$""").find(header)?.groupValues?.getOrNull(1)
                ?.toIntOrNull()
                ?.let { return it }
        }
        return fallback
    }

    private fun timeRanges(cell: Element): List<Pair<String, String>> {
        val values = TIME_REGEX.findAll(cell.text()).map { it.value }.toList()
        return values.chunked(2).mapNotNull {
            if (it.size == 2) it[0] to it[1] else null
        }
    }

    private fun cellLines(cell: Element): List<String> {
        var html = cell.html()
        html = html.replace(Regex("""(?i)<br\s*/?>"""), "__OAT_LINE__")
        html = html.replace(Regex("""(?i)</(div|p|li)>"""), "__OAT_LINE__")
        return Jsoup.parseBodyFragment(html).text()
            .split("__OAT_LINE__")
            .map(::normalize)
            .filter(String::isNotBlank)
    }

    private fun chunkLessons(lines: List<String>): List<List<String>> {
        val markers = lines.indices.filter { lines[it].contains("подгруппа", true) }
        if (lines.size <= 3 || markers.isEmpty()) return listOf(lines)

        val subject = lines.firstOrNull {
            !it.contains("подгруппа", true) &&
                !looksLikeTeacher(it) &&
                !looksLikeRoom(it)
        } ?: "Занятие"

        return markers.mapIndexed { index, start ->
            val end = markers.getOrNull(index + 1) ?: lines.size
            listOf(subject) + lines.subList(start, end)
        }
    }

    private fun looksLikeTeacher(value: String): Boolean =
        value.matches(Regex("""^[А-ЯЁ][А-ЯЁа-яё-]+\s+[А-ЯЁ]\.\s*[А-ЯЁ]?\.?$"""))

    private fun looksLikeRoom(value: String): Boolean =
        value.matches(
            Regex(
                """^(\d{2,4}[а-яА-Я]?\+?|спортзал|стадион)$""",
                RegexOption.IGNORE_CASE
            )
        )

    private fun looksLikeGroupName(value: String): Boolean =
        value.any(Char::isLetter) &&
            value.any(Char::isDigit) &&
            !value.contains("выберите", true)

    private fun intCell(value: String?): Int? =
        value?.filter(Char::isDigit)?.toIntOrNull()

    private fun normalize(value: String): String =
        value.replace('\u00A0', ' ')
            .trim()
            .split(Regex("""\s+"""))
            .filter(String::isNotBlank)
            .joinToString(" ")

    data class ChangePage(
        val date: LocalDate,
        val url: String
    )

    companion object {
        private val DATE_REGEX = Regex("""\b\d{1,2}\.\d{1,2}\.\d{4}\b""")
        private val TIME_REGEX = Regex("""\d{1,2}:\d{2}""")
        private val MONTHS = mapOf(
            "января" to 1,
            "февраля" to 2,
            "марта" to 3,
            "апреля" to 4,
            "мая" to 5,
            "июня" to 6,
            "июля" to 7,
            "августа" to 8,
            "сентября" to 9,
            "октября" to 10,
            "ноября" to 11,
            "декабря" to 12
        )
    }
}
