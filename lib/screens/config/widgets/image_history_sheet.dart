// ==========================
// File: screens/config/widgets/image_history_sheet.dart
//
// Bottom sheet showing every image loaded this session so the user can
// swap the active one back in without losing its placed sensors.
// ==========================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../services/config/configuration_store.dart';
import '../../../services/config/site_image_config.dart';

void showImageHistorySheet(BuildContext context) {
  final store = ConfigurationStore.instance;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Image History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (store.history.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text(
                  'No images loaded yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: store.history.length,
                  itemBuilder: (context, index) {
                    final cfg = store.history[index];
                    final isActive = index == store.activeIndex;

                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: SvgPicture.file(
                            File(cfg.imagePath),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      title: Text(
                        cfg.floorLabel,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${cfg.sensors.length} sensor(s) placed  •  ${_formatTime(cfg.loadedAt)}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isActive)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.check_circle,
                                  color: Colors.tealAccent),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18,
                                color: Colors.white54),
                            tooltip: 'Rename floor',
                            onPressed: () => _showRenameDialog(context, store, cfg),
                          ),
                        ],
                      ),
                      onTap: () {
                        store.setActive(cfg.id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

String _formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)} - ${two(t.day)}/${two(t.month)}/${t.year}';
}

void _showRenameDialog(
  BuildContext context,
  ConfigurationStore store,
  SiteImageConfig cfg,
) {
  final controller = TextEditingController(text: cfg.floorLabel)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: cfg.floorLabel.length,
    );

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Rename Floor'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Floor label'),
          onSubmitted: (value) {
            store.renameFloor(cfg.id, value);
            Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              store.renameFloor(cfg.id, controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
