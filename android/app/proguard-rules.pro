# ============================================================
# Flutter
# ============================================================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# ============================================================
# Firebase / GMS / Google Play Services (Auth, Firestore, Storage, Messaging)
# ============================================================
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firestore / Realtime DB model classes often use no-arg constructors + reflection
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <fields>;
    @com.google.firebase.firestore.PropertyName <methods>;
}
-keepclassmembers class * {
    public <init>();
}

# ============================================================
# Gson (used internally by Firebase / many plugins)
# ============================================================
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn sun.misc.**

# Keep generic signatures for classes that get serialized/deserialized (Gson uses reflection)
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# ============================================================
# Razorpay
# ============================================================
-keepclassmembers class * implements com.razorpay.PaymentResultListener {
    public void onPaymentSuccess(java.lang.String);
    public void onPaymentError(int, java.lang.String);
}
-keepclassmembers class * implements com.razorpay.PaymentResultWithDataListener {
    public void onPaymentSuccess(java.lang.String, com.razorpay.PaymentData);
    public void onPaymentError(int, java.lang.String, com.razorpay.PaymentData);
}
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-optimizations !method/inlining/*
-keepattributes *Annotation*
-keepclassmembers class **.R$* {
    public static <fields>;
}

# ============================================================
# Firebase Auth Phone / OTP (AutofillGroup + SMS retriever use reflection)
# ============================================================
-keep class com.google.android.gms.auth.api.phone.** { *; }
-dontwarn com.google.android.gms.auth.api.phone.**

# ============================================================
# flutter_sound_record (auto-generated warning fix)
# ============================================================
-dontwarn com.josephcrowell.flutter_sound_record.FlutterSoundRecordPlugin

# ============================================================
# Keep your own model classes (edit package name to match yours)
# This prevents R8 from stripping your Firestore data model classes.
# ============================================================
-keep class com.example.credbro.** { *; }

# ============================================================
# General safety nets
# ============================================================
-keepattributes Exceptions
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception