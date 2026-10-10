package ru.oat.schedule.model

import kotlinx.serialization.Serializable
import java.security.MessageDigest

@Serializable
data class CollegeCategory(
    val title: String,
    val slug: String,
    val url: String
)

@Serializable
data class StudentGroup(
    val name: String,
    val url: String,
    val categoryId: String
)

@Serializable
data class UserSelection(
    val category: CollegeCategory,
    val group: StudentGroup
)

@Serializable
data class ScheduleLesson(
    val week: Int,
    val weekday: Int,
    val number: Int,
    val start: String,
    val end: String,
    val subject: String,
    val teacher: String? = null,
    val room: String? = null,
    val subgroup: String? = null,
    val extra: String? = null
)

@Serializable
data class Schedule(
    val groupName: String,
    val lessons: List<ScheduleLesson>,
    val currentWeek: Int,
    val fetchedAtEpochMs: Long = System.currentTimeMillis()
)

@Serializable
data class ScheduleChange(
    val stableId: String,
    val categoryId: String,
    val group: String,
    val date: String,
    val course: String? = null,
    val oldLesson: Int? = null,
    val oldRoom: String? = null,
    val oldSubject: String? = null,
    val oldTeacher: String? = null,
    val reason: String? = null,
    val newLesson: Int? = null,
    val newRoom: String? = null,
    val newSubject: String? = null,
    val newTeacher: String? = null,
    val rawText: String = ""
) {
    val isCancelled: Boolean
        get() = listOf(newSubject, newRoom)
            .filterNotNull()
            .any { it.contains("отмена", ignoreCase = true) }

    val isAdded: Boolean
        get() = oldSubject.isNullOrBlank()
            && oldRoom.isNullOrBlank()
            && oldTeacher.isNullOrBlank()
            && !isCancelled
}

fun stableHash(value: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
    return digest.joinToString("") { "%02x".format(it) }
}
