# Release builds shrink with R8. ML Kit ships consumer rules, but its Flutter
# wrappers and model loaders are reached through reflection/JNI; keep them so a
# release APK can't fail only at runtime. onnxruntime is FFI-only (no Java).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google_mlkit_** { *; }
-dontwarn com.google.mlkit.**

# WorkManager (pulled in by ML Kit / Play services) builds its Room database by
# reflection (WorkDatabase -> WorkDatabase_Impl). R8 full mode strips the
# generated class's constructor and the release app crashes on launch in
# androidx.startup.InitializationProvider. Keep Room databases and WorkManager.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.** { *; }
-keep class androidx.startup.** { *; }
