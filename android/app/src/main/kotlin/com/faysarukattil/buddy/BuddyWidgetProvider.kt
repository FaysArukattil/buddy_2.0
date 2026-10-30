package com.faysarukattil.buddy

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

class BuddyWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val TAG = "BuddyWidgetProvider"
        const val ACTION_MIDNIGHT_UPDATE = "com.faysarukattil.buddy.ACTION_MIDNIGHT_UPDATE"
        const val ACTION_SWITCH_PAGE = "com.faysarukattil.buddy.ACTION_SWITCH_PAGE"
        const val ACTION_TOGGLE_STATS_MODE = "com.faysarukattil.buddy.ACTION_TOGGLE_STATS_MODE"
        const val ACTION_TOGGLE_DONUT_MODE = "com.faysarukattil.buddy.ACTION_TOGGLE_DONUT_MODE"
        const val ACTION_TOGGLE_HEATMAP_MODE = "com.faysarukattil.buddy.ACTION_TOGGLE_HEATMAP_MODE"
        const val EXTRA_PAGE_INDEX = "extra_page_index"

        private val COLOR_INCOME = 0xFF34D399.toInt()
        private val COLOR_EXPENSE = 0xFFFB7185.toInt()
        private val COLOR_ACCENT = 0xFF2DD4BF.toInt()

        // 8 transaction row view IDs for Today page
        private val ROW_IDS = arrayOf(
            RowIds(R.id.row_txn_0, R.id.tv_txn_0_title, R.id.tv_txn_0_subtitle, R.id.tv_txn_0_amount, R.id.iv_txn_0_icon_bg, R.id.iv_txn_0_icon, R.id.badge_ai_txn_0),
            RowIds(R.id.row_txn_1, R.id.tv_txn_1_title, R.id.tv_txn_1_subtitle, R.id.tv_txn_1_amount, R.id.iv_txn_1_icon_bg, R.id.iv_txn_1_icon, R.id.badge_ai_txn_1),
            RowIds(R.id.row_txn_2, R.id.tv_txn_2_title, R.id.tv_txn_2_subtitle, R.id.tv_txn_2_amount, R.id.iv_txn_2_icon_bg, R.id.iv_txn_2_icon, R.id.badge_ai_txn_2),
            RowIds(R.id.row_txn_3, R.id.tv_txn_3_title, R.id.tv_txn_3_subtitle, R.id.tv_txn_3_amount, R.id.iv_txn_3_icon_bg, R.id.iv_txn_3_icon, R.id.badge_ai_txn_3),
            RowIds(R.id.row_txn_4, R.id.tv_txn_4_title, R.id.tv_txn_4_subtitle, R.id.tv_txn_4_amount, R.id.iv_txn_4_icon_bg, R.id.iv_txn_4_icon, R.id.badge_ai_txn_4),
            RowIds(R.id.row_txn_5, R.id.tv_txn_5_title, R.id.tv_txn_5_subtitle, R.id.tv_txn_5_amount, R.id.iv_txn_5_icon_bg, R.id.iv_txn_5_icon, R.id.badge_ai_txn_5),
            RowIds(R.id.row_txn_6, R.id.tv_txn_6_title, R.id.tv_txn_6_subtitle, R.id.tv_txn_6_amount, R.id.iv_txn_6_icon_bg, R.id.iv_txn_6_icon, R.id.badge_ai_txn_6),
            RowIds(R.id.row_txn_7, R.id.tv_txn_7_title, R.id.tv_txn_7_subtitle, R.id.tv_txn_7_amount, R.id.iv_txn_7_icon_bg, R.id.iv_txn_7_icon, R.id.badge_ai_txn_7)
        )
    }

    private class RowIds(
        val row: Int,
        val title: Int,
        val subtitle: Int,
        val amount: Int,
        val iconBg: Int,
        val icon: Int,
        val badgeAi: Int
    )

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return
        Log.d(TAG, "📡 onReceive action: $action")

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, BuddyWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        val data = HomeWidgetPlugin.getData(context)

        when (action) {
            ACTION_MIDNIGHT_UPDATE, Intent.ACTION_BOOT_COMPLETED -> {
                scheduleMidnightAlarm(context)
                refreshDataFromCachedJson(context, data)
                appWidgetIds.forEach { id ->
                    render(context, appWidgetManager, id, data)
                }
            }

            ACTION_SWITCH_PAGE -> {
                val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                val targetPage = intent.getIntExtra(EXTRA_PAGE_INDEX, 0)
                if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    data.edit().putInt("active_page_$widgetId", targetPage).apply()
                    render(context, appWidgetManager, widgetId, data)
                } else {
                    appWidgetIds.forEach { id ->
                        data.edit().putInt("active_page_$id", targetPage).apply()
                        render(context, appWidgetManager, id, data)
                    }
                }
            }

            ACTION_TOGGLE_DONUT_MODE, ACTION_TOGGLE_STATS_MODE -> {
                val currentMode = data.getString("donut_chart_mode", "spending") ?: "spending"
                val newMode = if (currentMode == "spending") "earning" else "spending"
                data.edit().putString("donut_chart_mode", newMode).apply()
                appWidgetIds.forEach { id ->
                    render(context, appWidgetManager, id, data)
                }
            }

            ACTION_TOGGLE_HEATMAP_MODE -> {
                val currentMode = data.getString("heatmap_chart_mode", "expense") ?: "expense"
                val newMode = if (currentMode == "expense") "income" else "expense"
                data.edit().putString("heatmap_chart_mode", newMode).apply()
                appWidgetIds.forEach { id ->
                    render(context, appWidgetManager, id, data)
                }
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        scheduleMidnightAlarm(context)
        appWidgetIds.forEach { widgetId ->
            render(context, appWidgetManager, widgetId, widgetData)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    // ==========================================
    // 📐 ORIENTATION-AWARE SIZE CALCULATION
    // ==========================================
    private fun getWidgetSizeDp(context: Context, manager: AppWidgetManager, widgetId: Int): Pair<Int, Int> {
        val options = manager.getAppWidgetOptions(widgetId)
        val isLandscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

        var widthDp = if (isLandscape) {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        } else {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        }

        var heightDp = if (isLandscape) {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        } else {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        }

        if (widthDp <= 0) {
            widthDp = max(
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
            )
        }
        if (heightDp <= 0) {
            heightDp = max(
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
            )
        }

        // Android 12+ (API 31+) size query
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val sizes = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
            if (!sizes.isNullOrEmpty()) {
                val currentSize = sizes.firstOrNull()
                if (currentSize != null) {
                    widthDp = currentSize.width.toInt()
                    heightDp = currentSize.height.toInt()
                }
            }
        }

        if (widthDp <= 0) widthDp = 280
        if (heightDp <= 0) heightDp = 180

        return Pair(widthDp, heightDp)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences
    ) {
        try {
            val (widthDp, heightDp) = getWidgetSizeDp(context, manager, widgetId)
            val isDark = isDarkTheme(context)
            val density = context.resources.displayMetrics.density

            val widthClass = when {
                widthDp < 180 -> "narrow"
                widthDp < 320 -> "normal"
                widthDp < 440 -> "wide"
                else -> "xwide"
            }
            val heightClass = when {
                heightDp < 120 -> "tiny"
                heightDp < 180 -> "short"
                heightDp < 260 -> "medium"
                heightDp < 360 -> "tall"
                else -> "xtall"
            }

            val activePage = data.getInt("active_page_$widgetId", 0).coerceIn(0, 3)
            Log.d(TAG, "📏 Size: ${widthDp}w x ${heightDp}h dp | Class: $widthClass x $heightClass | Active Page: $activePage")

            // 1. Tiny Layout Check (< 180x120dp)
            if (widthDp < 180 || heightDp < 120) {
                val smallViews = buildSmallLayout(context, widgetId, data)
                manager.updateAppWidget(widgetId, smallViews)
                return
            }

            // 2. Full Main Multi-Page Layout
            val views = RemoteViews(context.packageName, R.layout.widget_buddy)
            views.setDisplayedChild(R.id.flipper_pages, activePage)

            // Adaptive Header & Branding (Section 6)
            bindHeaderAndBranding(views, widthDp)

            // Segmented Tab Switcher (Section 4)
            updateTabBar(views, activePage, widthDp, isDark)

            // Bind Page 0: Today (Kept unchanged, Section 1 & 7)
            bindTodayPage(context, views, heightDp, data)

            // Bind Page 1: Month (Three Tiles, Adaptive arrangement, Section 1)
            bindMonthPage(views, widthDp, heightDp, data, isDark)

            // Bind Page 2: Donut (Native Canvas + Line Breakdown, Section 2)
            bindDonutPage(context, views, widthDp, heightDp, data, isDark, density)

            // Bind Page 3: Heatmap (Native Canvas + Scaled Cells, Section 3)
            bindHeatmapPage(context, views, widthDp, heightDp, data, isDark, density)

            // Attach PendingIntents specifically for main layout views
            attachMainIntents(context, widgetId, views)

            manager.updateAppWidget(widgetId, views)
        } catch (e: Exception) {
            Log.e(TAG, "❌ FATAL error rendering widget $widgetId: ${e.message}", e)
        }
    }

    // ==========================================
    // 1. HEADER & BRANDING (Section 6)
    // ==========================================
    private fun bindHeaderAndBranding(views: RemoteViews, widthDp: Int) {
        if (widthDp < 240) {
            // Drop wordmark on narrow widths, keep squircle icon
            views.setViewVisibility(R.id.layout_brand_text, View.GONE)
        } else {
            views.setViewVisibility(R.id.layout_brand_text, View.VISIBLE)
            if (widthDp >= 320) {
                views.setViewVisibility(R.id.tv_today_date, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.tv_today_date, View.GONE)
            }
        }
    }

    // ==========================================
    // 2. SEGMENTED TAB SWITCHER (Section 4)
    // ==========================================
    private fun updateTabBar(views: RemoteViews, activePage: Int, widthDp: Int, isDark: Boolean) {
        val tabIds = arrayOf(R.id.tab_btn_today, R.id.tab_btn_month, R.id.tab_btn_donut, R.id.tab_btn_heatmap)
        val iconIds = arrayOf(R.id.iv_tab_today_icon, R.id.iv_tab_month_icon, R.id.iv_tab_donut_icon, R.id.iv_tab_heatmap_icon)
        val labelIds = arrayOf(R.id.tv_tab_today_label, R.id.tv_tab_month_label, R.id.tv_tab_donut_label, R.id.tv_tab_heatmap_label)

        val activeTextColor = if (isDark) 0xFF2DD4BF.toInt() else 0xFF1E5D57.toInt()
        val inactiveTextColor = if (isDark) 0x99EBEBF5.toInt() else 0x993C3C43.toInt()

        val showLabels = widthDp >= 290

        for (i in tabIds.indices) {
            val isActive = (i == activePage)
            views.setInt(tabIds[i], "setBackgroundResource", if (isActive) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive)
            views.setInt(iconIds[i], "setColorFilter", if (isActive) activeTextColor else inactiveTextColor)

            if (showLabels) {
                views.setViewVisibility(labelIds[i], View.VISIBLE)
                views.setTextColor(labelIds[i], if (isActive) activeTextColor else inactiveTextColor)
            } else {
                views.setViewVisibility(labelIds[i], View.GONE)
            }
        }
    }

    // ==========================================
    // 3. PAGE 0: TODAY (Unchanged, Responsive Rows)
    // ==========================================
    private fun bindTodayPage(
        context: Context,
        views: RemoteViews,
        heightDp: Int,
        data: SharedPreferences
    ) {
        val dateLabel = data.getString("today_date_label", "Today") ?: "Today"
        val spentToday = data.getString("today_spent", "₹0") ?: "₹0"
        val incomeToday = data.getString("today_income_formatted", "+₹0") ?: "+₹0"

        views.setTextViewText(R.id.tv_today_date, dateLabel)
        views.setTextViewText(R.id.tv_hero_spent, spentToday)
        views.setTextViewText(R.id.tv_hero_earned, incomeToday)

        val todayTxnsCount = data.getInt("today_count", 0)

        if (todayTxnsCount <= 0) {
            views.setViewVisibility(R.id.layout_empty_txns, View.VISIBLE)
            views.setViewVisibility(R.id.layout_txns_container, View.GONE)
            return
        }

        views.setViewVisibility(R.id.layout_empty_txns, View.GONE)
        views.setViewVisibility(R.id.layout_txns_container, View.VISIBLE)

        val availableListHeightDp = max(0, heightDp - 194)
        val maxWholeRows = min(8, floor(availableListHeightDp / 56.0).toInt())

        var visibleCount = 0
        for (i in 0 until 8) {
            val rowId = ROW_IDS[i]
            val exists = (i < maxWholeRows) && data.getBoolean("txn_${i}_exists", false)

            if (exists) {
                views.setViewVisibility(rowId.row, View.VISIBLE)
                bindRow(views, i, rowId, data)
                visibleCount++
            } else {
                views.setViewVisibility(rowId.row, View.GONE)
            }
        }

        val overflow = todayTxnsCount - visibleCount
        if (overflow > 0) {
            views.setViewVisibility(R.id.tv_more_txns_hint, View.VISIBLE)
            views.setTextViewText(R.id.tv_more_txns_hint, "+$overflow more · tap to open Buddy")
        } else {
            views.setViewVisibility(R.id.tv_more_txns_hint, View.GONE)
        }
    }

    private fun bindRow(views: RemoteViews, index: Int, ids: RowIds, data: SharedPreferences) {
        val title = data.getString("txn_${index}_title", "Transaction") ?: "Transaction"
        val subtitle = data.getString("txn_${index}_subtitle", "") ?: ""
        val amount = data.getString("txn_${index}_amount", "₹0") ?: "₹0"
        val category = data.getString("txn_${index}_category", "Other") ?: "Other"
        val isIncome = data.getBoolean("txn_${index}_is_income", false)
        val isAuto = data.getBoolean("txn_${index}_is_auto", false)

        val catColor = parseColor(data, "txn_${index}_color", if (isIncome) COLOR_INCOME else COLOR_EXPENSE)
        val catDrawable = getCategoryDrawable(category, isIncome)

        views.setTextViewText(ids.title, title)
        views.setTextViewText(ids.subtitle, subtitle)
        views.setTextViewText(ids.amount, amount)
        views.setTextColor(ids.amount, if (isIncome) COLOR_INCOME else COLOR_EXPENSE)

        views.setImageViewResource(ids.icon, catDrawable)
        views.setInt(ids.icon, "setColorFilter", catColor)

        views.setImageViewResource(ids.iconBg, R.drawable.widget_cat_bg)
        views.setInt(ids.iconBg, "setColorFilter", catColor)
        views.setInt(ids.iconBg, "setImageAlpha", 45)

        views.setInt(
            ids.row,
            "setBackgroundResource",
            if (isAuto) R.drawable.widget_row_ai_bg else R.drawable.widget_row_bg
        )
        views.setViewVisibility(ids.badgeAi, if (isAuto) View.VISIBLE else View.GONE)
    }

    // ==========================================
    // 4. PAGE 1: MONTH (Section 1: Three Tiles, No Transaction List)
    // ==========================================
    private fun bindMonthPage(
        views: RemoteViews,
        widthDp: Int,
        heightDp: Int,
        data: SharedPreferences,
        isDark: Boolean
    ) {
        val monthName = data.getString("month_name", "Month") ?: "Month"
        val monthSpent = data.getString("month_spent", "₹0") ?: "₹0"
        val monthEarned = data.getString("month_income", "+₹0") ?: "+₹0"
        val monthBalance = data.getString("month_balance", "₹0") ?: "₹0"
        val isNegative = data.getBoolean("month_is_negative", false)
        val delta = data.getString("month_delta", "+0.0% vs last mo") ?: "+0.0% vs last mo"

        val balanceColor = if (isNegative) COLOR_EXPENSE else (if (isDark) 0xFF2DD4BF.toInt() else 0xFF1E5D57.toInt())
        val balanceLabel = if (isNegative) "$monthName · Deficit" else "$monthName · Balance"

        // Adaptive arrangement:
        // Wide and short = 3 equal columns in one row
        // Medium / tall = Hero Balance on top, Spent & Earned side by side below
        val isWideAndShort = widthDp >= 320 && heightDp < 200

        if (isWideAndShort) {
            views.setViewVisibility(R.id.layout_month_3_col, View.VISIBLE)
            views.setViewVisibility(R.id.layout_month_hero_plus_dual, View.GONE)

            views.setTextViewText(R.id.tv_month_3col_spent_label, "$monthName · SPENT".uppercase())
            views.setTextViewText(R.id.tv_month_3col_spent, monthSpent)

            views.setTextViewText(R.id.tv_month_3col_earned_label, "$monthName · EARNED".uppercase())
            views.setTextViewText(R.id.tv_month_3col_earned, monthEarned)

            views.setTextViewText(R.id.tv_month_3col_balance_label, balanceLabel.uppercase())
            views.setTextViewText(R.id.tv_month_3col_balance, monthBalance)
            views.setTextColor(R.id.tv_month_3col_balance, balanceColor)
            views.setInt(R.id.iv_month_3col_balance_icon, "setColorFilter", balanceColor)
        } else {
            views.setViewVisibility(R.id.layout_month_3_col, View.GONE)
            views.setViewVisibility(R.id.layout_month_hero_plus_dual, View.VISIBLE)

            // Hero Balance on Top
            views.setTextViewText(R.id.tv_month_balance_hero_label, balanceLabel.uppercase())
            views.setTextViewText(R.id.tv_month_hero_balance, monthBalance)
            views.setTextColor(R.id.tv_month_hero_balance, balanceColor)
            views.setInt(R.id.iv_month_balance_icon, "setColorFilter", balanceColor)

            // Optional delta chip in larger sizes
            if (heightDp >= 200 || widthDp >= 280) {
                views.setViewVisibility(R.id.tv_month_delta_chip, View.VISIBLE)
                views.setTextViewText(R.id.tv_month_delta_chip, delta)
            } else {
                views.setViewVisibility(R.id.tv_month_delta_chip, View.GONE)
            }

            // Dual Tiles Below: Spent & Earned
            views.setTextViewText(R.id.tv_month_spent_label, "$monthName · SPENT".uppercase())
            views.setTextViewText(R.id.tv_month_spent_value, monthSpent)

            views.setTextViewText(R.id.tv_month_earned_label, "$monthName · EARNED".uppercase())
            views.setTextViewText(R.id.tv_month_earned_value, monthEarned)
        }
    }

    // ==========================================
    // 5. PAGE 2: DONUT (Section 2: Native Canvas + Line Breakdown)
    // ==========================================
    private fun bindDonutPage(
        context: Context,
        views: RemoteViews,
        widthDp: Int,
        heightDp: Int,
        data: SharedPreferences,
        isDark: Boolean,
        density: Float
    ) {
        val donutMode = data.getString("donut_chart_mode", "spending") ?: "spending"
        val isSpending = donutMode.equals("spending", ignoreCase = true)

        val activeColor = if (isDark) 0xFF2DD4BF.toInt() else 0xFF1E5D57.toInt()
        val inactiveColor = if (isDark) 0x99EBEBF5.toInt() else 0x993C3C43.toInt()

        // Segmented Control [ Spending | Earning ] (min 40dp tall)
        views.setInt(R.id.btn_donut_spending, "setBackgroundResource", if (isSpending) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive)
        views.setTextColor(R.id.btn_donut_spending, if (isSpending) activeColor else inactiveColor)

        views.setInt(R.id.btn_donut_earning, "setBackgroundResource", if (!isSpending) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive)
        views.setTextColor(R.id.btn_donut_earning, if (!isSpending) activeColor else inactiveColor)

        // Native Canvas Drawing
        val slotWidthPx = ((widthDp - 32) * density).toInt().coerceAtLeast(100)
        val slotHeightPx = ((heightDp - 150) * density).toInt().coerceAtLeast(100)

        val txnsJson = data.getString("recent_txns_json", null)
        val colorsJson = data.getString("category_colors_json", null)

        val donutBitmap = BuddyChartRenderer.renderDonutChart(
            context, slotWidthPx, slotHeightPx, isDark, donutMode, txnsJson, colorsJson
        )
        if (donutBitmap != null) {
            views.setImageViewBitmap(R.id.iv_stats_donut, donutBitmap)
        }
    }

    // ==========================================
    // 6. PAGE 3: HEATMAP (Section 3: Native Canvas + Exact Sizing)
    // ==========================================
    private fun bindHeatmapPage(
        context: Context,
        views: RemoteViews,
        widthDp: Int,
        heightDp: Int,
        data: SharedPreferences,
        isDark: Boolean,
        density: Float
    ) {
        val heatmapMode = data.getString("heatmap_chart_mode", "expense") ?: "expense"
        val isExpense = heatmapMode.equals("expense", ignoreCase = true)

        val activeColor = if (isDark) 0xFF2DD4BF.toInt() else 0xFF1E5D57.toInt()
        val inactiveColor = if (isDark) 0x99EBEBF5.toInt() else 0x993C3C43.toInt()

        // Segmented Control [ Expense | Income ] (min 40dp tall)
        views.setInt(R.id.btn_heatmap_expense, "setBackgroundResource", if (isExpense) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive)
        views.setTextColor(R.id.btn_heatmap_expense, if (isExpense) activeColor else inactiveColor)

        views.setInt(R.id.btn_heatmap_income, "setBackgroundResource", if (!isExpense) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive)
        views.setTextColor(R.id.btn_heatmap_income, if (!isExpense) activeColor else inactiveColor)

        // Native Canvas Drawing
        val slotWidthPx = ((widthDp - 32) * density).toInt().coerceAtLeast(100)
        val slotHeightPx = ((heightDp - 150) * density).toInt().coerceAtLeast(100)

        val txnsJson = data.getString("recent_txns_json", null)

        val heatmapBitmap = BuddyChartRenderer.renderHeatmapChart(
            context, slotWidthPx, slotHeightPx, isDark, heatmapMode, txnsJson
        )
        if (heatmapBitmap != null) {
            views.setImageViewBitmap(R.id.iv_stats_heatmap, heatmapBitmap)
        }
    }

    // ==========================================
    // 7. SMALL 2x2 LAYOUT (Section 5)
    // ==========================================
    private fun buildSmallLayout(context: Context, widgetId: Int, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_buddy_small)
        val dateLabel = data.getString("today_date_label", "Today") ?: "Today"
        val spentToday = data.getString("today_spent", "₹0") ?: "₹0"
        val incomeToday = data.getString("today_income_formatted", "+₹0") ?: "+₹0"

        views.setTextViewText(R.id.tv_today_date, dateLabel)
        views.setTextViewText(R.id.tv_hero_spent, spentToday)
        views.setTextViewText(R.id.tv_hero_earned, incomeToday)

        attachSmallIntents(context, widgetId, views)
        return views
    }

    private fun attachSmallIntents(context: Context, widgetId: Int, views: RemoteViews) {
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        val addIntent = Intent(context, WidgetAddModalActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val addPi = PendingIntent.getActivity(context, widgetId * 40 + 1, addIntent, piFlags)
        views.setOnClickPendingIntent(R.id.btn_widget_add, addPi)

        val openIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val openPi = PendingIntent.getActivity(context, widgetId * 40 + 2, openIntent, piFlags)
        views.setOnClickPendingIntent(android.R.id.background, openPi)
    }

    // ==========================================
    // 8. MAIN PENDING INTENTS
    // ==========================================
    private fun attachMainIntents(context: Context, widgetId: Int, views: RemoteViews) {
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        // 1. Add Button Action -> Opens Instant Transparent Modal
        val addIntent = Intent(context, WidgetAddModalActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val addPi = PendingIntent.getActivity(context, widgetId * 40 + 1, addIntent, piFlags)
        views.setOnClickPendingIntent(R.id.btn_widget_add, addPi)

        // 2. Widget Background Tap -> Opens Main App (MainActivity)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val openPi = PendingIntent.getActivity(context, widgetId * 40 + 2, openIntent, piFlags)
        views.setOnClickPendingIntent(android.R.id.background, openPi)

        // 3. Tab Buttons (Today: 0, Month: 1, Donut: 2, Heatmap: 3)
        val tabIds = arrayOf(R.id.tab_btn_today, R.id.tab_btn_month, R.id.tab_btn_donut, R.id.tab_btn_heatmap)
        for (i in tabIds.indices) {
            val tabIntent = Intent(context, BuddyWidgetProvider::class.java).apply {
                action = ACTION_SWITCH_PAGE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                putExtra(EXTRA_PAGE_INDEX, i)
            }
            val tabPi = PendingIntent.getBroadcast(context, widgetId * 40 + 10 + i, tabIntent, piFlags)
            views.setOnClickPendingIntent(tabIds[i], tabPi)
        }

        // 4. Donut Segmented Toggle: Spending / Earning
        val donutToggleIntent = Intent(context, BuddyWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_DONUT_MODE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val donutPi = PendingIntent.getBroadcast(context, widgetId * 40 + 5, donutToggleIntent, piFlags)
        views.setOnClickPendingIntent(R.id.btn_donut_spending, donutPi)
        views.setOnClickPendingIntent(R.id.btn_donut_earning, donutPi)

        // 5. Heatmap Segmented Toggle: Expense / Income
        val heatmapToggleIntent = Intent(context, BuddyWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_HEATMAP_MODE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val heatmapPi = PendingIntent.getBroadcast(context, widgetId * 40 + 6, heatmapToggleIntent, piFlags)
        views.setOnClickPendingIntent(R.id.btn_heatmap_expense, heatmapPi)
        views.setOnClickPendingIntent(R.id.btn_heatmap_income, heatmapPi)
    }

    // ==========================================
    // 9. MIDNIGHT SCHEDULER & NATIVE DATA ROLLOVER
    // ==========================================
    private fun scheduleMidnightAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val midnightIntent = Intent(context, BuddyWidgetProvider::class.java).apply {
            action = ACTION_MIDNIGHT_UPDATE
        }
        val pi = PendingIntent.getBroadcast(
            context,
            9999,
            midnightIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val cal = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 5)
            set(Calendar.MILLISECOND, 0)
        }

        try {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
            Log.d(TAG, "⏰ Midnight alarm scheduled for: ${cal.time}")
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Failed to schedule midnight alarm: ${e.message}")
        }
    }

    private fun refreshDataFromCachedJson(context: Context, data: SharedPreferences) {
        val jsonStr = data.getString("recent_txns_json", null) ?: return
        try {
            val arr = JSONArray(jsonStr)
            val now = Calendar.getInstance()
            val curYear = now.get(Calendar.YEAR)
            val curMonth = now.get(Calendar.MONTH) + 1
            val curDay = now.get(Calendar.DAY_OF_MONTH)

            var todaySpent = 0.0
            var todayEarned = 0.0
            var todayCount = 0
            val todayTxns = mutableListOf<JSONObject>()

            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val isDebt = obj.optBoolean("is_debt", false)
                if (isDebt) continue // Today page always excludes debts

                val y = obj.optInt("year")
                val m = obj.optInt("month")
                val d = obj.optInt("day")
                if (y == curYear && m == curMonth && d == curDay) {
                    val amount = obj.optDouble("amount", 0.0)
                    val isIncome = obj.optBoolean("is_income", false)
                    todayCount++
                    if (isIncome) {
                        todayEarned += amount
                    } else {
                        todaySpent += amount
                    }
                    todayTxns.add(obj)
                }
            }

            val editor = data.edit()
            val currencyFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN"))
            editor.putString("today_spent", currencyFormat.format(todaySpent))
            editor.putString("today_income_formatted", "+${currencyFormat.format(todayEarned)}")
            editor.putInt("today_count", todayCount)
            val dateFmt = SimpleDateFormat("EEE, d MMM", Locale.getDefault())
            editor.putString("today_date_label", dateFmt.format(Date()))

            for (i in 0 until 8) {
                if (i < todayTxns.size) {
                    val obj = todayTxns[i]
                    editor.putBoolean("txn_${i}_exists", true)
                    editor.putString("txn_${i}_title", obj.optString("title", "Transaction"))
                    editor.putString("txn_${i}_subtitle", obj.optString("subtitle", ""))
                    editor.putString("txn_${i}_amount", obj.optString("amount_str", "₹0"))
                    editor.putString("txn_${i}_category", obj.optString("category", "Other"))
                    editor.putString("txn_${i}_color", obj.optString("color", "#FB7185"))
                    editor.putBoolean("txn_${i}_is_income", obj.optBoolean("is_income", false))
                    editor.putBoolean("txn_${i}_is_auto", obj.optBoolean("is_auto", false))
                } else {
                    editor.putBoolean("txn_${i}_exists", false)
                }
            }
            editor.apply()
            Log.d(TAG, "🔄 Native midnight rollover updated $todayCount txns for $curYear-$curMonth-$curDay")
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Error parsing cached JSON: ${e.message}")
        }
    }

    // ==========================================
    // 10. CATEGORY DRAWABLES & COLOR HELPERS
    // ==========================================
    private fun getCategoryDrawable(category: String, isIncome: Boolean): Int {
        if (isIncome) return R.drawable.ic_cat_income
        val norm = category.lowercase().trim()
        return when {
            norm.contains("food") || norm.contains("dining") ||
                norm.contains("swiggy") || norm.contains("zomato") ||
                norm.contains("pizza") || norm.contains("burger") ||
                norm.contains("restaurant") -> R.drawable.ic_cat_food

            norm.contains("grocer") || norm.contains("zepto") ||
                norm.contains("instamart") || norm.contains("blinkit") ||
                norm.contains("supermarket") -> R.drawable.ic_cat_groceries

            norm.contains("shop") || norm.contains("amazon") ||
                norm.contains("flipkart") || norm.contains("myntra") ||
                norm.contains("cloth") || norm.contains("store") -> R.drawable.ic_cat_shopping

            norm.contains("transport") || norm.contains("uber") ||
                norm.contains("ola") || norm.contains("rapido") ||
                norm.contains("taxi") || norm.contains("travel") ||
                norm.contains("ride") -> R.drawable.ic_cat_transport

            norm.contains("fuel") || norm.contains("petrol") ||
                norm.contains("diesel") || norm.contains("gas") -> R.drawable.ic_cat_fuel

            norm.contains("movie") || norm.contains("netflix") ||
                norm.contains("youtube") || norm.contains("spotify") ||
                norm.contains("hotstar") || norm.contains("entertain") ||
                norm.contains("party") || norm.contains("music") -> R.drawable.ic_cat_entertainment

            norm.contains("bill") || norm.contains("recharge") ||
                norm.contains("wifi") || norm.contains("internet") ||
                norm.contains("electricity") || norm.contains("water") ||
                norm.contains("jio") -> R.drawable.ic_cat_bills

            norm.contains("medical") || norm.contains("health") ||
                norm.contains("doctor") || norm.contains("pharmacy") ||
                norm.contains("gym") || norm.contains("fitness") -> R.drawable.ic_cat_medical

            norm.contains("education") || norm.contains("school") ||
                norm.contains("college") || norm.contains("course") ||
                norm.contains("tuition") -> R.drawable.ic_cat_education

            norm.contains("rent") || norm.contains("house") ||
                norm.contains("home") || norm.contains("flat") -> R.drawable.ic_cat_home

            norm.contains("coffee") || norm.contains("cafe") ||
                norm.contains("starbucks") -> R.drawable.ic_cat_coffee

            norm.contains("gift") || norm.contains("charity") ||
                norm.contains("donation") -> R.drawable.ic_cat_gift

            norm.contains("subscri") -> R.drawable.ic_cat_subscriptions

            norm.contains("pet") || norm.contains("dog") ||
                norm.contains("cat") -> R.drawable.ic_cat_pets

            else -> R.drawable.ic_cat_other
        }
    }

    private fun parseColor(data: SharedPreferences, key: String, defaultColor: Int): Int {
        val raw = data.all[key] ?: return defaultColor
        return when (raw) {
            is Number -> raw.toInt()
            is String -> try {
                Color.parseColor(if (raw.startsWith("#")) raw else "#$raw")
            } catch (_: Exception) {
                defaultColor
            }
            else -> defaultColor
        }
    }

    private fun isDarkTheme(context: Context): Boolean {
        val mode = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return mode == Configuration.UI_MODE_NIGHT_YES
    }
}
