package com.faysarukattil.buddy

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import kotlin.math.max

class BuddyStatsWidgetProvider : AppWidgetProvider() {

    companion object {
        const val TAG = "BuddyStatsWidget"
        const val ACTION_SWITCH_PAGE = "com.faysarukattil.buddy.ACTION_SWITCH_PAGE"
        const val ACTION_TOGGLE_STATS_MODE = "com.faysarukattil.buddy.ACTION_TOGGLE_STATS_MODE"
        const val ACTION_TOGGLE_DONUT_MODE = "com.faysarukattil.buddy.ACTION_TOGGLE_DONUT_MODE"
        const val ACTION_TOGGLE_HEATMAP_MODE = "com.faysarukattil.buddy.ACTION_TOGGLE_HEATMAP_MODE"
        const val EXTRA_PAGE_INDEX = "extra_page_index"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return
        Log.d(TAG, "📡 onReceive action: $action")

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, BuddyStatsWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)

        val data = BuddyWidgetProvider.getData(context)

        when (action) {
            ACTION_SWITCH_PAGE -> {
                val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                val targetPage = intent.getIntExtra(EXTRA_PAGE_INDEX, 0)
                if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    data.edit().putInt("stats_page_$widgetId", targetPage).apply()
                    render(context, appWidgetManager, widgetId, data)
                } else {
                    appWidgetIds.forEach { id ->
                        data.edit().putInt("stats_page_$id", targetPage).apply()
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
        appWidgetIds: IntArray
    ) {
        val data = BuddyWidgetProvider.getData(context)
        appWidgetIds.forEach { widgetId ->
            render(context, appWidgetManager, widgetId, data)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, BuddyWidgetProvider.getData(context))
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: android.content.SharedPreferences
    ) {
        try {
            val views = RemoteViews(context.packageName, R.layout.widget_buddy_stats)
            val isDark = isDarkTheme(context)
            val density = context.resources.displayMetrics.density

            val options = manager.getAppWidgetOptions(widgetId)
            val isLandscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val widthDp = if (isLandscape) options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 260)
                          else options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 260)
            val heightDp = if (isLandscape) options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 240)
                           else options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 240)

            val safeW = max(140, widthDp)
            val safeH = max(140, heightDp)

            val activePage = data.getInt("stats_page_$widgetId", 0).coerceIn(0, 1)
            views.setDisplayedChild(R.id.flipper_stats_pages, activePage)

            val activeColor = if (isDark) 0xFF2DD4BF.toInt() else 0xFF1E5D57.toInt()
            val inactiveColor = if (isDark) 0x99EBEBF5.toInt() else 0x993C3C43.toInt()

            views.setInt(
                R.id.tab_stats_donut,
                "setBackgroundResource",
                if (activePage == 0) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive
            )
            views.setTextColor(R.id.tab_stats_donut, if (activePage == 0) activeColor else inactiveColor)

            views.setInt(
                R.id.tab_stats_heatmap,
                "setBackgroundResource",
                if (activePage == 1) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive
            )
            views.setTextColor(R.id.tab_stats_heatmap, if (activePage == 1) activeColor else inactiveColor)

            val donutMode = data.getString("donut_chart_mode", "spending") ?: "spending"
            val heatmapMode = data.getString("heatmap_chart_mode", "expense") ?: "expense"
            val txnsJson = data.getString("recent_txns_json", null)
            val colorsJson = data.getString("category_colors_json", null)

            val isDonutSpending = donutMode.equals("spending", ignoreCase = true)
            views.setInt(R.id.btn_donut_spending, "setBackgroundResource", if (isDonutSpending) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive)
            views.setTextColor(R.id.btn_donut_spending, if (isDonutSpending) activeColor else inactiveColor)
            views.setInt(R.id.btn_donut_earning, "setBackgroundResource", if (!isDonutSpending) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive)
            views.setTextColor(R.id.btn_donut_earning, if (!isDonutSpending) activeColor else inactiveColor)

            val isHeatmapExpense = heatmapMode.equals("expense", ignoreCase = true)
            views.setInt(R.id.btn_heatmap_expense, "setBackgroundResource", if (isHeatmapExpense) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive)
            views.setTextColor(R.id.btn_heatmap_expense, if (isHeatmapExpense) activeColor else inactiveColor)
            views.setInt(R.id.btn_heatmap_income, "setBackgroundResource", if (!isHeatmapExpense) R.drawable.widget_tab_active else R.drawable.widget_tab_inactive)
            views.setTextColor(R.id.btn_heatmap_income, if (!isHeatmapExpense) activeColor else inactiveColor)

            val slotWidthPx = ((safeW - 32) * density).toInt().coerceAtLeast(100)
            val slotHeightPx = ((safeH - 110) * density).toInt().coerceAtLeast(100)

            val donutBitmap = BuddyChartRenderer.renderDonutChart(
                context, slotWidthPx, slotHeightPx, isDark, donutMode, txnsJson, colorsJson
            )
            if (donutBitmap != null) {
                views.setImageViewBitmap(R.id.iv_stats_donut, donutBitmap)
            }

            val heatmapBitmap = BuddyChartRenderer.renderHeatmapChart(
                context, slotWidthPx, slotHeightPx, isDark, heatmapMode, txnsJson
            )
            if (heatmapBitmap != null) {
                views.setImageViewBitmap(R.id.iv_stats_heatmap, heatmapBitmap)
            }

            attachIntents(context, widgetId, views)
            manager.updateAppWidget(widgetId, views)
        } catch (e: Exception) {
            Log.e(TAG, "❌ FATAL error rendering stats widget $widgetId: ${e.message}", e)
        }
    }

    private fun attachIntents(context: Context, widgetId: Int, views: RemoteViews) {
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        val tabDonutIntent = Intent(context, BuddyStatsWidgetProvider::class.java).apply {
            action = ACTION_SWITCH_PAGE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            putExtra(EXTRA_PAGE_INDEX, 0)
        }
        views.setOnClickPendingIntent(
            R.id.tab_stats_donut,
            PendingIntent.getBroadcast(context, widgetId * 50 + 1, tabDonutIntent, piFlags)
        )

        val tabHeatmapIntent = Intent(context, BuddyStatsWidgetProvider::class.java).apply {
            action = ACTION_SWITCH_PAGE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            putExtra(EXTRA_PAGE_INDEX, 1)
        }
        views.setOnClickPendingIntent(
            R.id.tab_stats_heatmap,
            PendingIntent.getBroadcast(context, widgetId * 50 + 2, tabHeatmapIntent, piFlags)
        )

        val donutToggleIntent = Intent(context, BuddyStatsWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_DONUT_MODE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val donutPi = PendingIntent.getBroadcast(context, widgetId * 50 + 3, donutToggleIntent, piFlags)
        views.setOnClickPendingIntent(R.id.btn_donut_spending, donutPi)
        views.setOnClickPendingIntent(R.id.btn_donut_earning, donutPi)

        val heatmapToggleIntent = Intent(context, BuddyStatsWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_HEATMAP_MODE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val heatmapPi = PendingIntent.getBroadcast(context, widgetId * 50 + 5, heatmapToggleIntent, piFlags)
        views.setOnClickPendingIntent(R.id.btn_heatmap_expense, heatmapPi)
        views.setOnClickPendingIntent(R.id.btn_heatmap_income, heatmapPi)

        val openIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val openPi = PendingIntent.getActivity(context, widgetId * 50 + 4, openIntent, piFlags)
        views.setOnClickPendingIntent(android.R.id.background, openPi)
    }

    private fun isDarkTheme(context: Context): Boolean {
        val mode = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return mode == Configuration.UI_MODE_NIGHT_YES
    }
}
