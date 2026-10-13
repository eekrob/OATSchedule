package ru.oat.schedule.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

class OatHttpClient {
    suspend fun get(url: String): String = withContext(Dispatchers.IO) {
        val started = System.currentTimeMillis()
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 12_000
            readTimeout = 15_000
            instanceFollowRedirects = true
            useCaches = false
            setRequestProperty(
                "User-Agent",
                "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36 OATSchedule/1.0"
            )
            setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            setRequestProperty("Accept-Language", "ru-RU,ru;q=0.9,en;q=0.6")
            setRequestProperty("Cache-Control", "no-cache")
            setRequestProperty("Pragma", "no-cache")
        }

        try {
            val status = connection.responseCode
            val finalUrl = connection.url.toString()
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()

            DiagnosticsLog.add(
                "HTTP",
                "requested: $url\nfinal: $finalUrl\nstatus: $status\nbytes: ${body.toByteArray().size}\nms: ${System.currentTimeMillis() - started}"
            )

            if (status !in 200..299) {
                throw IOException("OAT вернул HTTP $status")
            }
            if (body.isBlank()) {
                throw IOException("OAT вернул пустой ответ")
            }
            body
        } finally {
            connection.disconnect()
        }
    }
}
