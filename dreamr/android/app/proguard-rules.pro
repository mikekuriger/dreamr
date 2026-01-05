# android/app/proguard-rules.pro
#
# Fix for runtime crash:
#   IllegalStateException: TypeToken must be created with a type argument...
# This happens when R8/ProGuard strips generic signatures used by Gson.

# Preserve generic type info + reflection metadata
-keepattributes Signature,InnerClasses,EnclosingMethod
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations

# Gson core
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Gson TypeToken relies on generic signatures
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# If any models use @SerializedName (safe no-op if not)
-keepclassmembers class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
