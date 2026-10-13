package ru.oat.schedule.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val LightColors = lightColorScheme(
    primary = Color(0xFF1769E0),
    secondary = Color(0xFF2979FF),
    tertiary = Color(0xFFE53935)
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF8AB4FF),
    secondary = Color(0xFFA8C7FA),
    tertiary = Color(0xFFFF8A80)
)

@Composable
fun OATScheduleTheme(
    appearance: String,
    content: @Composable () -> Unit
) {
    val systemDark = isSystemInDarkTheme()
    val dark = when (appearance) {
        "light" -> false
        "dark" -> true
        else -> systemDark
    }

    val context = LocalContext.current
    val scheme = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    } else {
        if (dark) DarkColors else LightColors
    }

    MaterialTheme(
        colorScheme = scheme,
        typography = MaterialTheme.typography,
        content = content
    )
}
