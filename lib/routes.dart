import 'package:flutter/material.dart';
import 'package:fridge_app/screens/welcome_login_screen.dart';
import 'package:fridge_app/screens/inside_fridge_screen.dart';
import 'package:fridge_app/screens/suggested_recipes_screen.dart';
import 'package:fridge_app/screens/recipe_voting_screen.dart';
import 'package:fridge_app/screens/fridge_grid_screen.dart';
import 'package:fridge_app/screens/food_item_details_screen.dart';
import 'package:fridge_app/screens/recipe_preparation_guide_screen.dart';
import 'package:fridge_app/screens/add_ingredients_screen.dart';
import 'package:fridge_app/screens/manual_entry_screen.dart';

class AppRoutes {
  static const String welcomeLogin = '/';
  static const String insideFridge = '/inside_fridge';
  static const String suggestedRecipes = '/suggested_recipes';
  static const String recipeVoting = '/recipe_voting';
  static const String fridgeGrid = '/fridge_grid';
  static const String foodItemDetails = '/food_item_details';
  static const String recipePreparation = '/recipe_preparation';
  static const String addIngredients = '/add_ingredients';
  static const String manualEntry = '/manual_entry';

  static Map<String, WidgetBuilder> get routes => {
    welcomeLogin: (context) => const WelcomeLoginScreen(),
    insideFridge: (context) => const InsideFridgeScreen(),
    suggestedRecipes: (context) => const SuggestedRecipesScreen(),
    recipeVoting: (context) => const RecipeVotingScreen(),
    fridgeGrid: (context) => const FridgeGridScreen(),
    foodItemDetails: (context) => const FoodItemDetailsScreen(),
    recipePreparation: (context) => const RecipePreparationGuideScreen(),
    addIngredients: (context) => const AddIngredientsScreen(),
    manualEntry: (context) => const ManualEntryScreen(),
  };
}
