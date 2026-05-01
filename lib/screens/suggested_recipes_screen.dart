import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/models/recipe.dart';
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/services/fridge_service.dart';
import 'package:fridge_app/services/recipe_service.dart';
import 'package:fridge_app/widgets/fridge_bottom_navigation.dart';
import 'package:fridge_app/widgets/fridge_header.dart';

class SuggestedRecipesScreen extends StatefulWidget {
  const SuggestedRecipesScreen({super.key});

  @override
  State<SuggestedRecipesScreen> createState() => _SuggestedRecipesScreenState();
}

class _SuggestedRecipesScreenState extends State<SuggestedRecipesScreen> {
  late final TextEditingController _recipeSearchController;
  late final TextEditingController _ingredientSearchController;
  late final FocusNode _ingredientFocusNode;
  late List<FridgeItem> _fridgeIngredients;
  late List<Recipe> _recipes;
  bool _didReadRouteArgs = false;
  String? _pendingRouteIngredientId;
  String? _pendingRouteIngredientName;

  final LinkedHashSet<String> _selectedIngredientIds = LinkedHashSet<String>();
  String _recipeSearchQuery = '';
  String _ingredientQuery = '';

  @override
  void initState() {
    super.initState();
    _recipeSearchController = TextEditingController();
    _ingredientSearchController = TextEditingController();
    _ingredientFocusNode = FocusNode();
    _ingredientFocusNode.addListener(() => setState(() {}));
    _fridgeIngredients = const [];
    _recipes = const [];
    _loadData();
    _refreshFromCloud();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readRouteFiltersIfNeeded();
  }

  @override
  void dispose() {
    _recipeSearchController.dispose();
    _ingredientSearchController.dispose();
    _ingredientFocusNode.dispose();
    super.dispose();
  }

  void _loadData() {
    final uniqueByName = <String, FridgeItem>{};
    for (final item in FridgeService.instance.getAllItems()) {
      final key = item.name.toLowerCase();
      uniqueByName.putIfAbsent(key, () => item);
    }

    _fridgeIngredients = uniqueByName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _recipes = RecipeService.instance.getSuggestedRecipes();
    _tryApplyPendingRouteFilter();
  }

  Future<void> _refreshFromCloud() async {
    await FridgeService.instance.refreshFromCloud();
    if (!mounted) return;
    setState(() {
      _loadData();
    });
  }

  void _readRouteFiltersIfNeeded() {
    if (_didReadRouteArgs) return;
    _didReadRouteArgs = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) return;

    final routeMap = Map<String, dynamic>.from(args);
    _pendingRouteIngredientId = routeMap['ingredientId'] as String?;
    _pendingRouteIngredientName = routeMap['ingredientName'] as String?;

    if (_tryApplyPendingRouteFilter()) {
      setState(() {});
    }
  }

  bool _tryApplyPendingRouteFilter() {
    final ingredientId = _pendingRouteIngredientId;
    final ingredientName = _pendingRouteIngredientName;
    if (ingredientId == null && ingredientName == null) {
      return false;
    }

    FridgeItem? match;
    if (ingredientId != null) {
      for (final item in _fridgeIngredients) {
        if (item.id == ingredientId) {
          match = item;
          break;
        }
      }
    }

    if (match == null &&
        ingredientName != null &&
        ingredientName.trim().isNotEmpty) {
      final normalizedName = ingredientName.trim().toLowerCase();
      for (final item in _fridgeIngredients) {
        final itemName = item.name.toLowerCase();
        if (itemName == normalizedName ||
            itemName.contains(normalizedName) ||
            normalizedName.contains(itemName)) {
          match = item;
          break;
        }
      }
    }

    if (match == null) return false;
    _pendingRouteIngredientId = null;
    _pendingRouteIngredientName = null;

    final wasAdded = _selectedIngredientIds.add(match.id);
    if (wasAdded) {
      _ingredientQuery = '';
      _ingredientSearchController.clear();
    }
    return wasAdded;
  }

  List<FridgeItem> get _selectedIngredients {
    return _fridgeIngredients
        .where((item) => _selectedIngredientIds.contains(item.id))
        .toList();
  }

  List<FridgeItem> get _ingredientSuggestions {
    final query = _ingredientQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];

    return _fridgeIngredients
        .where((item) {
          if (_selectedIngredientIds.contains(item.id)) return false;
          return item.name.toLowerCase().contains(query);
        })
        .take(8)
        .toList();
  }

  bool _ingredientMatchesFridgeItem(String ingredientName, String fridgeName) {
    final ingredient = ingredientName.toLowerCase();
    final item = fridgeName.toLowerCase();

    if (ingredient.contains(item) || item.contains(ingredient)) return true;

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

  bool _recipeContainsIngredient(Recipe recipe, FridgeItem item) {
    return recipe.ingredients.any(
      (ingredient) => _ingredientMatchesFridgeItem(ingredient.name, item.name),
    );
  }

  List<Recipe> get _visibleRecipes {
    Iterable<Recipe> filtered = _recipes;

    if (_recipeSearchQuery.isNotEmpty) {
      filtered = filtered.where(
        (recipe) => recipe.title.toLowerCase().contains(_recipeSearchQuery),
      );
    }

    if (_selectedIngredientIds.isNotEmpty) {
      final selectedIngredients = _selectedIngredients;
      filtered = filtered.where(
        (recipe) => selectedIngredients.every(
          (item) => _recipeContainsIngredient(recipe, item),
        ),
      );
    }

    return filtered.toList();
  }

  void _addIngredientFilter(FridgeItem item) {
    setState(() {
      _selectedIngredientIds.add(item.id);
      _ingredientQuery = '';
      _ingredientSearchController.clear();
    });
  }

  void _removeIngredientFilter(String id) {
    setState(() {
      _selectedIngredientIds.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final recipes = _visibleRecipes;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context),
                _buildRecipeSearchBar(),
                _buildIngredientSearchPicker(),
                _buildSelectedIngredientCards(),
                Expanded(child: _buildRecipeList(context, recipes)),
              ],
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomNav(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return FridgeHeader(
      superTitle: 'BASED ON YOUR FRIDGE',
      title: 'Suggested Recipes',
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

  Widget _buildRecipeSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 4),
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
        key: const ValueKey('recipe_name_search_field'),
        controller: _recipeSearchController,
        onChanged: (value) {
          setState(() {
            _recipeSearchQuery = value.trim().toLowerCase();
          });
        },
        decoration: InputDecoration(
          icon: const Icon(Icons.search, color: Colors.grey),
          hintText: 'Search recipe name...',
          border: InputBorder.none,
          suffixIcon: _recipeSearchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    _recipeSearchController.clear();
                    setState(() {
                      _recipeSearchQuery = '';
                    });
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildIngredientSearchPicker() {
    final suggestions = _ingredientSuggestions;
    final showSuggestions =
        suggestions.isNotEmpty &&
        _ingredientFocusNode.hasFocus &&
        _ingredientQuery.trim().isNotEmpty;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF13EC13).withOpacity(0.3)),
          ),
          child: TextField(
            key: const ValueKey('ingredient_filter_search_field'),
            controller: _ingredientSearchController,
            focusNode: _ingredientFocusNode,
            onChanged: (value) {
              setState(() {
                _ingredientQuery = value;
              });
            },
            decoration: const InputDecoration(
              icon: Icon(Icons.filter_alt_outlined, color: Colors.grey),
              hintText: 'Add ingredient filter from fridge...',
              border: InputBorder.none,
            ),
          ),
        ),
        if (showSuggestions)
          Container(
            margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestions.map((item) {
                return ActionChip(
                  key: ValueKey('ingredient_suggestion_${item.id}'),
                  avatar: Text(
                    item.category.emoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                  label: Text(item.name),
                  onPressed: () => _addIngredientFilter(item),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildSelectedIngredientCards() {
    final selected = _selectedIngredients;
    if (selected.isEmpty) return const SizedBox(height: 12);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Active Ingredient Filters',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedIngredientIds.clear();
                  });
                },
                child: const Text('Clear all'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selected.map((item) {
              return InputChip(
                key: ValueKey('selected_ingredient_${item.id}'),
                avatar: Text(
                  item.category.emoji,
                  style: const TextStyle(fontSize: 14),
                ),
                label: Text(item.name),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => _removeIngredientFilter(item.id),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeList(BuildContext context, List<Recipe> recipes) {
    if (recipes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              const Text(
                'No recipes found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Try another search or adjust ingredient filters.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final hasFilters =
        _recipeSearchQuery.isNotEmpty || _selectedIngredientIds.isNotEmpty;
    final footerText = hasFilters
        ? 'Showing ${recipes.length} filtered recipe${recipes.length == 1 ? '' : 's'}.'
        : 'Showing top matches for your inventory.';

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
      itemCount: recipes.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 24),
      itemBuilder: (context, index) {
        if (index == recipes.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                footerText,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          );
        }

        final recipe = recipes[index];
        return _buildRecipeCard(context, recipe);
      },
    );
  }

  Widget _buildRecipeCard(BuildContext context, Recipe recipe) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          AppRoutes.recipePreparation,
          arguments: recipe,
        );
      },
      child: Container(
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
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                if (recipe.imageUrl != null &&
                    recipe.imageUrl!.startsWith('http'))
                  Image.network(
                    recipe.imageUrl!,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 220,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image),
                    ),
                  )
                else if (recipe.imageUrl != null)
                  Image.asset(
                    recipe.imageUrl!,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 220,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image),
                    ),
                  )
                else
                  Container(
                    height: 220,
                    color: Colors.grey[300],
                    child: const Icon(Icons.image),
                  ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bookmark_border,
                      color: Color(0xFF13EC13),
                      size: 20,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: recipe.missingIngredients.isEmpty
                          ? const Color(0xFF13EC13)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 4),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          recipe.missingIngredients.isEmpty
                              ? Icons.check_circle
                              : Icons.warning,
                          size: 16,
                          color: recipe.missingIngredients.isEmpty
                              ? Colors.black
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            recipe.missingIngredients.isEmpty
                                ? 'You have all ingredients'
                                : 'Missing ${recipe.missingIngredients.length} item: ${recipe.missingIngredients.join(", ")}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: recipe.missingIngredients.isEmpty
                                  ? Colors.black
                                  : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          recipe.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            '${recipe.rating}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (recipe.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      recipe.description,
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildIconText(Icons.schedule, recipe.prepTime),
                      const SizedBox(width: 24),
                      if (recipe.calories.isNotEmpty) ...[
                        _buildIconText(
                          Icons.local_fire_department,
                          recipe.calories,
                        ),
                        const SizedBox(width: 24),
                      ],
                      if (recipe.type.isNotEmpty)
                        _buildIconText(Icons.restaurant_menu, recipe.type),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconText(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF13EC13)),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return const FridgeBottomNavigation(currentTab: FridgeTab.cook);
  }
}
