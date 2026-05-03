import 'package:flutter/material.dart';
import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/models/units.dart';
import 'package:fridge_app/services/fridge_service.dart';
import 'package:intl/intl.dart';

class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final _nameController = TextEditingController();
  
  FridgeCategory _selectedCategory = FridgeCategory.dairy;
  double _quantity = 1.0;
  FridgeUnit _selectedUnit = FridgeUnit.liters;
  DateTime? _expiryDate;
  
  // Storage Location
  // 0 = Fridge, 1 = Freezer, 2 = Pantry
  int _storageLocationIndex = 0;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveIngredient() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a product name')),
      );
      return;
    }

    final newItem = FridgeItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      category: _selectedCategory,
      amount: _quantity,
      unit: _selectedUnit,
      expiryDate: _expiryDate,
      addedDate: DateTime.now(),
      isFrozen: _storageLocationIndex == 1, // 1 is Freezer
    );

    FridgeService.instance.addItem(newItem);

    // Pop back to the fridge grid directly (or pop twice if we came from add_ingredients)
    Navigator.of(context).pop();
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(Duration(days: _selectedCategory.defaultExpiryDays)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF13EC13),
              onPrimary: Colors.black,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() {
        _expiryDate = date;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Generate a set of popular categories for the emoji picker
    final popularCategories = [
      FridgeCategory.milk,
      FridgeCategory.apple,
      FridgeCategory.vegetables,
      FridgeCategory.egg,
      FridgeCategory.poultry,
      FridgeCategory.bread,
      FridgeCategory.cheese,
      FridgeCategory.beef,
    ];

    if (!popularCategories.contains(_selectedCategory)) {
      popularCategories.insert(0, _selectedCategory);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        title: const Text(
          'Add Ingredient',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _saveIngredient,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Color(0xFF13EC13),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Name
              const Text('Product Name', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'e.g. Fresh Milk',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF13EC13), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Choose an Icon
              const Text('Choose an Icon', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: popularCategories.length,
                  itemBuilder: (context, index) {
                    final cat = popularCategories[index];
                    final isSelected = _selectedCategory == cat;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat;
                          // Auto-update expiry date if not explicitly set
                          if (_expiryDate == null) {
                            _expiryDate = DateTime.now().add(Duration(days: cat.defaultExpiryDays));
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF13EC13).withOpacity(0.2) : Colors.white,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF13EC13) : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          cat.emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Details Grid
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quantity
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
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
                                icon: const Icon(Icons.remove, color: Colors.black54),
                                onPressed: () {
                                  if (_quantity > 1) {
                                    setState(() => _quantity--);
                                  }
                                },
                              ),
                              Text(
                                _quantity.toInt().toString(),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, color: Colors.black54),
                                onPressed: () {
                                  setState(() => _quantity++);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Unit
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Unit', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
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
                              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
                              items: FridgeUnit.values.map((unit) {
                                return DropdownMenuItem(
                                  value: unit,
                                  child: Text(unit.displayName),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedUnit = val);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Expiration Date
              const Text('Expiration Date (Optional)', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickExpiryDate,
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.black54, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _expiryDate == null
                            ? 'Select Date'
                            : DateFormat('MMM dd, yyyy').format(_expiryDate!),
                        style: TextStyle(
                          fontSize: 16,
                          color: _expiryDate == null ? Colors.black54 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Category Full Dropdown
              const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
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
                  child: DropdownButton<FridgeCategory>(
                    value: _selectedCategory,
                    isExpanded: true,
                    icon: const Icon(Icons.category, color: Colors.black54),
                    items: FridgeCategory.values.map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(cat.displayName),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Location in Kitchen
              const Text('Store In', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStoreInOption(0, 'Fridge', Icons.kitchen),
                  const SizedBox(width: 12),
                  _buildStoreInOption(1, 'Freezer', Icons.ac_unit),
                  const SizedBox(width: 12),
                  _buildStoreInOption(2, 'Pantry', Icons.inventory_2),
                ],
              ),
              const SizedBox(height: 32),

              // Primary Action
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _saveIngredient,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF13EC13),
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_circle),
                  label: const Text(
                    'Add to Fridge',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoreInOption(int index, String title, IconData icon) {
    final isSelected = _storageLocationIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _storageLocationIndex = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF13EC13).withOpacity(0.1) : Colors.white,
            border: Border.all(
              color: isSelected ? const Color(0xFF13EC13) : Colors.grey.shade300,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF13EC13) : Colors.black54,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF13EC13) : Colors.black87,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
