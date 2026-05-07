import 'package:flutter/material.dart';
import 'package:fridge_app/routes.dart';

class UserPreferencesBottomSheet extends StatefulWidget {
  const UserPreferencesBottomSheet({super.key});

  @override
  State<UserPreferencesBottomSheet> createState() =>
      _UserPreferencesBottomSheetState();
}

class _UserPreferencesBottomSheetState
    extends State<UserPreferencesBottomSheet> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 4;

  // Step 1
  String? _selectedGender;
  String? _selectedAgeRange;

  // Step 2
  bool? _exercisesRegularly;
  String? _primaryFocus; // mutually exclusive
  
  // Step 3
  bool? _isPregnant;

  // Step 4
  String _mainDiet = 'Standard';
  final Set<String> _allergies = {};
  final Set<String> _excludes = {};

  bool _showOtherAllergyInput = false;
  final TextEditingController _otherAllergyCtrl = TextEditingController();
  final List<String> _customAllergies = [];

  bool _showOtherExcludeInput = false;
  final TextEditingController _otherExcludeCtrl = TextEditingController();
  final List<String> _customExcludes = [];

  final Color primaryColor = const Color(0xFF13EC13);
  final Color surfaceColor = Colors.white;

  @override
  void dispose() {
    _pageController.dispose();
    _otherAllergyCtrl.dispose();
    _otherExcludeCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
      Navigator.pushNamed(context, AppRoutes.insideFridge);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleTagInput(TextEditingController ctrl, List<String> tags) {
    final text = ctrl.text.trim();
    if (text.isNotEmpty && !tags.contains(text)) {
      setState(() {
        tags.add(text);
        ctrl.clear();
      });
    } else {
      ctrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 24),
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Header & Progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'STEP ${_currentStep + 1} OF $_totalSteps',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                        letterSpacing: 1.2,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      color: Colors.grey[600],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(_totalSteps, (i) {
                    return Expanded(
                      child: Container(
                        height: 6,
                        margin: EdgeInsets.only(right: i < _totalSteps - 1 ? 8 : 0),
                        decoration: BoxDecoration(
                          color: i <= _currentStep ? primaryColor : Colors.grey[200],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          // Pages
          Flexible(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentStep = i),
              children: [
                _buildStep1(),
                _buildStep2(),
                _buildStep3(),
                _buildStep4(),
              ],
            ),
          ),
          // Footer
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: surfaceColor,
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                if (_currentStep > 0) ...[
                  OutlinedButton(
                    onPressed: _prevStep,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.black87),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentStep == _totalSteps - 1 ? 'Finish Setup' : 'Next',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 20),
                      ],
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

  // ── Step 1: About You ─────────────────────────────────────────────────
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About You', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Let's tailor your experience. This helps us suggest better options.",
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 32),
          const Text('Gender', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _choiceCard('Male', Icons.male, _selectedGender == 'Male',
                  () => setState(() => _selectedGender = 'Male'))),
              const SizedBox(width: 12),
              Expanded(child: _choiceCard('Female', Icons.female, _selectedGender == 'Female',
                  () => setState(() => _selectedGender = 'Female'))),
            ],
          ),
          const SizedBox(height: 32),
          const Text('Age Range', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3, mainAxisSpacing: 12, crossAxisSpacing: 12,
            children: ['18 - 25', '25 - 30', '35 - 40', '40+'].map((age) {
              return _radioTile(age, _selectedAgeRange == age,
                  () => setState(() => _selectedAgeRange = age));
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Lifestyle ─────────────────────────────────────────────────
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lifestyle', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          const Text('Do you exercise regularly?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _choiceCard('Yes', Icons.directions_run,
                  _exercisesRegularly == true, () => setState(() => _exercisesRegularly = true))),
              const SizedBox(width: 12),
              Expanded(child: _choiceCard('No', Icons.weekend,
                  _exercisesRegularly == false, () => setState(() => _exercisesRegularly = false))),
            ],
          ),
          if (_exercisesRegularly == true) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.grey[300]!, width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What is your primary focus?',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['Athlete', 'Bodybuilding'].map((focus) {
                      final sel = _primaryFocus == focus;
                      return GestureDetector(
                        onTap: () => setState(() => _primaryFocus = sel ? null : focus),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? primaryColor.withValues(alpha: 0.15) : surfaceColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel ? primaryColor : Colors.grey[300]!,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (sel) ...[
                                Icon(Icons.check, size: 16, color: primaryColor),
                                const SizedBox(width: 4),
                              ],
                              Text(focus, style: TextStyle(
                                fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                                color: sel ? Colors.black : Colors.grey[700],
                              )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 3: Pregnancy ─────────────────────────────────────────────────
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Health', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('This information helps us personalise nutritional recommendations.',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 32),
          const Text('Are you pregnant?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _choiceCard('Yes', Icons.pregnant_woman,
                  _isPregnant == true, () => setState(() => _isPregnant = true))),
              const SizedBox(width: 12),
              Expanded(child: _choiceCard('No', Icons.person,
                  _isPregnant == false, () => setState(() => _isPregnant = false))),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 4: Dietary Choices ───────────────────────────────────────────
  Widget _buildStep4() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dietary Choices',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Personalize your recipe suggestions based on your diet and allergies.',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 32),
          // ── Diet ──
          const Text('Main Diet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _dietTile('Standard', Icons.restaurant),
          const SizedBox(height: 12),
          _dietTile('Vegetarian', Icons.eco),
          const SizedBox(height: 12),
          _dietTile('Vegan', Icons.spa),
          const SizedBox(height: 32),
          // ── Allergies ──
          const Text('Allergies', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...['Peanuts', 'Tree Nuts', 'Soy', 'Eggs', 'Fish', 'Shellfish'].map((a) {
                final sel = _allergies.contains(a);
                return _chipToggle(a, sel, () {
                  setState(() {
                    if (sel) { _allergies.remove(a); } else { _allergies.add(a); }
                  });
                });
              }),
              ..._customAllergies.map((a) => _tagChip(a, () {
                setState(() => _customAllergies.remove(a));
              })),
              _addOtherChip(_showOtherAllergyInput, () {
                setState(() {
                  _showOtherAllergyInput = !_showOtherAllergyInput;
                  if (!_showOtherAllergyInput) { _otherAllergyCtrl.clear(); }
                });
              }),
            ],
          ),
          if (_showOtherAllergyInput) ...[
            const SizedBox(height: 12),
            _tagTextField(_otherAllergyCtrl, 'Type an allergy and press space to add',
                _customAllergies),
          ],
          const SizedBox(height: 32),
          // ── Excludes ──
          const Text('Reduce / Exclude',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3, mainAxisSpacing: 12, crossAxisSpacing: 12,
            children: ['Sugar', 'Salt', 'Gluten', 'Lactose'].map((item) {
              final sel = _excludes.contains(item);
              return _checkTile(item, sel, () {
                setState(() {
                  if (sel) { _excludes.remove(item); } else { _excludes.add(item); }
                });
              });
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Other excludes chips
          if (_customExcludes.isNotEmpty) ...[
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _customExcludes.map((e) => _tagChip(e, () {
                setState(() => _customExcludes.remove(e));
              })).toList(),
            ),
            const SizedBox(height: 12),
          ],
          _otherExcludeRow(),
          if (_showOtherExcludeInput) ...[
            const SizedBox(height: 12),
            _tagTextField(_otherExcludeCtrl, 'Type an ingredient and press space to add',
                _customExcludes),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Reusable Widgets ──────────────────────────────────────────────────

  Widget _tagTextField(TextEditingController ctrl, String hint, List<String> tags) {
    return TextField(
      controller: ctrl,
      onChanged: (val) {
        if (val.endsWith(' ')) {
          _handleTagInput(ctrl, tags);
        }
      },
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _tagChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[400],
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipToggle(String label, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? primaryColor.withValues(alpha: 0.15) : surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? primaryColor : Colors.grey[300]!, width: sel ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sel) ...[
              Icon(Icons.check, size: 16, color: primaryColor),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(
              color: sel ? Colors.black : Colors.grey[700],
              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }

  Widget _addOtherChip(bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
          color: active ? Colors.grey[100] : surfaceColor,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text('Other', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _otherExcludeRow() {
    return InkWell(
      onTap: () {
        setState(() {
          _showOtherExcludeInput = !_showOtherExcludeInput;
          if (!_showOtherExcludeInput) { _otherExcludeCtrl.clear(); }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: _showOtherExcludeInput ? Colors.grey[50] : surfaceColor,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24, height: 24,
              child: Checkbox(
                value: _showOtherExcludeInput,
                onChanged: (val) {
                  setState(() {
                    _showOtherExcludeInput = val == true;
                    if (!_showOtherExcludeInput) { _otherExcludeCtrl.clear(); }
                  });
                },
                activeColor: primaryColor,
                checkColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Other', style: TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _choiceCard(String title, IconData icon, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: sel ? primaryColor.withValues(alpha: 0.1) : surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? primaryColor : Colors.grey[300]!, width: sel ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: sel ? primaryColor : Colors.grey[500]),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(
              fontSize: 16, fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
              color: sel ? Colors.black : Colors.grey[700],
            )),
          ],
        ),
      ),
    );
  }

  Widget _radioTile(String title, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: sel ? primaryColor.withValues(alpha: 0.1) : surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? primaryColor : Colors.grey[300]!, width: sel ? 2 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(
              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
              color: sel ? Colors.black : Colors.grey[700],
            )),
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: sel ? primaryColor : Colors.grey[400]!, width: 2),
                color: sel ? primaryColor : Colors.transparent,
              ),
              child: sel ? const Center(child: CircleAvatar(radius: 4, backgroundColor: Colors.black)) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkTile(String item, bool sel, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: sel ? Colors.grey[50] : surfaceColor,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24, height: 24,
              child: Checkbox(
                value: sel,
                onChanged: (_) => onTap(),
                activeColor: primaryColor,
                checkColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(item, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );
  }

  Widget _dietTile(String title, IconData icon) {
    final sel = _mainDiet == title;
    return GestureDetector(
      onTap: () => setState(() => _mainDiet = title),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sel ? primaryColor.withValues(alpha: 0.1) : surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? primaryColor : Colors.grey[300]!, width: sel ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: sel ? primaryColor : Colors.grey[500]),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(
              fontSize: 16, fontWeight: sel ? FontWeight.w600 : FontWeight.w500, color: Colors.black87,
            ))),
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: sel ? primaryColor : Colors.grey[400]!, width: 2),
                color: sel ? primaryColor : Colors.transparent,
              ),
              child: sel ? const Center(child: CircleAvatar(radius: 4, backgroundColor: Colors.white)) : null,
            ),
          ],
        ),
      ),
    );
  }
}
