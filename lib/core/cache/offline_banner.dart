// ✅ UPDATED 2026-05-09
import 'package:flutter/material.dart';

import 'connectivity_service.dart';

/// Displays a red banner when the device is offline.
/// Uses [ConnectivityService.onlineStream] so it reacts to network changes.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final bool online = await ConnectivityService.isOnline();
    if (mounted) setState(() => _isOnline = online);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectivityService.onlineStream(),
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        final bool online = snapshot.data ?? _isOnline;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: online ? 0 : 40,
          color: const Color(0xFFD32F2F),
          child: online
              ? const SizedBox.shrink()
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.wifi_off_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'أنت غير متصل بالإنترنت — عرض بيانات محفوظة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
