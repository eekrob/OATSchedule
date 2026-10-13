package ru.oat.schedule.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.oat.schedule.model.CollegeCategory

class OatParserTest {
    private val parser = OatParser()

    @Test
    fun parsesRealCategoryLinkShape() {
        val html = """
            <html><body>
              <a href="groups/ul_lenina_24">Корпус 1 | ул. Ленина, 24</a>
              <a href="groups/ul_b_khmelnickogo_281a">Корпус 2 | ул. Б. Хмельницкого, 281а</a>
            </body></html>
        """.trimIndent()

        val result = parser.categories(html)

        assertEquals(2, result.size)
        assertEquals("ul_lenina_24", result.first().slug)
        assertEquals(
            "https://www.oat.ru/timetable/groups/ul_lenina_24",
            result.first().url
        )
    }

    @Test
    fun mapsAbsoluteWeekToTwoWeekCycle() {
        assertEquals(
            2,
            parser.currentTeachingWeek(
                "<h1>Расписание занятий (6 учебная неделя)</h1>"
            )
        )
        assertEquals(
            1,
            parser.currentTeachingWeek(
                "<h1>Расписание занятий (7 учебная неделя)</h1>"
            )
        )
    }

    @Test
    fun parsesDirectChangePagesAndTable() {
        val category = CollegeCategory(
            "Корпус 1",
            "ul_lenina_24",
            "https://www.oat.ru/timetable/groups/ul_lenina_24"
        )
        val buildingUrl = "https://www.oat.ru/timetable/Changes/b1"
        val html = """
            <html><body>
              <h2 class="section-title">Изменения в расписании на 12 октября (понедельник)</h2>
              <a class="choose-item" href="/timetable/Changes/b1/10.10.2026">10.10.2026</a>
              <a class="choose-item active" href="/timetable/Changes/b1/12.10.2026">12.10.2026</a>
              <table class="customized timetable">
                <tr>
                  <th>Курс</th><th>Группа</th><th>Пара</th><th>Аудит</th>
                  <th>Учеб.дисциплина</th><th>ФИО преподавателя</th><th>причина</th>
                  <th>пара</th><th>Аудит</th><th>Учеб.дисциплина</th><th>ФИО преподавателя</th>
                </tr>
                <tr>
                  <td>1</td><td>ПР116</td><td>2</td><td>204</td>
                  <td>ИнЯзык2пг</td><td>Передрей А.Е.</td><td>бол</td>
                  <td>2</td><td>301</td><td>ИнЯзык2пг</td><td>Маслакова Л.М.</td>
                </tr>
              </table>
            </body></html>
        """.trimIndent()

        val pages = parser.changePages(html, buildingUrl)
        assertEquals(2, pages.size)
        assertEquals(
            "https://www.oat.ru/timetable/Changes/b1/12.10.2026",
            pages.first().url
        )

        val date = requireNotNull(parser.currentChangeDate(html))
        assertEquals("2026-10-12", date.toString())

        val changes = parser.changes(html, "b1", date)
        assertEquals(1, changes.size)
        assertEquals("ПР116", changes.first().group)
        assertEquals("301", changes.first().newRoom)
        assertTrue(changes.first().stableId.isNotBlank())
    }
}
