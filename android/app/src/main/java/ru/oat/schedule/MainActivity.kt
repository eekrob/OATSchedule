package ru.oat.schedule

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import ru.oat.schedule.ui.OatApp
import ru.oat.schedule.ui.theme.OATScheduleTheme

class MainActivity : ComponentActivity() {
    private val viewModel: OatViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            OATScheduleTheme(appearance = viewModel.appearance) {
                OatApp(viewModel)
            }
        }
    }
}
