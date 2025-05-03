import 'package:flutter/material.dart';

class TabButton extends StatelessWidget {
  final String title;
  final bool isActive;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const TabButton(
      {super.key,
      required this.title,
      required this.isActive,
      required this.isSaved,
      required this.onTap,
      required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                isSaved ? title : '$title *',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isActive
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onClose,
            color: Theme.of(context).colorScheme.onSurface,
            hoverColor: Theme.of(context).colorScheme.error.withOpacity(0.2),
          ),
        ],
      ),
    );
  }
}
