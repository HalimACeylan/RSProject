import 'package:flutter/material.dart';
import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/services/fridge_service.dart';
import 'package:fridge_app/widgets/fridge_bottom_navigation.dart';


class FridgeGridScreen extends StatefulWidget {
  const FridgeGridScreen({super.key});

  @override
  State<FridgeGridScreen> createState() => _FridgeGridScreenState();
}

class _FridgeGridScreenState extends State<FridgeGridScreen> {
  /// null = "All Items", otherwise a specific category filter.
  FridgeCategory? _selectedCategory;
  bool _showExpiringOnly = false;

  @override
  void initState() {
    super.initState();
    _refreshFromCloud();
  }

  Future<void> _refreshFromCloud() async {
    await FridgeService.instance.refreshFromCloud();
    if (!mounted) return;
    setState(() {});
  }

  List<FridgeItem> get _filteredItems {
    final service = FridgeService.instance;
    List<FridgeItem> items;

    if (_showExpiringOnly) {
      items = [...service.getExpiringItems(), ...service.getUseSoonItems()];
    } else if (_selectedCategory != null) {
      items = service.getItemsByCategory(_selectedCategory!);
    } else {
      items = service.getAllItems();
    }

    return items;
  }

  Future<void> _openItemDetails(FridgeItem item) async {
    final didDelete = await Navigator.pushNamed(
      context,
      AppRoutes.foodItemDetails,
      arguments: item,
    );

    if (!mounted || didDelete != true) return;

    await _refreshFromCloud();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${item.name} removed from fridge')));
  }


  @override
  Widget build(BuildContext context) {
    final service = FridgeService.instance;
    final categories = service.getActiveCategories();
    final items = _filteredItems;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'My Fridge',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    'All Items',
                    _selectedCategory == null && !_showExpiringOnly,
                    onSelected: () => setState(() {
                      _selectedCategory = null;
                      _showExpiringOnly = false;
                    }),
                  ),
                  ...categories.map(
                    (cat) => _buildFilterChip(
                      '${cat.emoji} ${cat.label}',
                      _selectedCategory == cat && !_showExpiringOnly,
                      onSelected: () => setState(() {
                        _selectedCategory = cat;
                        _showExpiringOnly = false;
                      }),
                    ),
                  ),
                  _buildFilterChip(
                    '⚠️ Expiring',
                    _showExpiringOnly,
                    isWarning: true,
                    onSelected: () => setState(() {
                      _showExpiringOnly = !_showExpiringOnly;
                      _selectedCategory = null;
                    }),
                  ),
                ],
              ),
            ),
          ),
          // Grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.kitchen,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No items found',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.8,
                      children: [
                        ...items.map((item) => _buildItemCard(item)),
                        _buildAddItemCard(context),
                      ],
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, AppRoutes.addIngredients);
        },
        backgroundColor: const Color(0xFF13EC13),
        child: const Icon(Icons.add, color: Colors.black),
      ),
      bottomNavigationBar: const FridgeBottomNavigation(
        currentTab: FridgeTab.fridge,
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    bool isSelected, {
    bool isWarning = false,
    required VoidCallback onSelected,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(),
        backgroundColor: isWarning ? Colors.red[50] : Colors.white,
        selectedColor: const Color(0xFF13EC13),
        labelStyle: TextStyle(
          color: isSelected
              ? Colors.black
              : (isWarning ? Colors.red : Colors.grey[600]),
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected
                ? const Color(0xFF13EC13)
                : (isWarning ? Colors.red.withOpacity(0.3) : Colors.grey[300]!),
          ),
        ),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildItemCard(FridgeItem item) {
    final isCritical = item.freshnessStatus == FreshnessStatus.expired;
    final isWarning = item.freshnessStatus == FreshnessStatus.expiringSoon;
    final statusColor = isCritical
        ? Colors.red
        : isWarning
        ? Colors.orange
        : item.freshnessStatus == FreshnessStatus.useSoon
        ? Colors.amber
        : const Color(0xFF13EC13);

    return GestureDetector(
      onTap: () => _openItemDetails(item),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: isCritical ? Border.all(color: Colors.red[200]!) : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Item image or emoji fallback
                  item.imageUrl != null
                      ? Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              _buildEmojiPlaceholder(item),
                        )
                      : _buildEmojiPlaceholder(item),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  if (isCritical)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.red.withOpacity(0.9),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: const Text(
                          'EXPIRING TODAY',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (item.unit.label == 'pcs' && item.amount > 1)
                    Positioned(
                      bottom: isCritical ? 24 : 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Qty: ${item.amount.toInt()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            item.amountDisplay,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          item.expiryDisplayText,
                          style: TextStyle(
                            color: isCritical || isWarning
                                ? (isCritical ? Colors.red : Colors.orange)
                                : Colors.grey[400],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiPlaceholder(FridgeItem item) {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Text(item.category.emoji, style: const TextStyle(fontSize: 48)),
      ),
    );
  }

  Widget _buildAddItemCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, AppRoutes.addIngredients);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 32, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Add Item',
              style: TextStyle(
                color: Colors.grey[500],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
