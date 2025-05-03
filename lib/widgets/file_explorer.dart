import 'dart:io';
import 'package:flutter/material.dart';

class FileExplorer extends StatelessWidget {
  final String path;
  final Function(String) onFileSelected;

  const FileExplorer(
      {super.key, required this.path, required this.onFileSelected});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FileSystemEntity>>(
      future: Directory(path)
          .list(recursive: false)
          .where((f) => f.path.endsWith('.bf'))
          .toList(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final files = snapshot.data!;
        return ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(files[index].path.split('/').last,
                style: Theme.of(context).textTheme.bodyMedium),
            onTap: () => onFileSelected(files[index].path),
            hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          ),
        );
      },
    );
  }
}
