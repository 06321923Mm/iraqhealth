import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationRationaleSheet extends StatelessWidget {
  const LocationRationaleSheet({super.key});

  /// Shows the sheet and returns true if the user granted location permission,
  /// false if they tapped 'تخطي' or dismissed the sheet.
  static Future<bool> show(BuildContext context) async {
    final bool? result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const LocationRationaleSheet(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(Icons.location_on, color: colors.primary, size: 64),
              const SizedBox(height: 16),
              const Text(
                'نحتاج إذنك للموقع',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _Bullet('يُستخدم لعرض الأطباء الأقرب إليك'),
              _Bullet('لا يُخزَّن موقعك على خوادمنا أبداً'),
              _Bullet('تقدر تستخدم التطبيق بدونه'),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('تخطي'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      final PermissionStatus status =
                          await Permission.location.request();
                      if (context.mounted) {
                        Navigator.of(context).pop(status.isGranted);
                      }
                    },
                    child: const Text('السماح بالموقع'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.check_circle_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}
