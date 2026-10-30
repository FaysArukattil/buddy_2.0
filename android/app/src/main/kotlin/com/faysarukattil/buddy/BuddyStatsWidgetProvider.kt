package com.faysarukattil.buddy

/**
 * Pre-configured 3×3 Stats widget in the launcher widget picker.
 * Fully inherits all dynamic sizing and adaptive rendering behavior from [BuddyWidgetProvider].
 * If resized down to 2×2, it automatically adapts into the Quick Add card.
 * If resized to 4×2, it shows Today & Month.
 * If resized larger (3×3, 4×4), it shows full Today, Month, Donut and Heatmap analytics!
 */
class BuddyStatsWidgetProvider : BuddyWidgetProvider()
