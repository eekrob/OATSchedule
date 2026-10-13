package ru.oat.schedule.work

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import ru.oat.schedule.data.DiagnosticsLog
import ru.oat.schedule.data.OatRepository
import java.util.concurrent.TimeUnit

class ChangesWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val repository = OatRepository(applicationContext)
        val prefs = repository.preferences

        if (!prefs.notificationsEnabled()) return Result.success()
        val selection = prefs.loadSelection() ?: return Result.success()

        return runCatching {
            val fresh = repository.loadChanges(selection)
            val oldIds = prefs.knownChangeIds()
            val freshIds = fresh.mapTo(mutableSetOf()) { it.stableId }

            if (oldIds.isNotEmpty()) {
                val groupKey = normalizeGroup(selection.group.name)
                fresh.filter {
                    it.stableId !in oldIds && normalizeGroup(it.group) == groupKey
                }.forEach(::notifyChange)
            }

            prefs.setKnownChangeIds(freshIds)
            repository.cacheChanges(selection, fresh)
            Result.success()
        }.getOrElse {
            DiagnosticsLog.add("WORKER FAILED", it.message ?: it.toString())
            Result.retry()
        }
    }

    private fun notifyChange(change: ru.oat.schedule.model.ScheduleChange) {
        if (
            Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) return

        ensureChannel()

        val lesson = change.newLesson ?: change.oldLesson ?: 0
        val body = when {
            change.isCancelled -> "$lesson-я пара отменена"
            !change.newSubject.isNullOrBlank() -> "$lesson-я пара · ${change.newSubject}"
            else -> "$lesson-я пара · ${change.reason ?: "есть обновление"}"
        }

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("Изменение расписания · ${change.group}")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        NotificationManagerCompat.from(applicationContext)
            .notify(change.stableId.hashCode(), notification)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Изменения расписания",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Замены, отмены и переносы для выбранной группы"
        }
        manager.createNotificationChannel(channel)
    }

    private fun normalizeGroup(value: String): String =
        value.filter { it.isLetterOrDigit() }.uppercase()

    companion object {
        private const val WORK_NAME = "oat_changes_watch"
        private const val CHANNEL_ID = "schedule_changes"

        fun enqueue(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = PeriodicWorkRequestBuilder<ChangesWorker>(
                15,
                TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
