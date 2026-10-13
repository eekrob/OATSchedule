package ru.oat.schedule.data

import android.content.Context
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import ru.oat.schedule.model.CollegeCategory
import ru.oat.schedule.model.Schedule
import ru.oat.schedule.model.ScheduleChange
import ru.oat.schedule.model.StudentGroup
import ru.oat.schedule.model.UserSelection

class OatRepository(context: Context) {
    private val http = OatHttpClient()
    private val parser = OatParser()
    val preferences = AppPreferences(context.applicationContext)

    suspend fun loadCategories(): List<CollegeCategory> {
        val html = http.get(CLASSES_URL)
        val result = parser.categories(html)
        check(result.isNotEmpty()) { "Не удалось найти корпуса на oat.ru" }
        return result
    }

    suspend fun loadGroups(category: CollegeCategory): List<StudentGroup> {
        val html = http.get(category.url)
        val result = parser.groups(html, category)
        check(result.isNotEmpty()) { "Не удалось найти группы выбранного корпуса" }
        return result
    }

    suspend fun loadSchedule(selection: UserSelection): Schedule = coroutineScope {
        val index = async { http.get(CLASSES_URL) }
        val schedulePage = async { http.get(selection.group.url) }

        val week = parser.currentTeachingWeek(index.await())
        parser.schedule(
            html = schedulePage.await(),
            group = selection.group,
            currentWeek = week
        )
    }

    suspend fun loadChanges(selection: UserSelection): List<ScheduleChange> {
        val building = buildingNumber(selection.category)
        val buildingUrl = "https://www.oat.ru/timetable/Changes/b$building"
        val indexHtml = http.get(buildingUrl)

        val result = mutableListOf<ScheduleChange>()

        parser.currentChangeDate(indexHtml)?.let { date ->
            result += parser.changes(
                html = indexHtml,
                categoryId = "b$building",
                date = date
            )
        }

        parser.changePages(indexHtml, buildingUrl)
            .distinctBy { it.url }
            .forEach { page ->
                runCatching {
                    val html = http.get(page.url)
                    parser.changes(
                        html = html,
                        categoryId = "b$building",
                        date = page.date
                    )
                }.onSuccess {
                    result += it
                }.onFailure {
                    DiagnosticsLog.add(
                        "CHANGE PAGE FAILED",
                        "url: ${page.url}\nerror: ${it.message}"
                    )
                }
            }

        return result
            .distinctBy { it.stableId }
            .sortedWith(
                compareByDescending<ScheduleChange> { it.date }
                    .thenBy { it.group }
                    .thenBy { it.oldLesson ?: it.newLesson ?: 0 }
            )
    }

    fun cachedSchedule(selection: UserSelection): Schedule? =
        preferences.loadSchedule(selection.group.name)

    fun cacheSchedule(selection: UserSelection, schedule: Schedule) =
        preferences.saveSchedule(selection.group.name, schedule)

    fun cachedChanges(selection: UserSelection): List<ScheduleChange> =
        preferences.loadChanges(selection.category.slug)

    fun cacheChanges(selection: UserSelection, changes: List<ScheduleChange>) =
        preferences.saveChanges(selection.category.slug, changes)

    private fun buildingNumber(category: CollegeCategory): Int {
        Regex("""Корпус\s*(\d+)""", RegexOption.IGNORE_CASE)
            .find(category.title)
            ?.groupValues
            ?.getOrNull(1)
            ?.toIntOrNull()
            ?.let { return it.coerceIn(1, 4) }

        return when (category.slug.lowercase()) {
            "ul_lenina_24" -> 1
            "ul_b_khmelnickogo_281a" -> 2
            "pr_kosmicheskij_14a" -> 3
            "ul_volkhovstroya_5" -> 4
            else -> 1
        }
    }

    companion object {
        private const val CLASSES_URL = "https://www.oat.ru/timetable/Classes"
    }
}
