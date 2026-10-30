package com.faysarukattil.buddy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.util.Log
import android.util.LruCache
import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

object BuddyChartRenderer {

    private const val TAG = "BuddyChartRenderer"

    // Bitmap in-memory LRU cache to keep redraws virtually free (< 1ms)
    private val bitmapCache = object : LruCache<String, Bitmap>(16) {
        override fun sizeOf(key: String, bitmap: Bitmap): Int {
            return bitmap.byteCount / 1024
        }
    }

    data class CategorySlice(
        val name: String,
        val amount: Double,
        val color: Int
    )

    // ==========================================
    // 1. NATIVE DONUT CHART & LINE BREAKDOWN
    // ==========================================
    fun renderDonutChart(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        isDark: Boolean,
        mode: String, // "spending" or "earning"
        txnsJson: String?,
        colorsJson: String?
    ): Bitmap? {
        if (widthPx <= 0 || heightPx <= 0) return null

        val dataHash = (txnsJson?.hashCode() ?: 0).toString()
        val cacheKey = "donut_${mode}_${widthPx}_${heightPx}_${isDark}_${dataHash}"
        bitmapCache.get(cacheKey)?.let { cached ->
            if (!cached.isRecycled) return cached
        }

        try {
            val density = context.resources.displayMetrics.density
            val now = Calendar.getInstance()
            val curYear = now.get(Calendar.YEAR)
            val curMonth = now.get(Calendar.MONTH) + 1

            val isExpense = mode.equals("spending", ignoreCase = true)
            val categoryAmounts = mutableMapOf<String, Double>()
            val categoryColors = mutableMapOf<String, Int>()

            // Parse colors
            if (!colorsJson.isNullOrEmpty()) {
                try {
                    val colorsObj = JSONObject(colorsJson)
                    colorsObj.keys().forEach { cat ->
                        val hex = colorsObj.optString(cat, "")
                        if (hex.isNotEmpty()) {
                            try {
                                categoryColors[cat] = Color.parseColor(if (hex.startsWith("#")) hex else "#$hex")
                            } catch (_: Exception) {}
                        }
                    }
                } catch (_: Exception) {}
            }

            // Aggregate month transactions
            if (!txnsJson.isNullOrEmpty()) {
                val arr = JSONArray(txnsJson)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val y = obj.optInt("year")
                    val m = obj.optInt("month")
                    if (y == curYear && m == curMonth) {
                        val isIncome = obj.optBoolean("is_income", false)
                        if (isExpense == !isIncome) {
                            val cat = obj.optString("category", "Other")
                            val amt = obj.optDouble("amount", 0.0)
                            categoryAmounts[cat] = (categoryAmounts[cat] ?: 0.0) + amt
                            if (!categoryColors.containsKey(cat)) {
                                val colHex = obj.optString("color", "")
                                if (colHex.isNotEmpty()) {
                                    try {
                                        categoryColors[cat] = Color.parseColor(if (colHex.startsWith("#")) colHex else "#$colHex")
                                    } catch (_: Exception) {}
                                }
                            }
                        }
                    }
                }
            }

            // Build Slices: Top 5 + Others
            val sorted = categoryAmounts.entries.sortedByDescending { it.value }
            val top5 = sorted.take(5)
            val othersSum = sorted.drop(5).sumOf { it.value }
            var totalAmount = sorted.sumOf { it.value }

            val slices = mutableListOf<CategorySlice>()
            for (e in top5) {
                val color = categoryColors[e.key] ?: getDefaultCategoryColor(e.key)
                slices.add(CategorySlice(e.key, e.value, color))
            }
            if (othersSum > 0) {
                slices.add(CategorySlice("Others", othersSum, 0xFF90A4AE.toInt()))
            }

            // Create transparent ARGB bitmap
            val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            val textColor = if (isDark) 0xFFFFFFFF.toInt() else 0xFF1C1C1E.toInt()
            val textMuted = if (isDark) 0x99EBEBF5.toInt() else 0x993C3C43.toInt()
            val trackColor = if (isDark) 0x1AFFFFFF.toInt() else 0x14000000.toInt()

            val isWide = (widthPx >= 180f * density || widthPx >= heightPx * 0.9f) && slices.isNotEmpty() && totalAmount > 0

            if (isWide) {
                // Wide layout: Donut on left, Ledger on right - uses full width
                val donutDiameter = min(heightPx - 8f * density, widthPx * 0.44f).coerceAtLeast(60f * density)
                val donutCx = 8f * density + donutDiameter / 2f
                val donutCy = heightPx / 2f

                drawDonutRing(
                    canvas, donutCx, donutCy, donutDiameter, slices, totalAmount,
                    isExpense, isDark, textColor, textMuted, density
                )

                // Ledger on right
                val ledgerLeft = donutCx + donutDiameter / 2f + 10f * density
                val ledgerWidth = widthPx - ledgerLeft - 6f * density
                if (ledgerWidth > 50f * density) {
                    drawLedgerBreakdown(
                        canvas, ledgerLeft, 4f * density, ledgerWidth, heightPx - 8f * density,
                        slices, totalAmount, textColor, textMuted, trackColor, density
                    )
                }
            } else {
                // Centered Donut layout (when no ledger or narrow width)
                val donutDiameter = min(widthPx - 16f * density, heightPx - 8f * density).coerceAtLeast(60f * density)
                val donutCx = widthPx / 2f
                val donutCy = heightPx / 2f

                drawDonutRing(
                    canvas, donutCx, donutCy, donutDiameter, slices, totalAmount,
                    isExpense, isDark, textColor, textMuted, density
                )
            }

            bitmapCache.put(cacheKey, bitmap)
            return bitmap
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error rendering native donut chart: ${e.message}", e)
            return null
        }
    }

    private fun drawDonutRing(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        diameter: Float,
        slices: List<CategorySlice>,
        total: Double,
        isExpense: Boolean,
        isDark: Boolean,
        textColor: Int,
        textMuted: Int,
        density: Float
    ) {
        val strokeWidth = diameter * 0.14f
        val radius = (diameter - strokeWidth) / 2f
        val oval = RectF(cx - radius, cy - radius, cx + radius, cy + radius)

        val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
            strokeCap = Paint.Cap.ROUND
        }

        if (total <= 0 || slices.isEmpty()) {
            arcPaint.color = if (isDark) 0x22FFFFFF.toInt() else 0x14000000.toInt()
            canvas.drawCircle(cx, cy, radius, arcPaint)
        } else {
            var currentAngle = -90f
            val gapAngle = 3.5f

            for (s in slices) {
                val sweep = ((s.amount / total) * 360f).toFloat()
                val actualSweep = max(0.5f, sweep - gapAngle)

                arcPaint.color = s.color
                canvas.drawArc(oval, currentAngle + gapAngle / 2f, actualSweep, false, arcPaint)
                currentAngle += sweep
            }
        }

        // Center typography: Mode label + Total Amount + Category count
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        }

        val modeStr = if (isExpense) "Spent" else "Earned"
        textPaint.color = textMuted
        textPaint.textSize = (diameter * 0.09f).coerceIn(8f * density, 12f * density)
        canvas.drawText(modeStr, cx, cy - diameter * 0.10f, textPaint)

        // Amount
        val currencyFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN"))
        currencyFormat.maximumFractionDigits = 0
        val amountStr = currencyFormat.format(total)

        textPaint.color = textColor
        textPaint.textSize = (diameter * 0.15f).coerceIn(11f * density, 20f * density)
        // Auto-shrink text if amount string is wide
        val textWidth = textPaint.measureText(amountStr)
        val maxAllowedWidth = diameter * 0.65f
        if (textWidth > maxAllowedWidth && textWidth > 0) {
            textPaint.textSize *= (maxAllowedWidth / textWidth)
        }
        canvas.drawText(amountStr, cx, cy + diameter * 0.06f, textPaint)

        // Category count
        textPaint.color = textMuted
        textPaint.textSize = (diameter * 0.08f).coerceIn(7.5f * density, 11f * density)
        canvas.drawText("${slices.size} categories", cx, cy + diameter * 0.19f, textPaint)
    }

    private fun drawLedgerBreakdown(
        canvas: Canvas,
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        slices: List<CategorySlice>,
        total: Double,
        textColor: Int,
        textMuted: Int,
        trackColor: Int,
        density: Float
    ) {
        val rowHeight = (height / min(slices.size.coerceAtLeast(1), 4)).coerceIn(18f * density, 24f * density)
        val maxRows = min(slices.size, floor(height / rowHeight).toInt())
        if (maxRows <= 0) return

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            textSize = 10.5f * density
        }

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

        val currencyFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN"))
        currencyFormat.maximumFractionDigits = 0

        var currentY = y

        for (i in 0 until maxRows) {
            val s = slices[i]
            val pct = if (total > 0) (s.amount / total * 100).toInt() else 0

            // 1. Color Squircle / Dot
            trackPaint.color = s.color
            val dotRadius = 3.5f * density
            canvas.drawCircle(x + dotRadius, currentY + 7f * density, dotRadius, trackPaint)

            // 2. Category Name
            textPaint.typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            textPaint.color = textColor
            textPaint.textAlign = Paint.Align.LEFT
            textPaint.textSize = 10.5f * density
            val nameX = x + dotRadius * 2 + 6f * density

            // 3. Amount & Pct on Right
            val amountStr = currencyFormat.format(s.amount)
            val pctStr = "$pct%"
            textPaint.textAlign = Paint.Align.RIGHT
            textPaint.color = textColor
            canvas.drawText(amountStr, x + width, currentY + 10f * density, textPaint)

            textPaint.color = textMuted
            textPaint.textSize = 9.5f * density
            val pctWidth = textPaint.measureText(pctStr)
            val amountWidth = textPaint.measureText(amountStr)
            canvas.drawText(pctStr, x + width - amountWidth - 8f * density, currentY + 10f * density, textPaint)

            // Truncate name if it collides with right side
            textPaint.textAlign = Paint.Align.LEFT
            textPaint.color = textColor
            textPaint.textSize = 10.5f * density
            val maxNameWidth = width - amountWidth - pctWidth - 24f * density
            val truncatedName = truncateText(s.name, textPaint, maxNameWidth)
            canvas.drawText(truncatedName, nameX, currentY + 10f * density, textPaint)

            // 4. Progress Bar
            val barY = currentY + 15f * density
            val barHeight = 3.5f * density
            val barTrackWidth = width

            // Background Track
            trackPaint.color = trackColor
            val trackRect = RectF(x, barY, x + barTrackWidth, barY + barHeight)
            canvas.drawRoundRect(trackRect, 2f * density, 2f * density, trackPaint)

            // Progress Fill
            val fillWidth = if (total > 0) (barTrackWidth * (s.amount / total).toFloat()).coerceAtLeast(3f * density) else 0f
            trackPaint.color = s.color
            val fillRect = RectF(x, barY, x + fillWidth, barY + barHeight)
            canvas.drawRoundRect(fillRect, 2f * density, 2f * density, trackPaint)

            currentY += rowHeight
        }
    }

    // ==========================================
    // 2. NATIVE CALENDAR HEATMAP
    // ==========================================
    fun renderHeatmapChart(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        isDark: Boolean,
        mode: String, // "expense" or "income"
        txnsJson: String?
    ): Bitmap? {
        if (widthPx <= 0 || heightPx <= 0) return null

        val dataHash = (txnsJson?.hashCode() ?: 0).toString()
        val cacheKey = "heatmap_${mode}_${widthPx}_${heightPx}_${isDark}_${dataHash}"
        bitmapCache.get(cacheKey)?.let { cached ->
            if (!cached.isRecycled) return cached
        }

        try {
            val density = context.resources.displayMetrics.density
            val now = Calendar.getInstance()
            val curYear = now.get(Calendar.YEAR)
            val curMonth = now.get(Calendar.MONTH) + 1
            val curDay = now.get(Calendar.DAY_OF_MONTH)

            val isIncomeMode = mode.equals("income", ignoreCase = true)
            val dailyAmounts = mutableMapOf<Int, Double>()

            if (!txnsJson.isNullOrEmpty()) {
                val arr = JSONArray(txnsJson)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val y = obj.optInt("year")
                    val m = obj.optInt("month")
                    if (y == curYear && m == curMonth) {
                        val isIncome = obj.optBoolean("is_income", false)
                        if (isIncome == isIncomeMode) {
                            val d = obj.optInt("day")
                            val amt = obj.optDouble("amount", 0.0)
                            dailyAmounts[d] = (dailyAmounts[d] ?: 0.0) + amt
                        }
                    }
                }
            }

            val maxVal = if (dailyAmounts.values.isNotEmpty()) dailyAmounts.values.maxOrNull() ?: 0.0 else 0.0

            // Calendar Math: Weekday Alignment Mon-Sun
            val cal = Calendar.getInstance().apply {
                set(Calendar.YEAR, curYear)
                set(Calendar.MONTH, curMonth - 1)
                set(Calendar.DAY_OF_MONTH, 1)
            }
            // In Java Calendar: Sun = 1, Mon = 2, ..., Sat = 7
            // Convert to Mon = 0 .. Sun = 6
            val firstDayDow = cal.get(Calendar.DAY_OF_WEEK)
            val lead = (firstDayDow + 5) % 7
            val daysInMonth = cal.getActualMaximum(Calendar.DAY_OF_MONTH)

            val totalCells = lead + daysInMonth
            val rows = ceil(totalCells / 7.0).toInt().coerceAtLeast(5)

            val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            val textColor = if (isDark) 0xFFFFFFFF.toInt() else 0xFF1C1C1E.toInt()
            val textMuted = if (isDark) 0x99EBEBF5.toInt() else 0x993C3C43.toInt()
            val emptyCellBg = if (isDark) 0x14FFFFFF.toInt() else 0x0A000000.toInt()
            val accentColor = if (isIncomeMode) 0xFF34D399.toInt() else 0xFFFB7185.toInt()

            val headerHeight = 13f * density
            val gridTop = headerHeight + 2f * density
            val gridHeight = heightPx - gridTop - 2f * density
            val colWidth = widthPx / 7f
            val rowHeight = gridHeight / rows
            val cellGap = 2f * density

            val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textAlign = Paint.Align.CENTER
                typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            }

            val cellPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.FILL
            }

            val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = 1.4f * density
                color = textColor
            }

            // 1. Draw Weekday Headers: M T W T F S S
            val weekdays = arrayOf("M", "T", "W", "T", "F", "S", "S")
            textPaint.color = textMuted
            textPaint.textSize = (headerHeight * 0.65f).coerceIn(8f * density, 11f * density)

            for (c in 0 until 7) {
                val headerX = c * colWidth + colWidth / 2f
                canvas.drawText(weekdays[c], headerX, headerHeight * 0.75f, textPaint)
            }

            // 2. Draw Month Grid Cells
            val canFitAmount = rowHeight >= 26f * density && colWidth >= 26f * density
            val canFitDayOnly = rowHeight >= 14f * density

            for (day in 1..daysInMonth) {
                val index = lead + (day - 1)
                val c = index % 7
                val r = index / 7

                val left = c * colWidth + cellGap / 2f
                val top = gridTop + r * rowHeight + cellGap / 2f
                val right = (c + 1) * colWidth - cellGap / 2f
                val bottom = gridTop + (r + 1) * rowHeight - cellGap / 2f

                val cellRect = RectF(left, top, right, bottom)
                val cornerRadius = (rowHeight * 0.20f).coerceIn(3.5f * density, 7f * density)

                val amt = dailyAmounts[day] ?: 0.0
                val intensity = if (maxVal > 0 && amt > 0) (amt / maxVal).coerceIn(0.25, 1.0) else 0.0
                val isToday = (day == curDay)
                val isFuture = (day > curDay)

                // Fill color
                if (intensity > 0) {
                    val alpha = (60 + intensity * 190).toInt().coerceIn(60, 245)
                    cellPaint.color = Color.argb(alpha, Color.red(accentColor), Color.green(accentColor), Color.blue(accentColor))
                } else {
                    cellPaint.color = if (isFuture) (emptyCellBg and 0x00FFFFFF) or 0x08000000 else emptyCellBg
                }
                canvas.drawRoundRect(cellRect, cornerRadius, cornerRadius, cellPaint)

                // Outline today
                if (isToday) {
                    canvas.drawRoundRect(cellRect, cornerRadius, cornerRadius, borderPaint)
                }

                // Typography
                val cx = cellRect.centerX()
                if (canFitAmount && amt > 0) {
                    // Day number on top, amount on bottom
                    textPaint.color = if (intensity > 0.45) 0xFFFFFFFF.toInt() else textColor
                    textPaint.textSize = (rowHeight * 0.32f).coerceIn(8f * density, 11f * density)
                    canvas.drawText("$day", cx, cellRect.top + rowHeight * 0.38f, textPaint)

                    val compactStr = formatCompact(amt)
                    textPaint.textSize = (rowHeight * 0.28f).coerceIn(7f * density, 9.5f * density)
                    textPaint.color = if (intensity > 0.45) 0xEEFFFFFF.toInt() else textMuted
                    canvas.drawText(compactStr, cx, cellRect.bottom - rowHeight * 0.16f, textPaint)
                } else if (canFitDayOnly) {
                    // Day number centered
                    textPaint.color = if (intensity > 0.45) 0xFFFFFFFF.toInt() else (if (isFuture) textMuted else textColor)
                    textPaint.textSize = (rowHeight * 0.42f).coerceIn(8f * density, 12f * density)
                    val textY = cellRect.centerY() + textPaint.textSize * 0.35f
                    canvas.drawText("$day", cx, textY, textPaint)
                }
            }

            bitmapCache.put(cacheKey, bitmap)
            return bitmap
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error rendering native heatmap chart: ${e.message}", e)
            return null
        }
    }

    private fun truncateText(text: String, paint: Paint, maxWidth: Float): String {
        if (paint.measureText(text) <= maxWidth) return text
        var end = text.length - 1
        while (end > 0) {
            val candidate = text.substring(0, end) + "…"
            if (paint.measureText(candidate) <= maxWidth) return candidate
            end--
        }
        return text
    }

    private fun formatCompact(value: Double): String {
        if (value <= 0) return ""
        return when {
            value >= 10000000 -> String.format(Locale.US, "%.1fCr", value / 10000000)
            value >= 100000 -> String.format(Locale.US, "%.1fL", value / 100000)
            value >= 1000 -> String.format(Locale.US, "%.1fK", value / 1000)
            else -> String.format(Locale.US, "%.0f", value)
        }
    }

    private fun getDefaultCategoryColor(category: String): Int {
        val norm = category.lowercase().trim()
        return when {
            norm.contains("food") || norm.contains("dining") || norm.contains("swiggy") || norm.contains("zomato") -> 0xFFFF7A45.toInt()
            norm.contains("grocer") || norm.contains("zepto") || norm.contains("instamart") || norm.contains("blinkit") -> 0xFF43A047.toInt()
            norm.contains("shop") || norm.contains("amazon") || norm.contains("flipkart") || norm.contains("myntra") -> 0xFFFF9900.toInt()
            norm.contains("transport") || norm.contains("uber") || norm.contains("ola") || norm.contains("rapido") -> 0xFF3F51B5.toInt()
            norm.contains("fuel") || norm.contains("petrol") || norm.contains("diesel") -> 0xFFE65100.toInt()
            norm.contains("movie") || norm.contains("netflix") || norm.contains("youtube") || norm.contains("spotify") -> 0xFFE50914.toInt()
            norm.contains("bill") || norm.contains("recharge") || norm.contains("wifi") || norm.contains("electricity") -> 0xFF009688.toInt()
            norm.contains("medical") || norm.contains("health") || norm.contains("doctor") -> 0xFF00BCD4.toInt()
            norm.contains("education") || norm.contains("college") || norm.contains("school") -> 0xFF5E35B1.toInt()
            norm.contains("rent") || norm.contains("home") || norm.contains("flat") -> 0xFF795548.toInt()
            norm.contains("coffee") || norm.contains("cafe") -> 0xFF4E342E.toInt()
            norm.contains("gift") || norm.contains("charity") -> 0xFFF06292.toInt()
            else -> 0xFF90A4AE.toInt()
        }
    }
}

