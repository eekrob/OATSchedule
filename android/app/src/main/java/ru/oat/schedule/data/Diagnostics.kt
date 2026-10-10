package ru.oat.schedule.data

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object DiagnosticsLog {
    private val entries = ArrayDeque<String>()
    private val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    @Synchronized
    fun add(title: String, details: String) {
        entries.addLast("[${formatter.format(Date())}] $title\n$details")
        while (entries.size > 80) entries.removeFirst()
    }

    @Synchronized
    fun report(): String = buildString {
        appendLine("OATSchedule Android diagnostics")
        appendLine("generated: ${formatter.format(Date())}")
        appendLine("events: ${entries.size}")
        appendLine()
        entries.forEachIndexed { index, item ->
            appendLine("===== EVENT ${index + 1} =====")
            appendLine(item)
        }
    }
}
