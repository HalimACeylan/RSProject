import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fridge_app/models/food_item.dart';
import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/models/recipe.dart';
import 'package:fridge_app/models/units.dart';
import 'package:fridge_app/services/cooking_service.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/fridge_service.dart';
import 'package:fridge_app/services/recipe_service.dart';
import 'package:fridge_app/widgets/fridge_bottom_navigation.dart';

enum _LogMode { ingredient, recipe }

/// Sealed hierarchy for the pending list — an ingredient entry needs its
/// quantity/unit, a recipe entry just needs the Recipe and runs through
/// CookingService.markCooked when committed.
sealed class PendingEntry {}

class PendingIngredient extends PendingEntry {
  final FoodItem item;
  final double quantity;
  final FridgeUnit unit;
  final bool usedFromFridge;
  PendingIngredient({
    required this.item,
    required this.quantity,
    required this.unit,
    required this.usedFromFridge,
  });
}

class PendingRecipe extends PendingEntry {
  final Recipe recipe;
  PendingRecipe(this.recipe);
}

class LogConsumptionScreen extends StatefulWidget {
  const LogConsumptionScreen({super.key});

  @override
  State<LogConsumptionScreen> createState() => _LogConsumptionScreenState();
}

class _LogConsumptionScreenState extends State<LogConsumptionScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<FoodItem> _searchResults = [];
  List<Recipe> _recipeResults = const [];
  bool _isSearching = false;
  _LogMode _mode = _LogMode.ingredient;

  final List<PendingEntry> _pendingLogs = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = _searchController.text.trim();
      if (query.isEmpty) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _recipeResults = const [];
            _isSearching = false;
          });
        }
        return;
      }

      setState(() => _isSearching = true);
      switch (_mode) {
        case _LogMode.ingredient:
          final resultsMap = await DatabaseService.instance.searchFoodItems(query);
          final results = resultsMap.map((map) => FoodItem.fromMap(map)).toList();
          if (!mounted) return;
          setState(() {
            _searchResults = results;
            _recipeResults = const [];
            _isSearching = false;
          });
        case _LogMode.recipe:
          // Recipe cache may still be hydrating in the background.
          await RecipeService.instance.ready;
          if (!mounted) return;
          final q = query.toLowerCase();
          final matches = RecipeService.instance.allRecipes
              .where((r) => r.title.toLowerCase().contains(q))
              .take(20)
              .toList();
          setState(() {
            _recipeResults = matches;
            _searchResults = const [];
            _isSearching = false;
          });
      }
    });
  }

  void _selectMode(_LogMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _searchController.clear();
      _searchResults = const [];
      _recipeResults = const [];
    });
  }

  Future<void> _logUsage() async {
    if (_pendingLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your consumption list is empty.')),
      );
      return;
    }

    int ingredientCount = 0;
    int recipeCount = 0;
    bool showedWarning = false;

    for (final entry in _pendingLogs) {
      switch (entry) {
        case PendingIngredient(:final item, :final quantity, :final unit, :final usedFromFridge):
          if (usedFromFridge) {
            final consumed = await FridgeService.instance.consumeItem(item.name, quantity);
            if (!consumed && mounted && !showedWarning) {
              showedWarning = true;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Warning: Only existing ingredients can be removed from your fridge.',
                  ),
                  backgroundColor: Colors.amber,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
          await DatabaseService.instance.logConsumption(
            itemName: item.name,
            category: item.category,
            amount: quantity,
            unit: unit.name,
            isFromFridge: usedFromFridge,
          );
          ingredientCount++;
        case PendingRecipe(:final recipe):
          await CookingService.instance.markCooked(recipe);
          recipeCount++;
      }
    }

    if (!mounted) return;

    final parts = <String>[];
    if (ingredientCount > 0) parts.add('$ingredientCount ingredient${ingredientCount == 1 ? '' : 's'}');
    if (recipeCount > 0) parts.add('$recipeCount recipe${recipeCount == 1 ? '' : 's'}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logged ${parts.join(' and ')}.'),
        backgroundColor: const Color(0xFF13EC13),
        duration: const Duration(seconds: 2),
      ),
    );

    setState(() {
      _pendingLogs.clear();
      _searchController.clear();
      _searchResults = const [];
      _recipeResults = const [];
    });
  }

  void _showConfigSheet(FoodItem food) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ConfigSheet(
        item: food,
        onAdd: (quantity, unit, usedFromFridge) {
          setState(() {
            _pendingLogs.add(
              PendingIngredient(
                item: food,
                quantity: quantity,
                unit: unit,
                usedFromFridge: usedFromFridge,
              ),
            );
            _searchController.clear();
            _searchResults = const [];
          });
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        title: const Text(
          'Log Consumption',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, '/fridge_grid');
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
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModeToggle(),
                    const SizedBox(height: 12),
                    _buildSearchSection(),
                    const SizedBox(height: 24),
                    if (_pendingLogs.isNotEmpty) _buildPendingList(),
                  ],
                ),
              ),
            ),
            if (_pendingLogs.isNotEmpty) _buildLogButton(),
            const FridgeBottomNavigation(currentTab: FridgeTab.log),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return SegmentedButton<_LogMode>(
      segments: const [
        ButtonSegment(
          value: _LogMode.ingredient,
          icon: Icon(Icons.local_grocery_store_outlined),
          label: Text('Ingredient'),
        ),
        ButtonSegment(
          value: _LogMode.recipe,
          icon: Icon(Icons.restaurant_menu),
          label: Text('Recipe'),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (s) => _selectMode(s.first),
    );
  }

  Widget _buildSearchSection() {
    return Container(
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: _mode == _LogMode.ingredient
                          ? 'Search ingredients...'
                          : 'Search recipes by name...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_searchController.text.isNotEmpty) _buildSearchResults(),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: CircularProgressIndicator(color: Color(0xFF13EC13)),
      );
    }

    final results = _mode == _LogMode.ingredient
        ? _searchResults.length
        : _recipeResults.length;
    if (results == 0) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          _mode == _LogMode.ingredient
              ? 'No ingredients found.'
              : 'No recipes found.',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_mode == _LogMode.ingredient) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _searchResults.length > 5 ? 5 : _searchResults.length,
        itemBuilder: (context, index) {
          final food = _searchResults[index];
          final cat = FridgeCategory.fromString(food.category);
          return InkWell(
            onTap: () {
              _showConfigSheet(food);
              FocusScope.of(context).unfocus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                children: [
                  Text(cat.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      food.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(Icons.add_circle_outline, color: Color(0xFF13EC13)),
                ],
              ),
            ),
          );
        },
      );
    }

    // Recipe mode results
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recipeResults.length > 5 ? 5 : _recipeResults.length,
      itemBuilder: (context, index) {
        final recipe = _recipeResults[index];
        return InkWell(
          onTap: () => _addRecipeToPending(recipe),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                const Text('🍳', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${recipe.ingredients.length} ingredient${recipe.ingredients.length == 1 ? '' : 's'} • ${recipe.prepTime}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.add_circle_outline, color: Color(0xFF13EC13)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _addRecipeToPending(Recipe recipe) {
    setState(() {
      // Don't queue the same recipe twice.
      final alreadyQueued = _pendingLogs.any(
        (e) => e is PendingRecipe && e.recipe.id == recipe.id,
      );
      if (!alreadyQueued) _pendingLogs.add(PendingRecipe(recipe));
      _searchController.clear();
      _recipeResults = const [];
    });
    FocusScope.of(context).unfocus();
  }

  Widget _buildPendingList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Items to Log',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              '${_pendingLogs.length} items',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._pendingLogs.asMap().entries.map((entry) {
          final index = entry.key;
          final log = entry.value;
          return _buildPendingRow(log, index);
        }),
      ],
    );
  }

  Widget _buildPendingRow(PendingEntry log, int index) {
    final String emoji;
    final Color tileColor;
    final String title;
    final String subtitle;
    switch (log) {
      case PendingIngredient(:final item, :final quantity, :final unit, :final usedFromFridge):
        final cat = FridgeCategory.fromString(item.category);
        emoji = cat.emoji;
        tileColor = cat.color.withValues(alpha: 0.1);
        title = item.name;
        subtitle = '$quantity ${unit.displayName} • ${usedFromFridge ? 'From Fridge' : 'External'}';
      case PendingRecipe(:final recipe):
        emoji = '🍳';
        tileColor = const Color(0xFF13EC13).withValues(alpha: 0.12);
        title = recipe.title;
        subtitle = 'Recipe • ${recipe.ingredients.length} ingredient'
            '${recipe.ingredients.length == 1 ? '' : 's'} will be logged';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            onPressed: () => setState(() => _pendingLogs.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Widget _buildLogButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ElevatedButton.icon(
        onPressed: _logUsage,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF13EC13),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.check_circle_outline),
        label: Text(
          'Log ${_pendingLogs.length} Items',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _ConfigSheet extends StatefulWidget {
  final FoodItem item;
  final Function(double quantity, FridgeUnit unit, bool usedFromFridge) onAdd;

  const _ConfigSheet({required this.item, required this.onAdd});

  @override
  State<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends State<_ConfigSheet> {
  double _quantity = 1.0;
  FridgeUnit _selectedUnit = FridgeUnit.pieces;
  bool _usedFromFridge = true;

  @override
  Widget build(BuildContext context) {
    final cat = FridgeCategory.fromString(widget.item.category);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cat.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(cat.emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.item.category,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Unit',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<FridgeUnit>(
                          value: _selectedUnit,
                          isExpanded: true,
                          items: FridgeUnit.values.map((unit) {
                            return DropdownMenuItem(
                              value: unit,
                              child: Text(unit.displayName),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null)
                              setState(() => _selectedUnit = val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quantity',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () {
                              if (_quantity > 1) setState(() => _quantity--);
                            },
                          ),
                          Text(
                            _quantity.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => setState(() => _quantity++),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SwitchListTile(
              title: const Text(
                'Used from my fridge',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              value: _usedFromFridge,
              onChanged: (val) => setState(() => _usedFromFridge = val),
              activeThumbColor: const Color(0xFF13EC13),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                widget.onAdd(_quantity, _selectedUnit, _usedFromFridge);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Add to List',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
