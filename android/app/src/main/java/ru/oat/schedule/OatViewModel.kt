package ru.oat.schedule

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import ru.oat.schedule.data.DiagnosticsLog
import ru.oat.schedule.data.OatRepository
import ru.oat.schedule.model.CollegeCategory
import ru.oat.schedule.model.Schedule
import ru.oat.schedule.model.ScheduleChange
import ru.oat.schedule.model.StudentGroup
import ru.oat.schedule.model.UserSelection
import ru.oat.schedule.work.ChangesWorker

class OatViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = OatRepository(application)

    var selection by mutableStateOf(repository.preferences.loadSelection())
        private set

    var categories by mutableStateOf<List<CollegeCategory>>(emptyList())
        private set

    var groups by mutableStateOf<List<StudentGroup>>(emptyList())
        private set

    var chosenCategory by mutableStateOf<CollegeCategory?>(null)
        private set

    var chosenGroup by mutableStateOf<StudentGroup?>(null)
        private set

    var schedule by mutableStateOf<Schedule?>(null)
        private set

    var changes by mutableStateOf<List<ScheduleChange>>(emptyList())
        private set

    var categoryLoading by mutableStateOf(false)
        private set

    var groupLoading by mutableStateOf(false)
        private set

    var scheduleLoading by mutableStateOf(false)
        private set

    var changesLoading by mutableStateOf(false)
        private set

    var error by mutableStateOf<String?>(null)
        private set

    var appearance by mutableStateOf(repository.preferences.appearance())
        private set

    var notificationsEnabled by mutableStateOf(repository.preferences.notificationsEnabled())
        private set

    init {
        selection?.let {
            schedule = repository.cachedSchedule(it)
            changes = repository.cachedChanges(it)
            if (notificationsEnabled) ChangesWorker.enqueue(application)
            refreshAll()
        } ?: reloadCategories()
    }

    fun reloadCategories() {
        viewModelScope.launch {
            categoryLoading = true
            error = null
            runCatching { repository.loadCategories() }
                .onSuccess { categories = it }
                .onFailure {
                    error = it.message ?: "Не удалось загрузить корпуса"
                    DiagnosticsLog.add("CATEGORIES FAILED", error.orEmpty())
                }
            categoryLoading = false
        }
    }

    fun selectCategory(category: CollegeCategory) {
        chosenCategory = category
        chosenGroup = null
        groups = emptyList()

        viewModelScope.launch {
            groupLoading = true
            error = null
            runCatching { repository.loadGroups(category) }
                .onSuccess { groups = it }
                .onFailure {
                    error = it.message ?: "Не удалось загрузить группы"
                    DiagnosticsLog.add("GROUPS FAILED", error.orEmpty())
                }
            groupLoading = false
        }
    }

    fun selectGroup(group: StudentGroup) {
        chosenGroup = group
    }

    fun completeSelection() {
        val category = chosenCategory ?: return
        val group = chosenGroup ?: return
        val value = UserSelection(category, group)

        selection = value
        repository.preferences.saveSelection(value)
        schedule = repository.cachedSchedule(value)
        changes = repository.cachedChanges(value)
        refreshAll()
    }

    fun resetSelection() {
        repository.preferences.saveSelection(null)
        selection = null
        chosenCategory = null
        chosenGroup = null
        groups = emptyList()
        schedule = null
        changes = emptyList()
        error = null
        reloadCategories()
    }

    fun refreshAll() {
        val current = selection ?: return
        viewModelScope.launch {
            val scheduleTask = async { refreshScheduleInternal(current) }
            val changesTask = async { refreshChangesInternal(current) }
            scheduleTask.await()
            changesTask.await()
        }
    }

    fun refreshSchedule() {
        selection?.let { current ->
            viewModelScope.launch { refreshScheduleInternal(current) }
        }
    }

    fun refreshChanges() {
        selection?.let { current ->
            viewModelScope.launch { refreshChangesInternal(current) }
        }
    }

    private suspend fun refreshScheduleInternal(current: UserSelection) {
        scheduleLoading = true
        runCatching { repository.loadSchedule(current) }
            .onSuccess {
                schedule = it
                repository.cacheSchedule(current, it)
            }
            .onFailure {
                error = it.message ?: "Не удалось обновить расписание"
                DiagnosticsLog.add("SCHEDULE FAILED", error.orEmpty())
            }
        scheduleLoading = false
    }

    private suspend fun refreshChangesInternal(current: UserSelection) {
        changesLoading = true
        runCatching { repository.loadChanges(current) }
            .onSuccess { fresh ->
                if (fresh.isEmpty() && changes.isNotEmpty()) {
                    error = "Сайт вернул пустой список. Оставлены сохранённые изменения."
                } else {
                    changes = fresh
                    repository.cacheChanges(current, fresh)
                }
            }
            .onFailure {
                error = it.message ?: "Не удалось обновить изменения"
                DiagnosticsLog.add("CHANGES FAILED", error.orEmpty())
            }
        changesLoading = false
    }

    fun updateAppearance(value: String) {
        appearance = value
        repository.preferences.setAppearance(value)
    }

    fun updateNotificationsEnabled(value: Boolean) {
        notificationsEnabled = value
        repository.preferences.setNotificationsEnabled(value)

        if (value) {
            selection?.let { ChangesWorker.enqueue(getApplication()) }
        } else {
            ChangesWorker.cancel(getApplication())
        }
    }

    fun clearError() {
        error = null
    }

    fun diagnostics(): String = DiagnosticsLog.report()
}
