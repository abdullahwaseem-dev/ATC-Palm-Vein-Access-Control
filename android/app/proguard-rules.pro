# App bridge classes (referenced from Flutter channels / manifest)
-keep class com.atc.palmaccess.** { *; }

# Vendor SDK (also covered by the AAR consumer rules)
-keep class com.hfims.** { *; }
-keep class android.hibory.** { *; }
-dontwarn android.hibory.**
-keep class cn.eyecool.** { *; }
-keep class com.eyecool.** { *; }
-keep class com.jni.** { *; }
-keep class com.xinran.** { *; }
-dontwarn com.hfims.**
-dontwarn cn.eyecool.**

# SDK runtime dependencies
-keep class org.greenrobot.greendao.** { *; }
-keep class com.github.yuweiguocn.** { *; }
-keep class com.alibaba.fastjson.** { *; }
-keep class com.alibaba.fastjson2.** { *; }
-dontwarn com.alibaba.**
-dontwarn org.greenrobot.greendao.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn java.awt.**
-dontwarn com.sun.**
-dontwarn net.sqlcipher.**
-dontwarn rx.**
-dontwarn com.google.android.play.core.**
-keepattributes Signature, InnerClasses, EnclosingMethod, *Annotation*

# Strip verbose logging from release builds
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
