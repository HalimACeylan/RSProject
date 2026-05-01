import 'package:flutter/material.dart';
import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/models/recipe.dart';
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/services/fridge_service.dart';

class RecipePreparationGuideScreen extends StatefulWidget {
  const RecipePreparationGuideScreen({super.key, this.recipe});

  final Recipe? recipe;

  @override
  State<RecipePreparationGuideScreen> createState() =>
      _RecipePreparationGuideScreenState();
}

class _RecipePreparationGuideScreenState
    extends State<RecipePreparationGuideScreen> {
  bool _isConsumingIngredients = false;
  List<FridgeItem> _fridgeItems = const [];

  Recipe _resolveRecipe(BuildContext context) {
    return widget.recipe ??
        (ModalRoute.of(context)!.settings.arguments as Recipe);
  }

  @override
  void initState() {
    super.initState();
    _fridgeItems = FridgeService.instance.getAllItems();
    _refreshFridgeItemsFromCloud();
  }

  Future<void> _refreshFridgeItemsFromCloud() async {
    await FridgeService.instance.refreshFromCloud();
    if (!mounted) return;
    setState(() {
      _fridgeItems = FridgeService.instance.getAllItems();
    });
  }

  bool _ingredientMatchesFridgeItem(String ingredientName, String fridgeName) {
    final ingredient = ingredientName.toLowerCase();
    final item = fridgeName.toLowerCase();

    if (item.contains(ingredient) || ingredient.contains(item)) return true;

    final ingredientWords = ingredient
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .toSet();
    final itemWords = item
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .toSet();

    return ingredientWords.any(itemWords.contains);
  }

  bool _isInFridge(String ingredientName, List<FridgeItem> fridgeItems) {
    return fridgeItems.any(
      (item) => _ingredientMatchesFridgeItem(ingredientName, item.name),
    );
  }

  Set<String> _findUsedItemIds(Recipe recipe, List<FridgeItem> fridgeItems) {
    final usedIds = <String>{};

    for (final ingredient in recipe.ingredients) {
      for (final item in fridgeItems) {
        if (_ingredientMatchesFridgeItem(ingredient.name, item.name)) {
          usedIds.add(item.id);
        }
      }
    }

    return usedIds;
  }

  void _showStatusSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 110),
      ),
    );
  }

  Future<void> _consumeUsedIngredients(
    BuildContext context,
    Recipe recipe,
  ) async {
    if (_isConsumingIngredients) return;

    final usedItemIds = _findUsedItemIds(recipe, _fridgeItems);

    if (usedItemIds.isEmpty) {
      _showStatusSnackBar(
        'No matching fridge ingredients were found to remove.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Use Ingredients?'),
          content: Text(
            'This will remove ${usedItemIds.length} ingredient item${usedItemIds.length == 1 ? '' : 's'} from your fridge.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    setState(() {
      _isConsumingIngredients = true;
    });

    int removedCount = 0;
    try {
      for (final id in usedItemIds) {
        final deleted = await FridgeService.instance.deleteItemById(id);
        if (deleted) removedCount++;
      }
      await FridgeService.instance.refreshFromCloud();
      _fridgeItems = FridgeService.instance.getAllItems();
    } finally {
      if (mounted) {
        setState(() {
          _isConsumingIngredients = false;
        });
      }
    }

    if (!context.mounted) return;

    final text = removedCount == 0
        ? 'No ingredients were removed.'
        : 'Removed $removedCount ingredient item${removedCount == 1 ? '' : 's'} from fridge.';

    _showStatusSnackBar(text);
  }

  @override
  Widget build(BuildContext context) {
    final recipe = _resolveRecipe(context);
    final ingredientsInFridgeCount = recipe.ingredients
        .where((ingredient) => _isInFridge(ingredient.name, _fridgeItems))
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      body: Stack(
        children: [
          // Custom Scroll View for Header and Content
          CustomScrollView(
            slivers: [
              // Hero Header
              SliverAppBar(
                expandedHeight: 350,
                pinned: true,
                backgroundColor: Colors.transparent,
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                actions: [
                  Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.favorite_border,
                        color: Colors.white,
                      ),
                      onPressed: () {},
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.share, color: Colors.white),
                      onPressed: () {},
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (recipe.imageUrl != null &&
                          recipe.imageUrl!.startsWith('http'))
                        Image.network(
                          recipe.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: Colors.grey[800]),
                        )
                      else if (recipe.imageUrl != null)
                        Image.asset(
                          recipe.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: Colors.grey[800]),
                        )
                      else
                        Container(color: Colors.grey[800]),

                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.transparent,
                              Colors.black.withOpacity(0.4),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 40, // Space for overlap
                        left: 24,
                        right: 24,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (recipe.tags.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF13EC13),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  recipe.tags.first.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              recipe.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _HeaderInfoItem(
                                  icon: Icons.schedule,
                                  text: recipe.prepTime,
                                ),
                                const SizedBox(width: 16),
                                _HeaderInfoItem(
                                  icon: Icons.restaurant,
                                  text: '${recipe.servings} Servings',
                                ),
                                const SizedBox(width: 16),
                                if (recipe.calories.isNotEmpty)
                                  _HeaderInfoItem(
                                    icon: Icons.local_fire_department,
                                    text: recipe.calories,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Content
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF6F8F6),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  transform: Matrix4.translationValues(
                    0,
                    -20,
                    0,
                  ), // Overlap effect
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ingredients Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Ingredients',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF13EC13,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$ingredientsInFridgeCount/${recipe.ingredients.length} In Fridge',
                                      style: const TextStyle(
                                        color: Color(0xFF102210),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ...recipe.ingredients.map((ingredient) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: _IngredientItem(
                                    name: ingredient.name,
                                    amount: ingredient.amount,
                                    inFridge: _isInFridge(
                                      ingredient.name,
                                      _fridgeItems,
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 4),
                              Center(
                                child: TextButton.icon(
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      AppRoutes.insideFridge,
                                    );
                                  },
                                  icon: const Text('View Full Inventory'),
                                  label: const Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF102210),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Instructions Section
                        const Text(
                          'Instructions',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (recipe.steps.isNotEmpty)
                          ...recipe.steps.map(
                            (step) => _InstructionStep(
                              stepNumber: step.stepNumber,
                              title: step.title,
                              description: step.description,
                              imageUrl: step.imageUrl,
                              isLast: step == recipe.steps.last,
                            ),
                          )
                        else
                          const Text(
                            'No instructions available.',
                            style: TextStyle(color: Colors.grey),
                          ),

                        const SizedBox(
                          height: 100,
                        ), // Space for floating footer
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Sticky Footer
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 40,
                bottom: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.white,
                    Colors.white.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: ElevatedButton(
                key: const ValueKey('recipe_cooked_button'),
                onPressed: _isConsumingIngredients
                    ? null
                    : () => _consumeUsedIngredients(context, recipe),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF13EC13),
                  foregroundColor: const Color(0xFF102210),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  shadowColor: const Color(0xFF13EC13).withOpacity(0.4),
                ),
                child: _isConsumingIngredients
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Updating fridge...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check),
                          const SizedBox(width: 8),
                          const Text(
                            'Cooked',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (recipe.prepTime.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderInfoItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeaderInfoItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF13EC13), size: 16),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _IngredientItem extends StatelessWidget {
  final String name;
  final String amount;
  final bool inFridge;

  const _IngredientItem({
    required this.name,
    required this.amount,
    required this.inFridge,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: inFridge ? 1.0 : 0.75,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: inFridge
                  ? const Color(0xFF13EC13).withOpacity(0.2)
                  : Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              inFridge ? Icons.check : Icons.shopping_cart,
              size: 16,
              color: inFridge ? const Color(0xFF102210) : Colors.grey[400],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  amount,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          if (inFridge)
            const Text(
              'In Fridge',
              style: TextStyle(
                color: Color(0xFF102210),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Need to Buy',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String description;
  final String? imageUrl;
  final bool isLast;

  const _InstructionStep({
    required this.stepNumber,
    required this.title,
    required this.description,
    this.imageUrl,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isLast ? Colors.white : Colors.black,
                  border: isLast
                      ? Border.all(color: Colors.grey[300]!, width: 2)
                      : null,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    stepNumber.toString(),
                    style: TextStyle(
                      color: isLast ? Colors.grey[500] : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey[200],
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[100]!),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null)
                      Image.network(
                        imageUrl!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            description,
                            style: TextStyle(
                              color: Colors.grey[600],
                              height: 1.5,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
