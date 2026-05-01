import 'package:flutter/material.dart';
import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/services/fridge_service.dart';
import 'package:fridge_app/widgets/fridge_bottom_navigation.dart';
import 'package:fridge_app/widgets/fridge_header.dart';


class InsideFridgeScreen extends StatefulWidget {
  const InsideFridgeScreen({super.key});

  @override
  State<InsideFridgeScreen> createState() => _InsideFridgeScreenState();
}

class _InsideFridgeScreenState extends State<InsideFridgeScreen> {
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

  Future<bool> _confirmDelete(FridgeItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove Item'),
          content: Text('Remove ${item.name} from your fridge?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _deleteFromList(FridgeItem item) async {
    final shouldDelete = await _confirmDelete(item);
    if (!shouldDelete) return;

    final deleted = await FridgeService.instance.deleteItemById(item.id);
    if (!mounted) return;

    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item could not be removed')),
      );
      return;
    }

    await _refreshFromCloud();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${item.name} removed from fridge')));
  }

  @override
  Widget build(BuildContext context) {
    final service = FridgeService.instance;
    final stats = service.getStats();
    final urgentItems = service.getExpiringItems();
    final categories = service.getActiveCategories();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context),
                _buildSearchBar(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
                    children: [
                      _buildStatsGrid(stats),
                      const SizedBox(height: 24),
                      // ── Urgent items ───────────────────────────
                      if (urgentItems.isNotEmpty) ...[
                        _buildSectionHeader(
                          'Use Immediately',
                          '${urgentItems.length} items',
                          isUrgent: true,
                        ),
                        const SizedBox(height: 12),
                        ...urgentItems.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildUrgentItem(item),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // ── Category sections ──────────────────────
                      ...categories.map(
                        (cat) => _buildCategorySection(context, service, cat),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Bottom Nav and FAB
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomNav(context),
            ),
            Positioned(
              bottom: 90, // Adjusted for bottom nav height
              right: 24,
              child: FloatingActionButton(
                onPressed: () {
                  // TODO: Navigate to manual ingredient adding screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Add ingredient manually — coming soon!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                backgroundColor: const Color(0xFF13EC13),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Category section builder ─────────────────────────────────────

  Widget _buildCategorySection(
    BuildContext context,
    FridgeService service,
    FridgeCategory category,
  ) {
    final items = service.getItemsByCategory(category);
    if (items.isEmpty) return const SizedBox.shrink();

    // Filter out items already shown in urgent section
    final nonUrgent = items
        .where(
          (i) =>
              i.freshnessStatus != FreshnessStatus.expiringSoon &&
              i.freshnessStatus != FreshnessStatus.expired,
        )
        .toList();
    if (nonUrgent.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          category.displayName,
          '${nonUrgent.length} items',
          isUrgent: false,
        ),
        const SizedBox(height: 12),
        if (nonUrgent.length <= 4)
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: nonUrgent.map((item) => _buildGridItem(item)).toList(),
          )
        else
          ...nonUrgent.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildListItem(item),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Helpers to derive display data from FridgeItem ────────────────

  Color _freshnessColor(FridgeItem item) {
    switch (item.freshnessStatus) {
      case FreshnessStatus.fresh:
        return const Color(0xFF13EC13);
      case FreshnessStatus.useSoon:
        return Colors.amber;
      case FreshnessStatus.expiringSoon:
        return Colors.orange;
      case FreshnessStatus.expired:
        return Colors.red;
    }
  }

  double _freshnessProgress(FridgeItem item) {
    switch (item.freshnessStatus) {
      case FreshnessStatus.fresh:
        return 0.3;
      case FreshnessStatus.useSoon:
        return 0.55;
      case FreshnessStatus.expiringSoon:
        return 0.8;
      case FreshnessStatus.expired:
        return 0.95;
    }
  }

  String _freshnessLabel(FridgeItem item) {
    switch (item.freshnessStatus) {
      case FreshnessStatus.fresh:
        return 'Fresh';
      case FreshnessStatus.useSoon:
        return 'Use Soon';
      case FreshnessStatus.expiringSoon:
        return 'Expiring';
      case FreshnessStatus.expired:
        return 'Expired';
    }
  }

  // ── Reusable widgets (unchanged visuals) ─────────────────────────

  Widget _buildHeader(BuildContext context) {
    return FridgeHeader(
      title: 'Inside My Fridge',
      subtitle: 'Inventory Management',
      trailing: GestureDetector(
        onTap: () {
          Navigator.pushNamed(context, AppRoutes.fridgeGrid);
        },
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.kitchen_outlined, color: Colors.grey),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF13EC13),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          icon: const Icon(Icons.search, color: Colors.grey),
          hintText: 'Find ingredients...',
          border: InputBorder.none,
          suffixIcon: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF13EC13).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.tune, color: Color(0xFF13EC13), size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(Map<String, int> stats) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _buildStatCard(
            color: Colors.red[50]!,
            borderColor: Colors.red[100]!,
            icon: Icons.warning,
            iconColor: Colors.red,
            badgeColor: Colors.red[100]!,
            badgeTextColor: Colors.red,
            badge: 'Urgent',
            count: '${stats['urgent'] ?? 0}',
            label: 'Expiring soon',
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            color: Colors.amber[50]!,
            borderColor: Colors.amber[100]!,
            icon: Icons.schedule,
            iconColor: Colors.amber,
            badgeColor: Colors.amber[100]!,
            badgeTextColor: Colors.amber[800]!,
            badge: 'Use Soon',
            count: '${stats['useSoon'] ?? 0}',
            label: 'Use this week',
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            color: const Color(0xFF13EC13).withOpacity(0.1),
            borderColor: const Color(0xFF13EC13).withOpacity(0.2),
            icon: Icons.inventory_2,
            iconColor: const Color(0xFF13EC13),
            badgeColor: const Color(0xFF13EC13).withOpacity(0.2),
            badgeTextColor: Colors.green,
            badge: 'Healthy',
            count: '${stats['healthy'] ?? 0}',
            label: 'Total fresh items',
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required Color color,
    required Color borderColor,
    required IconData icon,
    required Color iconColor,
    required Color badgeColor,
    required Color badgeTextColor,
    required String badge,
    required String count,
    required String label,
  }) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: badgeTextColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            count,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String action, {
    required bool isUrgent,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          action,
          style: TextStyle(
            fontSize: 12,
            color: isUrgent ? Colors.red : Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildUrgentItem(FridgeItem item) {
    final color = _freshnessColor(item);
    final progress = _freshnessProgress(item);

    return GestureDetector(
      key: ValueKey('urgent_item_${item.id}'),
      onTap: () => _openItemDetails(item),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: color, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  item.category.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.expiryDisplayText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      color: color,
                      backgroundColor: Colors.grey[200],
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.notes ?? item.category.label} (${item.amountDisplay})',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () => _deleteFromList(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridItem(FridgeItem item) {
    final color = _freshnessColor(item);
    final progress = _freshnessProgress(item);

    return GestureDetector(
      key: ValueKey('grid_item_${item.id}'),
      onTap: () => _openItemDetails(item),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue[50],
              radius: 24,
              child: Text(
                item.category.emoji,
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_freshnessLabel(item)} (${item.expiryDisplayText})',
              style: TextStyle(fontSize: 10, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                color: color,
                backgroundColor: Colors.grey[200],
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(FridgeItem item) {
    final color = _freshnessColor(item);
    final progress = _freshnessProgress(item);

    return GestureDetector(
      key: ValueKey('list_item_${item.id}'),
      onTap: () => _openItemDetails(item),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  item.category.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${item.amountDisplay} • ${item.expiryDisplayText}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _freshnessLabel(item),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      color: color,
                      backgroundColor: Colors.grey[200],
                      minHeight: 4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return const FridgeBottomNavigation(currentTab: FridgeTab.fridge);
  }
}
