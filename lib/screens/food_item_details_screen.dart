import 'package:flutter/material.dart';
import 'package:fridge_app/models/fridge_item.dart'; // Import FridgeItem
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/services/fridge_service.dart'; // Import FridgeService

class FoodItemDetailsScreen extends StatelessWidget {
  const FoodItemDetailsScreen({super.key});

  Future<void> _deleteItem(BuildContext context, FridgeItem item) async {
    final shouldDelete = await showDialog<bool>(
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

    if (shouldDelete != true || !context.mounted) return;

    final deleted = await FridgeService.instance.deleteItemById(item.id);
    if (!context.mounted) return;

    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item could not be removed')),
      );
      return;
    }

    Navigator.pop(context, true);
  }

  void _openFilteredRecipesPage(BuildContext context, FridgeItem item) {
    Navigator.pushNamed(
      context,
      AppRoutes.suggestedRecipes,
      arguments: <String, dynamic>{
        'ingredientId': item.id,
        'ingredientName': item.name,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get item from arguments
    final item = ModalRoute.of(context)!.settings.arguments as FridgeItem;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Section
            Center(
              child: Hero(
                tag: 'fridge_item_${item.id}', // Unique tag for Hero animation
                child: Container(
                  height: 200,
                  width: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Center(
                      child: Text(
                        item.category.emoji,
                        style: const TextStyle(fontSize: 80),
                      ),
                    ), // Use emoji as fallback/default
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Content Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Freshness Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF102210),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.amountDisplay, // Use amount display
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getFreshnessColor(
                            item.freshnessStatus,
                          ).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _getFreshnessColor(item.freshnessStatus),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 10,
                              color: _getFreshnessColor(item.freshnessStatus),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              item.expiryDisplayText, // Use dynamic expiry text
                              style: TextStyle(
                                color: _getFreshnessColor(item.freshnessStatus),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Quick Actions Grid
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      _buildQuickAction(
                        icon: Icons.search,
                        label: 'Find Recipes',
                        onTap: () => _openFilteredRecipesPage(context, item),
                      ),
                      const SizedBox(width: 12),
                      _buildQuickAction(
                        icon: Icons.history,
                        label: 'History',
                        onTap: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Divider
                  Divider(color: Colors.grey[200], thickness: 1),
                  const SizedBox(height: 24),

                  // Details Grid
                  const Text(
                    'Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF102210),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    'Added Date',
                    '${item.addedDate.day}/${item.addedDate.month}/${item.addedDate.year}',
                    Icons.calendar_today,
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    'Category',
                    item.category.displayName,
                    Icons.category_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    'Source',
                    item.receiptId != null ? 'Scanned Receipt' : 'Manual Entry',
                    Icons.qr_code_scanner,
                  ),

                  const SizedBox(height: 32),

                  // Nutrition Info (Mocked/Placeholder as FridgeItem doesn't have this yet)
                  // In a real app, this would come from a product database linked to the item
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.eco_outlined,
                          color: Color(0xFF13EC13),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nutrition Tips',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'Good source of healthy fats.', // Placeholder
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey[400]),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Delete Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteItem(context, item),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        'Remove from Fridge',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getFreshnessColor(FreshnessStatus status) {
    switch (status) {
      case FreshnessStatus.fresh:
        return const Color(0xFF13EC13); // Green
      case FreshnessStatus.useSoon:
        return Colors.orange;
      case FreshnessStatus.expiringSoon:
        return Colors.red;
      case FreshnessStatus.expired:
        return Colors.grey;
    }
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8F6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.transparent),
          ),
          child: Column(
            children: [
              Icon(icon, size: 24, color: const Color(0xFF102210)),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF102210),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Colors.grey[600]),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF102210),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
