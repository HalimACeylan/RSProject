import 'package:flutter/material.dart';
import 'package:fridge_app/routes.dart';

enum FridgeTab { fridge, cook, log }

class FridgeBottomNavigation extends StatelessWidget {
  final FridgeTab currentTab;

  const FridgeBottomNavigation({super.key, required this.currentTab});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context,
            Icons.kitchen_outlined,
            'Fridge',
            FridgeTab.fridge,
            AppRoutes.insideFridge,
          ),
          _buildNavItem(
            context,
            Icons.restaurant_menu,
            'Cook',
            FridgeTab.cook,
            AppRoutes.suggestedRecipes,
          ),
          _buildNavItem(
            context,
            Icons.history,
            'Log',
            FridgeTab.log,
            AppRoutes.logConsumption,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    IconData icon,
    String label,
    FridgeTab tab,
    String route,
  ) {
    final bool isActive = currentTab == tab;

    return GestureDetector(
      onTap: () {
        if (!isActive) {
          Navigator.pushReplacementNamed(context, route);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            alignment: Alignment.center,
            child: Column(
              children: [
                if (isActive)
                  Container(
                    width: 12,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13EC13).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Icon(
                  icon,
                  color: isActive ? const Color(0xFF13EC13) : Colors.grey,
                  shadows: isActive
                      ? [const Shadow(color: Color(0xFF13EC13), blurRadius: 8)]
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.black : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
