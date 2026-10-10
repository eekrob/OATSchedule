package ru.oat.schedule.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.AirplanemodeActive
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import ru.oat.schedule.BuildConfig
import ru.oat.schedule.OatViewModel
import ru.oat.schedule.model.Schedule
import ru.oat.schedule.model.ScheduleChange
import ru.oat.schedule.model.ScheduleLesson
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.util.Locale

private val OmskZone = ZoneId.of("Asia/Omsk")
private val RuLocale = Locale("ru", "RU")

@Composable
fun OatApp(viewModel: OatViewModel) {
    Crossfade(
        targetState = viewModel.selection != null,
        label = "root"
    ) { ready ->
        if (ready) {
            MainTabs(viewModel)
        } else {
            SetupScreen(viewModel)
        }
    }
}

@Composable
private fun SetupScreen(viewModel: OatViewModel) {
    var step by rememberSaveable { mutableIntStateOf(0) }
    var query by rememberSaveable { mutableStateOf("") }
    val context = LocalContext.current

    val notificationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) viewModel.updateNotificationsEnabled(true)
        viewModel.completeSelection()
    }

    fun finishWithNotifications() {
        if (
            Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            viewModel.updateNotificationsEnabled(true)
            viewModel.completeSelection()
        }
    }

    Surface(modifier = Modifier.fillMaxSize()) {
        AnimatedContent(
            targetState = step,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "setup-step"
        ) { current ->
            when (current) {
                0 -> WelcomeScreen(onStart = { step = 1 })
                1 -> GroupPickerScreen(
                    viewModel = viewModel,
                    query = query,
                    onQuery = { query = it },
                    onContinue = { step = 2 }
                )
                else -> NotificationsSetupScreen(
                    groupName = viewModel.chosenGroup?.name.orEmpty(),
                    onEnable = ::finishWithNotifications,
                    onLater = viewModel::completeSelection
                )
            }
        }
    }
}

@Composable
private fun WelcomeScreen(onStart: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.weight(1f))

        Box(
            modifier = Modifier
                .size(220.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Default.CalendarMonth,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.38f),
                modifier = Modifier.size(126.dp)
            )
            Icon(
                Icons.Default.AirplanemodeActive,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(92.dp)
            )
        }

        Spacer(Modifier.height(28.dp))
        Text(
            "ОмАВИАТ\nРасписание",
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(10.dp))
        Text(
            "Расписание занятий и изменения всегда под рукой.",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(Modifier.weight(1f))
        Button(
            onClick = onStart,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Начать")
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Default.ArrowForward, contentDescription = null)
        }
    }
}

@Composable
private fun GroupPickerScreen(
    viewModel: OatViewModel,
    query: String,
    onQuery: (String) -> Unit,
    onContinue: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
    ) {
        Text(
            "Ваша группа",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp)
        )

        OutlinedTextField(
            value = query,
            onValueChange = onQuery,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            placeholder = { Text("Найти группу") },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            trailingIcon = {
                if (query.isNotBlank()) {
                    IconButton(onClick = { onQuery("") }) {
                        Icon(Icons.Default.Close, contentDescription = "Очистить")
                    }
                }
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions.Default
        )

        AnimatedVisibility(visible = viewModel.error != null) {
            ErrorBanner(
                text = viewModel.error.orEmpty(),
                onRetry = viewModel::reloadCategories,
                modifier = Modifier.padding(16.dp)
            )
        }

        if (viewModel.categoryLoading && viewModel.categories.isEmpty()) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(viewModel.categories, key = { it.slug }) { category ->
                    val selected = viewModel.chosenCategory?.slug == category.slug

                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .animateContentSize()
                            .clickable { viewModel.selectCategory(category) },
                        colors = CardDefaults.cardColors(
                            containerColor = if (selected)
                                MaterialTheme.colorScheme.primaryContainer
                            else
                                MaterialTheme.colorScheme.surfaceVariant
                        )
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Apartment, contentDescription = null)
                            Spacer(Modifier.width(12.dp))
                            Text(
                                category.title,
                                modifier = Modifier.weight(1f),
                                fontWeight = FontWeight.SemiBold
                            )
                            if (selected && viewModel.groupLoading) {
                                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                            }
                        }

                        if (selected && !viewModel.groupLoading) {
                            val normalized = query.filter { it.isLetterOrDigit() }.uppercase()
                            val visibleGroups = viewModel.groups.filter {
                                normalized.isBlank() ||
                                    it.name.filter { c -> c.isLetterOrDigit() }
                                        .uppercase()
                                        .contains(normalized)
                            }

                            if (visibleGroups.isEmpty()) {
                                Text(
                                    if (query.isBlank()) "Группы не найдены" else "Нет совпадений",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(start = 52.dp, end = 16.dp, bottom = 16.dp)
                                )
                            } else {
                                visibleGroups.forEach { group ->
                                    val groupSelected = viewModel.chosenGroup?.name == group.name
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable { viewModel.selectGroup(group) }
                                            .padding(horizontal = 18.dp, vertical = 12.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(
                                            Icons.Default.Groups,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                        Spacer(Modifier.width(12.dp))
                                        Text(group.name, modifier = Modifier.weight(1f))
                                        if (groupSelected) {
                                            Icon(
                                                Icons.Default.CheckCircle,
                                                contentDescription = null,
                                                tint = MaterialTheme.colorScheme.primary
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        AnimatedVisibility(visible = viewModel.chosenGroup != null) {
            Button(
                onClick = onContinue,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp)
            ) {
                Text("Продолжить · ${viewModel.chosenGroup?.name.orEmpty()}")
            }
        }
    }
}

@Composable
private fun NotificationsSetupScreen(
    groupName: String,
    onEnable: () -> Unit,
    onLater: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.weight(1f))
        Icon(
            Icons.Default.NotificationsActive,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.tertiary,
            modifier = Modifier.size(72.dp)
        )
        Spacer(Modifier.height(20.dp))
        Text(
            "Узнавайте об изменениях сразу",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(10.dp))
        Text(
            "Android будет периодически проверять изменения для $groupName и покажет уведомление о новых заменах или отменах.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.weight(1f))
        Button(onClick = onEnable, modifier = Modifier.fillMaxWidth()) {
            Text("Включить уведомления")
        }
        TextButton(onClick = onLater, modifier = Modifier.fillMaxWidth()) {
            Text("Позже")
        }
    }
}

@Composable
private fun MainTabs(viewModel: OatViewModel) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(viewModel.error) {
        val message = viewModel.error ?: return@LaunchedEffect
        snackbar.showSnackbar(message)
        viewModel.clearError()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = tab == 0,
                    onClick = { tab = 0 },
                    icon = { Icon(Icons.Default.CalendarMonth, contentDescription = null) },
                    label = { Text("Расписание") }
                )
                NavigationBarItem(
                    selected = tab == 1,
                    onClick = { tab = 1 },
                    icon = { Icon(Icons.Default.SwapHoriz, contentDescription = null) },
                    label = { Text("Изменения") }
                )
                NavigationBarItem(
                    selected = tab == 2,
                    onClick = { tab = 2 },
                    icon = { Icon(Icons.Default.Settings, contentDescription = null) },
                    label = { Text("Настройки") }
                )
            }
        }
    ) { padding ->
        Crossfade(
            targetState = tab,
            modifier = Modifier.padding(padding),
            label = "tabs"
        ) {
            when (it) {
                0 -> ScheduleScreen(viewModel)
                1 -> ChangesScreen(viewModel)
                else -> SettingsScreen(viewModel)
            }
        }
    }
}

@Composable
private fun ScheduleScreen(viewModel: OatViewModel) {
    val selection = viewModel.selection ?: return
    val schedule = viewModel.schedule
    var selectedDate by rememberSaveable { mutableStateOf(LocalDate.now(OmskZone).toString()) }
    val date = LocalDate.parse(selectedDate)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f))
    ) {
        ScreenHeader(
            title = "Расписание",
            subtitle = selection.group.name,
            loading = viewModel.scheduleLoading,
            onRefresh = viewModel::refreshSchedule
        )

        if (schedule == null) {
            EmptyState(
                icon = Icons.Default.WifiOff,
                title = if (viewModel.scheduleLoading) "Загружаю расписание…" else "Расписание пока не загружено",
                description = "Проверьте интернет и нажмите обновить.",
                loading = viewModel.scheduleLoading
            )
            return@Column
        }

        LazyColumn(
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item {
                Text(
                    formatDate(date, "EEEE, d MMMM"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }

            item {
                WeekPicker(
                    selectedDate = date,
                    onSelect = { selectedDate = it.toString() }
                )
            }

            val lessons = lessonsForDate(schedule, date)

            if (lessons.isEmpty()) {
                item {
                    EmptyCard(
                        icon = Icons.Default.CheckCircle,
                        title = "На этот день занятий нет",
                        description = "Выберите другой день недели."
                    )
                }
            } else {
                item {
                    CurrentLessonCard(schedule = schedule, date = date)
                }

                item {
                    Text(
                        "Занятия",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }

                items(lessons, key = { "${it.week}-${it.weekday}-${it.number}-${it.subject}-${it.subgroup}" }) { lesson ->
                    LessonCard(lesson)
                }
            }
        }
    }
}

@Composable
private fun ScreenHeader(
    title: String,
    subtitle: String? = null,
    loading: Boolean,
    onRefresh: () -> Unit
) {
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    title,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold
                )
                if (!subtitle.isNullOrBlank()) {
                    Text(
                        subtitle,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.titleSmall
                    )
                }
            }
            IconButton(onClick = onRefresh, enabled = !loading) {
                Icon(Icons.Default.Refresh, contentDescription = "Обновить")
            }
        }
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
    }
}

@Composable
private fun WeekPicker(
    selectedDate: LocalDate,
    onSelect: (LocalDate) -> Unit
) {
    val weekStart = selectedDate.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val weekEnd = weekStart.plusDays(6)

    Card {
        Column(Modifier.padding(10.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { onSelect(selectedDate.minusWeeks(1)) }) {
                    Icon(Icons.Default.ChevronLeft, contentDescription = "Предыдущая неделя")
                }
                Text(
                    "${weekStart.dayOfMonth}–${formatDate(weekEnd, "d MMMM")}",
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                    fontWeight = FontWeight.SemiBold
                )
                IconButton(onClick = { onSelect(selectedDate.plusWeeks(1)) }) {
                    Icon(Icons.Default.ChevronRight, contentDescription = "Следующая неделя")
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                repeat(7) { offset ->
                    val item = weekStart.plusDays(offset.toLong())
                    val selected = item == selectedDate
                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .clickable { onSelect(item) },
                        shape = RoundedCornerShape(12.dp),
                        color = if (selected)
                            MaterialTheme.colorScheme.primary
                        else
                            Color.Transparent,
                        contentColor = if (selected)
                            MaterialTheme.colorScheme.onPrimary
                        else
                            MaterialTheme.colorScheme.onSurface
                    ) {
                        Column(
                            modifier = Modifier.padding(vertical = 9.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                formatDate(item, "EEEEE").uppercase(RuLocale),
                                style = MaterialTheme.typography.labelSmall
                            )
                            Text(
                                item.dayOfMonth.toString(),
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CurrentLessonCard(schedule: Schedule, date: LocalDate) {
    val today = LocalDate.now(OmskZone)
    if (date != today) return

    val lessons = lessonsForDate(schedule, date)
    val now = LocalTime.now(OmskZone)
    val current = lessons.firstOrNull { lesson ->
        val start = parseTime(lesson.start)
        val end = parseTime(lesson.end)
        start != null && end != null && !now.isBefore(start) && now.isBefore(end)
    }
    val next = lessons.firstOrNull { lesson ->
        val start = parseTime(lesson.start)
        start != null && now.isBefore(start)
    }

    when {
        current != null -> {
            val start = parseTime(current.start) ?: return
            val end = parseTime(current.end) ?: return
            val total = ChronoUnit.MINUTES.between(start, end).coerceAtLeast(1)
            val elapsed = ChronoUnit.MINUTES.between(start, now).coerceAtLeast(0)
            val progress by animateFloatAsState(
                targetValue = (elapsed.toFloat() / total.toFloat()).coerceIn(0f, 1f),
                label = "lesson-progress"
            )

            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            ) {
                Column(Modifier.padding(16.dp)) {
                    Text(
                        "Сейчас",
                        color = MaterialTheme.colorScheme.primary,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        current.subject,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text("${current.number} пара · ${current.start}–${current.end}")
                    current.teacher?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    current.room?.let { Text("Ауд. $it", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Spacer(Modifier.height(10.dp))
                    LinearProgressIndicator(
                        progress = { progress },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }
        next != null -> {
            AssistChip(
                onClick = {},
                label = { Text("Следующая: ${next.number} пара в ${next.start}") },
                leadingIcon = { Icon(Icons.Default.AccessTime, contentDescription = null) }
            )
        }
    }
}

@Composable
private fun LessonCard(lesson: ScheduleLesson) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .animateContentSize()
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${lesson.number} пара",
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "${lesson.start} – ${lesson.end}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                lesson.subject,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            lesson.subgroup?.let {
                MetaLine(Icons.Default.Groups, it)
            }
            lesson.teacher?.let {
                MetaLine(Icons.Default.Person, it)
            }
            lesson.room?.let {
                MetaLine(Icons.Default.MeetingRoom, "Ауд. $it")
            }
            lesson.extra?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
        }
    }
}

@Composable
private fun MetaLine(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(
        modifier = Modifier.padding(top = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.width(7.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun ChangesScreen(viewModel: OatViewModel) {
    val selection = viewModel.selection ?: return
    var mineOnly by rememberSaveable { mutableStateOf(true) }

    val visible = remember(viewModel.changes, mineOnly, selection.group.name) {
        if (!mineOnly) viewModel.changes
        else {
            val key = normalizeGroup(selection.group.name)
            viewModel.changes.filter { normalizeGroup(it.group) == key }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f))
    ) {
        ScreenHeader(
            title = "Изменения",
            subtitle = if (mineOnly) selection.group.name else "Все группы корпуса",
            loading = viewModel.changesLoading,
            onRefresh = viewModel::refreshChanges
        )

        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterChip(
                selected = mineOnly,
                onClick = { mineOnly = true },
                label = { Text("Моя группа") }
            )
            FilterChip(
                selected = !mineOnly,
                onClick = { mineOnly = false },
                label = { Text("Все") }
            )
        }

        AnimatedContent(
            targetState = visible.isEmpty(),
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "changes-content",
            modifier = Modifier.weight(1f)
        ) { empty ->
            if (empty) {
                EmptyState(
                    icon = Icons.Default.CheckCircle,
                    title = "Изменений нет",
                    description = if (mineOnly)
                        "Для ${selection.group.name} пока всё по расписанию."
                    else
                        "Для выбранного корпуса изменений не найдено.",
                    loading = viewModel.changesLoading
                )
            } else {
                LazyColumn(
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(visible, key = { it.stableId }) { change ->
                        ChangeCard(change)
                    }
                }
            }
        }
    }
}

@Composable
private fun ChangeCard(change: ScheduleChange) {
    val accent = when {
        change.isCancelled -> MaterialTheme.colorScheme.error
        change.isAdded -> Color(0xFF2E7D32)
        else -> MaterialTheme.colorScheme.tertiary
    }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(
                    color = accent.copy(alpha = 0.13f),
                    contentColor = accent,
                    shape = RoundedCornerShape(999.dp)
                ) {
                    Text(
                        when {
                            change.isCancelled -> "Отмена"
                            change.isAdded -> "Добавление"
                            else -> "Изменение"
                        },
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
                    )
                }
                Spacer(Modifier.weight(1f))
                Text(
                    formatIsoDate(change.date),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(Modifier.height(10.dp))
            Text(
                change.group,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(10.dp))

            Row(Modifier.fillMaxWidth()) {
                ChangeSide(
                    title = "Было",
                    lesson = change.oldLesson,
                    room = change.oldRoom,
                    subject = change.oldSubject,
                    teacher = change.oldTeacher,
                    modifier = Modifier.weight(1f)
                )
                Divider(
                    modifier = Modifier
                        .fillMaxHeight()
                        .width(1.dp)
                )
                ChangeSide(
                    title = "Стало",
                    lesson = change.newLesson,
                    room = change.newRoom,
                    subject = change.newSubject,
                    teacher = change.newTeacher,
                    cancelled = change.isCancelled,
                    modifier = Modifier.weight(1f)
                )
            }

            change.reason?.takeIf { it.isNotBlank() }?.let {
                Spacer(Modifier.height(10.dp))
                Text(
                    "Причина: $it",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun ChangeSide(
    title: String,
    lesson: Int?,
    room: String?,
    subject: String?,
    teacher: String?,
    modifier: Modifier = Modifier,
    cancelled: Boolean = false
) {
    Column(modifier.padding(horizontal = 6.dp)) {
        Text(
            title.uppercase(RuLocale),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.Bold
        )
        lesson?.let { Text("$it-я пара", fontWeight = FontWeight.SemiBold) }
        if (cancelled) {
            Text(
                "Пара отменена",
                color = MaterialTheme.colorScheme.error,
                fontWeight = FontWeight.Bold
            )
        } else {
            subject?.takeIf { it.isNotBlank() }?.let {
                Text(it, fontWeight = FontWeight.SemiBold)
            }
            room?.takeIf { it.isNotBlank() }?.let { Text("Ауд. $it") }
            teacher?.takeIf { it.isNotBlank() }?.let {
                Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun SettingsScreen(viewModel: OatViewModel) {
    val selection = viewModel.selection ?: return
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        viewModel.updateNotificationsEnabled(granted)
    }

    fun setNotifications(enabled: Boolean) {
        if (!enabled) {
            viewModel.updateNotificationsEnabled(false)
            return
        }

        if (
            Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            viewModel.updateNotificationsEnabled(true)
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            Text(
                "Настройки",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold
            )
        }

        item {
            SectionTitle("Моя группа")
            Card {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.AirplanemodeActive,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(selection.group.name, fontWeight = FontWeight.Bold)
                        Text(
                            selection.category.title,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    OutlinedButton(onClick = viewModel::resetSelection) {
                        Text("Изменить")
                    }
                }
            }
        }

        item {
            SectionTitle("Уведомления")
            Card {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.NotificationsActive, contentDescription = null)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Изменения расписания", fontWeight = FontWeight.SemiBold)
                        Text(
                            "Проверка примерно каждые 15 минут",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = viewModel.notificationsEnabled,
                        onCheckedChange = ::setNotifications
                    )
                }
            }
        }

        item {
            SectionTitle("Оформление")
            Card {
                listOf(
                    "system" to "Системное",
                    "light" to "Светлое",
                    "dark" to "Тёмное"
                ).forEachIndexed { index, (value, title) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { viewModel.updateAppearance(value) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Palette, contentDescription = null)
                        Spacer(Modifier.width(12.dp))
                        Text(title, modifier = Modifier.weight(1f))
                        RadioButton(
                            selected = viewModel.appearance == value,
                            onClick = { viewModel.updateAppearance(value) }
                        )
                    }
                    if (index < 2) HorizontalDivider(Modifier.padding(start = 52.dp))
                }
            }
        }

        item {
            SectionTitle("Диагностика")
            Card {
                Column(Modifier.padding(16.dp)) {
                    Text(
                        "HTTP-отчёт помогает понять, если сайт OAT снова поменяет структуру.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(10.dp))
                    OutlinedButton(
                        onClick = {
                            clipboard.setText(AnnotatedString(viewModel.diagnostics()))
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.ContentCopy, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Скопировать диагностику")
                    }
                }
            }
        }

        item {
            SectionTitle("О приложении")
            Card {
                Column(Modifier.padding(16.dp)) {
                    SettingsLink(
                        title = "Официальное расписание oat.ru",
                        onClick = {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://www.oat.ru/timetable/Classes")
                                )
                            )
                        }
                    )
                    SettingsLink(
                        title = "Изменения расписания",
                        onClick = {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://www.oat.ru/timetable/ClassesChanges")
                                )
                            )
                        }
                    )
                    HorizontalDivider(Modifier.padding(vertical = 10.dp))
                    Text(
                        "ОмАВИАТ Расписание · Android ${BuildConfig.VERSION_NAME}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        item { Spacer(Modifier.height(8.dp)) }
    }
}

@Composable
private fun SettingsLink(title: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.OpenInBrowser, contentDescription = null)
        Spacer(Modifier.width(12.dp))
        Text(title, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(bottom = 6.dp)
    )
}

@Composable
private fun ErrorBanner(
    text: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer
        )
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Default.ErrorOutline, contentDescription = null)
            Spacer(Modifier.width(10.dp))
            Text(text, modifier = Modifier.weight(1f))
            TextButton(onClick = onRetry) { Text("Повторить") }
        }
    }
}

@Composable
private fun EmptyState(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    description: String,
    loading: Boolean
) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp)
        ) {
            if (loading) {
                CircularProgressIndicator()
            } else {
                Icon(
                    icon,
                    contentDescription = null,
                    modifier = Modifier.size(56.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
            Spacer(Modifier.height(16.dp))
            Text(
                title,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(6.dp))
            Text(
                description,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun EmptyCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    description: String
) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 34.dp, horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                icon,
                contentDescription = null,
                modifier = Modifier.size(44.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(Modifier.height(12.dp))
            Text(title, fontWeight = FontWeight.Bold)
            Text(
                description,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}

private fun lessonsForDate(schedule: Schedule, date: LocalDate): List<ScheduleLesson> {
    val today = LocalDate.now(OmskZone)
    val todayMonday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val selectedMonday = date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val delta = ChronoUnit.WEEKS.between(todayMonday, selectedMonday).toInt()
    val base = schedule.currentWeek.coerceIn(1, 2)
    val week = if (kotlin.math.abs(delta) % 2 == 0) base else 3 - base
    val weekday = date.dayOfWeek.value

    return schedule.lessons
        .filter { it.week == week && it.weekday == weekday }
        .sortedBy { it.number }
}

private fun parseTime(value: String): LocalTime? =
    runCatching {
        LocalTime.parse(value, DateTimeFormatter.ofPattern("H:mm"))
    }.getOrNull()

private fun formatDate(date: LocalDate, pattern: String): String =
    date.format(DateTimeFormatter.ofPattern(pattern, RuLocale))
        .replaceFirstChar { if (it.isLowerCase()) it.titlecase(RuLocale) else it.toString() }

private fun formatIsoDate(value: String): String =
    runCatching {
        LocalDate.parse(value).format(DateTimeFormatter.ofPattern("d MMMM", RuLocale))
    }.getOrDefault(value)

private fun normalizeGroup(value: String): String =
    value.filter { it.isLetterOrDigit() }.uppercase()
