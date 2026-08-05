# Android release build 的 R8 保護規則。
#
# 為什麼需要:Flutter 對 release build **預設啟用 R8**(程式碼縮減/混淆,
# 見 flutter_tools 的 FlutterPlugin.kt:`releaseBuildType.isMinifyEnabled = true`)。
# 大量使用反射的原生 SDK 若未保留,編譯會成功但**執行期才失敗**,且只發生在
# release(debug 不啟用 R8)—— 這類問題很難從編譯輸出看出來。
#
# Flutter 會自動把本檔加入 proguardFiles(檔案存在即生效),無需改 build.gradle.kts。

# ── Google ML Kit:裝置內翻譯 ──
# 症狀(2026-08-05 實測):Android release 版設定頁的語言模型一直停在「檢查中…」,
# 因為 isModelDownloaded()/downloadModel() 在 R8 處理後拋 PlatformException。
# iOS 無此問題(不經 R8),故一開始難以判斷。
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**

# ML Kit 透過 ContentProvider 自動初始化,不可被移除。
-keep class com.google.mlkit.common.internal.MlKitInitProvider { *; }

# ── flutter_foreground_task:Android 前景服務(鎖屏持續錄音)──
# 服務與 receiver 由系統以類別名稱反射建立。
-keep class com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**
