package com.faysarukattil.buddy

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

class BuddyWidgetProvider : HomeWidgetProvider() {

    private class RowIds(
        val row: Int,
        val divider: Int,
        val title: Int,
        val subtitle: Int,
        val amount: Int,
        val iconBg: Int,
        val icon: Int,
        val autoBadge: Int
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
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

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ multi-size RemoteViews mapping
            val smallViews = buildSmallLayout(context, widgetId, data)
            val mediumViews = buildMediumLayout(context, widgetId, data)
            val largeViews = buildLargeLayout(context, widgetId, data)

            val viewsMap = mapOf(
                SizeF(120f, 120f) to smallViews,
                SizeF(230f, 110f) to mediumViews,
                SizeF(230f, 210f) to largeViews
            )
            val multiViews = RemoteViews(viewsMap)
            manager.updateAppWidget(widgetId, multiViews)
        } else {
            // Pre-Android 12 size options query
            val options = manager.getAppWidgetOptions(widgetId)
            val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

            val views = when {
                (widthDp in 1..219) || (heightDp in 1..129) ->
                    buildSmallLayout(context, widgetId, data)
                heightDp < 200 ->
                    buildMediumLayout(context, widgetId, data)
                else ->
                    buildLargeLayout(context, widgetId, data)
            }
            manager.updateAppWidget(widgetId, views)
        }
    }

    // ==========================================
    // 1. SMALL LAYOUT (2x2)
    // ==========================================
    private fun buildSmallLayout(
        context: Context,
        widgetId: Int,
        data: SharedPreferences
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_buddy_small)

        val dateLabel = data.getString("today_date_label", "Today") ?: "Today"
        val spentToday = data.getString("today_spent", "₹0") ?: "₹0"
        val countLabel = data.getString("today_count_label", "0 transactions") ?: "0 transactions"

        views.setTextViewText(R.id.tv_today_date, dateLabel)
        views.setTextViewText(R.id.tv_hero_spent, spentToday)
        views.setTextViewText(R.id.tv_secondary_hint, countLabel)

        attachIntents(context, widgetId, views)
        return views
    }

    // ==========================================
    // 2. MEDIUM LAYOUT (4x2)
    // ==========================================
    private fun buildMediumLayout(
        context: Context,
        widgetId: Int,
        data: SharedPreferences
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_buddy_medium)

        val dateLabel = "· " + (data.getString("today_date_label", "Today") ?: "Today")
        val spentToday = data.getString("today_spent", "₹0") ?: "₹0"
        val incomeStr = data.getString("today_income_formatted", "+₹0") ?: "+₹0"
        val count = data.getInt("today_count", 0)
        val hasTxns = data.getBoolean("has_txns", false)

        views.setTextViewText(R.id.tv_today_date, dateLabel)
        views.setTextViewText(R.id.tv_hero_spent, spentToday)
        views.setTextViewText(R.id.tv_today_income, incomeStr)
        views.setTextViewText(R.id.tv_today_count, "$count txn${if (count == 1) "" else "s"}")

        if (!hasTxns) {
            views.setViewVisibility(R.id.layout_empty_txns, View.VISIBLE)
            views.setViewVisibility(R.id.layout_txns_container, View.GONE)
        } else {
            views.setViewVisibility(R.id.layout_empty_txns, View.GONE)
            views.setViewVisibility(R.id.layout_txns_container, View.VISIBLE)

            val mediumRowIds = listOf(
                RowIds(R.id.row_txn_0, R.id.divider_txn_0, R.id.tv_txn_0_title, R.id.tv_txn_0_subtitle,
                    R.id.tv_txn_0_amount, R.id.iv_txn_0_icon_bg, R.id.iv_txn_0_icon, R.id.iv_txn_0_auto_badge),
                RowIds(R.id.row_txn_1, 0, R.id.tv_txn_1_title, R.id.tv_txn_1_subtitle,
                    R.id.tv_txn_1_amount, R.id.iv_txn_1_icon_bg, R.id.iv_txn_1_icon, R.id.iv_txn_1_auto_badge)
            )

            mediumRowIds.forEachIndexed { i, ids ->
                val exists = data.getBoolean("txn_${i}_exists", false)
                views.setViewVisibility(ids.row, if (exists) View.VISIBLE else View.GONE)
                if (ids.divider != 0) {
                    val nextExists = data.getBoolean("txn_${i + 1}_exists", false)
                    views.setViewVisibility(ids.divider, if (exists && nextExists) View.VISIBLE else View.GONE)
                }
                if (exists) bindRow(views, i, ids, data)
            }
        }

        attachIntents(context, widgetId, views)
        return views
    }

    // ==========================================
    // 3. LARGE LAYOUT (4x3+)
    // ==========================================
    private fun buildLargeLayout(
        context: Context,
        widgetId: Int,
        data: SharedPreferences
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_buddy_large)

        val dateLabel = "· " + (data.getString("today_date_label", "Today") ?: "Today")
        val spentToday = data.getString("today_spent", "₹0") ?: "₹0"
        val incomeStr = data.getString("today_income_formatted", "+₹0") ?: "+₹0"
        val countLabel = data.getString("today_count_label", "0 transactions") ?: "0 transactions"
        val splitSummary = data.getString("today_split_summary", "⚡ 0 auto · ✍️ 0 manual") ?: ""
        val hasTxns = data.getBoolean("has_txns", false)

        views.setTextViewText(R.id.tv_today_date, dateLabel)
        views.setTextViewText(R.id.tv_hero_spent, spentToday)
        views.setTextViewText(R.id.tv_today_income, incomeStr)
        views.setTextViewText(R.id.tv_today_count, countLabel)
        views.setTextViewText(R.id.tv_auto_manual_split, splitSummary)

        if (!hasTxns) {
            views.setViewVisibility(R.id.layout_empty_txns, View.VISIBLE)
            views.setViewVisibility(R.id.layout_txns_container, View.GONE)
        } else {
            views.setViewVisibility(R.id.layout_empty_txns, View.GONE)
            views.setViewVisibility(R.id.layout_txns_container, View.VISIBLE)

            val largeRowIds = listOf(
                RowIds(R.id.row_txn_0, R.id.divider_txn_0, R.id.tv_txn_0_title, R.id.tv_txn_0_subtitle,
                    R.id.tv_txn_0_amount, R.id.iv_txn_0_icon_bg, R.id.iv_txn_0_icon, R.id.iv_txn_0_auto_badge),
                RowIds(R.id.row_txn_1, R.id.divider_txn_1, R.id.tv_txn_1_title, R.id.tv_txn_1_subtitle,
                    R.id.tv_txn_1_amount, R.id.iv_txn_1_icon_bg, R.id.iv_txn_1_icon, R.id.iv_txn_1_auto_badge),
                RowIds(R.id.row_txn_2, R.id.divider_txn_2, R.id.tv_txn_2_title, R.id.tv_txn_2_subtitle,
                    R.id.tv_txn_2_amount, R.id.iv_txn_2_icon_bg, R.id.iv_txn_2_icon, R.id.iv_txn_2_auto_badge),
                RowIds(R.id.row_txn_3, 0, R.id.tv_txn_3_title, R.id.tv_txn_3_subtitle,
                    R.id.tv_txn_3_amount, R.id.iv_txn_3_icon_bg, R.id.iv_txn_3_icon, R.id.iv_txn_3_auto_badge)
            )

            largeRowIds.forEachIndexed { i, ids ->
                val exists = data.getBoolean("txn_${i}_exists", false)
                views.setViewVisibility(ids.row, if (exists) View.VISIBLE else View.GONE)
                if (ids.divider != 0) {
                    val nextExists = data.getBoolean("txn_${i + 1}_exists", false)
                    views.setViewVisibility(ids.divider, if (exists && nextExists) View.VISIBLE else View.GONE)
                }
                if (exists) bindRow(views, i, ids, data)
            }
        }

        attachIntents(context, widgetId, views)
        return views
    }

    // ==========================================
    // ROW DATA BINDING
    // ==========================================
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

        // Set Icon and Tint
        views.setImageViewResource(ids.icon, catDrawable)
        views.setInt(ids.icon, "setColorFilter", catColor)

        // Rounded-Square Background with ~18% alpha
        views.setImageViewResource(ids.iconBg, R.drawable.widget_cat_bg)
        views.setInt(ids.iconBg, "setColorFilter", catColor)
        views.setInt(ids.iconBg, "setImageAlpha", 45)

        // Auto Bolt Badge
        if (ids.autoBadge != 0) {
            if (isAuto) {
                views.setViewVisibility(ids.autoBadge, View.VISIBLE)
                views.setInt(ids.autoBadge, "setColorFilter", COLOR_AMBER)
            } else {
                views.setViewVisibility(ids.autoBadge, View.GONE)
            }
        }
    }

    // ==========================================
    // PENDING INTENTS
    // ==========================================
    private fun attachIntents(context: Context, widgetId: Int, views: RemoteViews) {
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        // 1. Add Button Action -> Opens Transparent Flutter Modal (/widget-add)
        val addIntent = Intent(context, WidgetAddModalActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val addPi = PendingIntent.getActivity(
            context,
            widgetId * 30 + 1,
            addIntent,
            piFlags
        )
        views.setOnClickPendingIntent(R.id.btn_widget_add, addPi)

        // 2. Full Widget Background Tap -> Opens Main App (MainActivity)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val openPi = PendingIntent.getActivity(
            context,
            widgetId * 30 + 2,
            openIntent,
            piFlags
        )
        views.setOnClickPendingIntent(android.R.id.background, openPi)
    }

    // ==========================================
    // CATEGORY TO VECTOR DRAWABLE MAPPING
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

    companion object {
        private val COLOR_INCOME = 0xFF34D399.toInt()
        private val COLOR_EXPENSE = 0xFFFB7185.toInt()
        private val COLOR_AMBER = 0xFFFBBF24.toInt()
    }
}
