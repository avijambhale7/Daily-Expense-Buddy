import 'package:material_ui/material_ui.dart';

import '../../domain/models/expense_category.dart';
import 'app_colors.dart';

/// Icon catalogue for categories. Keys are stored in Firestore; icons are
/// const so they are tree-shaken correctly on web.
abstract final class CategoryIcons {
  static const Map<String, IconData> catalogue = {
    'food': Icons.restaurant_rounded,
    'transport': Icons.directions_bus_rounded,
    'groceries': Icons.local_grocery_store_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'bills': Icons.receipt_long_rounded,
    'entertainment': Icons.movie_rounded,
    'health': Icons.favorite_rounded,
    'education': Icons.school_rounded,
    'travel': Icons.flight_takeoff_rounded,
    'housing': Icons.home_rounded,
    'personal_care': Icons.spa_rounded,
    'other': Icons.category_rounded,
    'coffee': Icons.local_cafe_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'pets': Icons.pets_rounded,
    'gifts': Icons.card_giftcard_rounded,
    'kids': Icons.child_friendly_rounded,
    'fitness': Icons.fitness_center_rounded,
    'phone': Icons.smartphone_rounded,
    'subscriptions': Icons.subscriptions_rounded,
    'insurance': Icons.shield_rounded,
    'charity': Icons.volunteer_activism_rounded,
    'work': Icons.work_rounded,
    'savings': Icons.savings_rounded,
  };

  static IconData of(String key) => catalogue[key] ?? Icons.category_rounded;
}

extension CategoryVisuals on ExpenseCategory {
  IconData get icon => CategoryIcons.of(iconKey);
  Color color(BuildContext context) => context.appColors.category(colorIndex);
}
