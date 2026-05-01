import 'package:flutter/material.dart';
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/widgets/fridge_bottom_navigation.dart';
import 'package:fridge_app/widgets/fridge_header.dart';

class RecipeVotingScreen extends StatelessWidget {
  const RecipeVotingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                FridgeHeader(
                  superTitle: 'Family Dinner',
                  title: 'Vote for Tonight',
                  trailing: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: const Icon(Icons.filter_list, color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    children: [
                      // Context Banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF13EC13).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF13EC13).withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF13EC13).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.kitchen,
                                color: Color(0xFF102210),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Based on your fridge',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'We found 5 recipes using your expiring spinach and chicken.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Card 1
                      _buildRecipeCard(
                        title: 'Spicy Basil Chicken',
                        imagePath: 'assets/images/spicy_basil_chicken.png',
                        badges: [
                          _buildBadge(
                            Icons.local_fire_department,
                            'Top Choice',
                            const Color(0xFF13EC13),
                            Colors.black,
                          ),
                          _buildBadge(
                            null,
                            '100% Match',
                            Colors.black.withOpacity(0.6),
                            Colors.white,
                          ),
                        ],
                        time: '30 min',
                        difficulty: 'Easy',
                        votes: 4,
                        voters: [
                          'assets/images/avatar_mom.png',
                          'assets/images/avatar_dad.png',
                          'assets/images/avatar_sibling.png',
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Card 2
                      _buildRecipeCard(
                        title: 'Vegetable Stir Fry',
                        imagePath: 'assets/images/vegetable_stir_fry.png',
                        badges: [
                          _buildBadge(
                            null,
                            '80% Match',
                            Colors.black.withOpacity(0.6),
                            Colors.white,
                          ),
                        ],
                        time: '20 min',
                        difficulty: '',
                        votes: 2,
                        voters: [
                          'assets/images/avatar_mom.png',
                          'assets/images/avatar_sibling.png',
                        ],
                        isGrayscaleVoters: true,
                      ),
                      const SizedBox(height: 24),
                      // Card 3
                      _buildEmptyVotingCard(),
                      const SizedBox(height: 24),
                      // Suggest Button
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.suggestedRecipes,
                          );
                        },
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Suggest something else'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(
                            color: Colors.grey[300]!,
                            style: BorderStyle.none,
                          ), // Dashed preferred
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: Colors.grey[300]!),
                          ), // Combine border
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Bottom Nav
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomNav(context),
            ),

            // FAB Check
            Positioned(
              bottom: 90,
              right: 20,
              child: FloatingActionButton(
                onPressed: () {},
                backgroundColor: const Color(0xFF13EC13),
                child: const Icon(Icons.check, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeCard({
    required String title,
    required String imagePath,
    required List<Widget> badges,
    required String time,
    required String difficulty,
    required int votes,
    required List<String> voters,
    bool isGrayscaleVoters = false,
  }) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF13EC13).withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Stack(
              children: [
                Image.asset(
                  imagePath,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5],
                      ),
                    ),
                  ),
                ),
                if (badges.isNotEmpty)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        badges.first,
                        if (badges.length > 1) badges.last,
                      ],
                    ),
                  ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            time,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          if (difficulty.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.restaurant,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              difficulty,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 80, // Overlap width
                            height: 32,
                            child: Stack(
                              children: [
                                for (int i = 0; i < voters.length; i++)
                                  Positioned(
                                    left: i * 20.0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundImage: AssetImage(voters[i]),
                                        backgroundColor: Colors.grey[200],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF13EC13).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$votes Votes',
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
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.thumb_up),
                          label: const Text('Vote Yes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF13EC13),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.thumb_down_outlined,
                            color: Colors.grey,
                          ),
                          onPressed: () {},
                        ),
                      ),
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

  Widget _buildEmptyVotingCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[100]!),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/baked_salmon.png',
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Baked Salmon',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'Be the first to vote!',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.thumb_up, size: 14),
                    label: const Text('Vote', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData? icon, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: bg == Colors.black.withOpacity(0.6)
            ? Border.all(color: Colors.white.withOpacity(0.1))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: fg, size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return const FridgeBottomNavigation(currentTab: FridgeTab.cook);
  }
}
