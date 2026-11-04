import 'package:flutter/material.dart';

/// The seven waste categories EcoSort sorts items into.
enum WasteCategory {
  plastic(
    id: 'plastic',
    label: 'Plastic',
    color: Color(0xFFF5C518),
    icon: Icons.local_drink_rounded,
    examples: ['Bottles', 'Bags', 'Cups', 'Wrappers', 'Food trays'],
    tips: [
      'Empty and rinse containers.',
      'Squash bottles to save space.',
      'Put in the yellow / plastics bin.',
    ],
  ),
  paper(
    id: 'paper',
    label: 'Paper',
    color: Color(0xFF2D9CDB),
    icon: Icons.description_rounded,
    examples: ['Cardboard boxes', 'Newspaper', 'Books', 'Paper bags'],
    tips: [
      'Keep it clean and dry.',
      'Flatten boxes.',
      'Greasy pizza boxes go to organic.',
    ],
  ),
  glass(
    id: 'glass',
    label: 'Glass',
    color: Color(0xFF27AE60),
    icon: Icons.wine_bar_rounded,
    examples: ['Jars', 'Bottles', 'Drinking glasses'],
    tips: [
      'Remove lids and corks.',
      'Rinse out food residue.',
      'Take to the bottle bank / glass bin.',
    ],
  ),
  metal(
    id: 'metal',
    label: 'Metal',
    color: Color(0xFFF2994A),
    icon: Icons.hardware_rounded,
    examples: ['Cans', 'Foil', 'Cutlery', 'Lids', 'Scrap metal'],
    tips: [
      'Rinse cans.',
      'Scrunch foil into a ball.',
      'Put in the metals / cans bin.',
    ],
  ),
  organic(
    id: 'organic',
    label: 'Organic',
    color: Color(0xFFB7794A),
    icon: Icons.eco_rounded,
    examples: ['Fruit & vegetables', 'Food scraps', 'Peels', 'Garden waste'],
    tips: [
      'Compost at home if you can.',
      'Use the green / organic bin.',
      'No plastic bags in compost.',
    ],
  ),
  ewaste(
    id: 'ewaste',
    label: 'E-waste',
    color: Color(0xFF9B51E0),
    icon: Icons.devices_other_rounded,
    examples: ['Phones', 'Laptops', 'Cables', 'Remotes', 'Chargers'],
    tips: [
      'Wipe personal data first.',
      'Take to an e-waste drop-off point.',
      'Remove batteries and dispose of them as hazardous.',
    ],
  ),
  hazardous(
    id: 'hazardous',
    label: 'Hazardous',
    color: Color(0xFFEB5757),
    icon: Icons.warning_amber_rounded,
    examples: ['Batteries', 'Paint', 'Chemicals', 'Light bulbs', 'Syringes'],
    tips: [
      'Never put in household bins.',
      'Keep in original container, lid closed.',
      'Take to a hazardous waste collection point.',
    ],
  );

  const WasteCategory({
    required this.id,
    required this.label,
    required this.color,
    required this.icon,
    required this.examples,
    required this.tips,
  });

  final String id;
  final String label;
  final Color color;
  final IconData icon;
  final List<String> examples;
  final List<String> tips;

  static WasteCategory? fromId(String id) {
    final key = id.trim().toLowerCase();
    for (final c in values) {
      if (c.id == key || c.label.toLowerCase() == key) return c;
    }
    // Common aliases used by training datasets.
    switch (key) {
      case 'cardboard':
      case 'paper_cardboard':
        return paper;
      case 'e-waste':
      case 'electronic':
      case 'electronics':
        return ewaste;
      case 'food':
      case 'biodegradable':
      case 'compost':
        return organic;
      case 'battery':
      case 'chemical':
        return hazardous;
    }
    return null;
  }
}
