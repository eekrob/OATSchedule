package ru.oat.schedule.data

import android.content.Context
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import ru.oat.schedule.model.Schedule
import ru.oat.schedule.model.ScheduleChange
import ru.oat.schedule.model.UserSelection

class AppPreferences(context: Context) {
    private val prefs = context.getSharedPreferences("oat_schedule", Context.MODE_PRIVATE)
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun loadSelection(): UserSelection? =
        prefs.getString(KEY_SELECTION, null)?.let {
            runCatching { json.decodeFromString<UserSelection>(it) }.getOrNull()
        }

    fun saveSelection(value: UserSelection?) {
        prefs.edit().apply {
            if (value == null) remove(KEY_SELECTION)
            else putString(KEY_SELECTION, json.encodeToString(value))
        }.apply()
    }

    fun loadSchedule(groupId: String): Schedule? =
        prefs.getString("schedule|$groupId", null)?.let {
            runCatching { json.decodeFromString<Schedule>(it) }.getOrNull()
        }

    fun saveSchedule(groupId: String, schedule: Schedule) {
        prefs.edit().putString("schedule|$groupId", json.encodeToString(schedule)).apply()
    }

    fun loadChanges(categoryId: String): List<ScheduleChange> =
        prefs.getString("changes|$categoryId", null)?.let {
            runCatching { json.decodeFromString<List<ScheduleChange>>(it) }.getOrNull()
        } ?: emptyList()

    fun saveChanges(categoryId: String, changes: List<ScheduleChange>) {
        prefs.edit().putString("changes|$categoryId", json.encodeToString(changes)).apply()
    }

    fun appearance(): String = prefs.getString(KEY_APPEARANCE, "system") ?: "system"

    fun setAppearance(value: String) {
        prefs.edit().putString(KEY_APPEARANCE, value).apply()
    }

    fun notificationsEnabled(): Boolean = prefs.getBoolean(KEY_NOTIFICATIONS, false)

    fun setNotificationsEnabled(value: Boolean) {
        prefs.edit().putBoolean(KEY_NOTIFICATIONS, value).apply()
    }

    fun knownChangeIds(): Set<String> =
        prefs.getStringSet(KEY_KNOWN_CHANGES, emptySet())?.toSet() ?: emptySet()

    fun setKnownChangeIds(ids: Set<String>) {
        prefs.edit().putStringSet(KEY_KNOWN_CHANGES, ids).apply()
    }

    companion object {
        private const val KEY_SELECTION = "selection"
        private const val KEY_APPEARANCE = "appearance"
        private const val KEY_NOTIFICATIONS = "notifications"
        private const val KEY_KNOWN_CHANGES = "known_changes"
    }
}
