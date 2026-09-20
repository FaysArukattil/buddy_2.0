import 'package:flutter/material.dart';

/// Helper to safely retrieve an [IconData] for stored category/transaction icon codes.
///
/// Because Flutter's release build performs icon font tree-shaking, calling
/// `IconData(runtimeVariable)` causes the compile-time tree shaker to fail with:
/// `Avoid non-constant invocations of IconData`.
///
/// This helper maps runtime codepoint integers to compile-time constant [IconData]
/// references, allowing icon tree-shaking to succeed cleanly and safely falling back
/// to [Icons.category_rounded] for any unrecognized code.
class IconHelper {
  IconHelper._();

  static const Map<int, IconData> _iconMap = {
    // Default & selectable icons (Material Icons rounded)
    983304: Icons.restaurant_rounded,
    983409: Icons.shopping_cart_rounded,
    63129: Icons.delivery_dining_rounded,
    63286: Icons.fastfood_rounded,
    62922: Icons.bolt_rounded,
    983521: Icons.storefront_rounded,
    63522: Icons.inventory_2_rounded,
    983407: Icons.shopping_bag_rounded,
    63033: Icons.checkroom_rounded,
    63155: Icons.directions_car_rounded,
    63616: Icons.local_taxi_rounded,
    983646: Icons.two_wheeler_rounded,
    63597: Icons.local_gas_station_rounded,
    983645: Icons.tv_rounded,
    983086: Icons.ondemand_video_rounded,
    63725: Icons.music_note_rounded,
    63584: Icons.live_tv_rounded,
    63335: Icons.fitness_center_rounded,
    63664: Icons.medical_services_rounded,
    983342: Icons.school_rounded,
    63477: Icons.home_rounded,
    983265: Icons.receipt_long_rounded,
    983160: Icons.phone_android_rounded,
    63061: Icons.coffee_rounded,
    63346: Icons.flight_rounded,
    63013: Icons.celebration_rounded,
    983707: Icons.volunteer_activism_rounded,
    62878: Icons.autorenew_rounded,
    63609: Icons.local_pizza_rounded,
    983319: Icons.router_rounded,
    983743: Icons.wifi_rounded,
    983074: Icons.note_rounded,
    983128: Icons.payments_rounded,
    983750: Icons.work_outline_rounded,
    62967: Icons.business_center_rounded,
    983636: Icons.trending_up_rounded,
    983336: Icons.savings_rounded,
    983294: Icons.reply_rounded,
    63002: Icons.card_giftcard_rounded,
    983797: Icons.currency_exchange_rounded,
    63489: Icons.house_rounded,
    63719: Icons.movie_rounded,
    983159: Icons.pets_rounded,
    983484: Icons.sports_esports_rounded,
    63012: Icons.category_rounded,

    // Notification / legacy / non-rounded variations
    58674: Icons.restaurant,
    58778: Icons.shopping_bag,
    57815: Icons.directions_car,
    58636: Icons.receipt,
    58381: Icons.movie,
    58262: Icons.local_hospital,
    57409: Icons.account_balance_wallet,
    58644: Icons.refresh,
    57672: Icons.category,
    58272: Icons.local_pizza,
    58260: Icons.local_gas_station,
    57946: Icons.fastfood,
    58007: Icons.flight,
    58713: Icons.school,
    58136: Icons.home,
    58637: Icons.receipt_long,
    58531: Icons.phone_android,
    57997: Icons.fitness_center,
    58328: Icons.medical_services,
    57720: Icons.coffee,
    57673: Icons.celebration,
    59015: Icons.tv,
    58389: Icons.music_note,
    58707: Icons.savings,
    58498: Icons.payments,
    59124: Icons.work_outline,
    57628: Icons.business_center,
    59007: Icons.trending_up,
    57662: Icons.card_giftcard,
    57522: Icons.attach_money,
    58360: Icons.money,
    57408: Icons.account_balance,
    58780: Icons.shopping_cart,
    58779: Icons.shopping_basket,
    58261: Icons.local_grocery_store,
    57759: Icons.credit_card,
    57689: Icons.check_circle,
    59083: Icons.warning,
    58172: Icons.info,
    57911: Icons.error,
    58121: Icons.help,
    58751: Icons.settings,
    58513: Icons.person,
    58447: Icons.notifications,
    58727: Icons.search,
    57415: Icons.add,
    57882: Icons.edit,
    57785: Icons.delete,
    57706: Icons.close,
  };

  /// Returns a constant [IconData] corresponding to [codePoint],
  /// or [fallback] (defaulting to [Icons.category_rounded]) if not recognized.
  static IconData getIcon(dynamic codePoint, {IconData fallback = Icons.category_rounded}) {
    if (codePoint == null) return fallback;
    final int? code = codePoint is int ? codePoint : int.tryParse(codePoint.toString());
    if (code == null) return fallback;
    return _iconMap[code] ?? fallback;
  }
}
