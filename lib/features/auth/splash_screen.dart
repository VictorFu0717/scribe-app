import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../widgets/brand_background.dart';
import '../../widgets/brand_wave.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandWave(size: 84),
              const SizedBox(height: 24),
              Text(
                AppConfig.appName,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontSize: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
