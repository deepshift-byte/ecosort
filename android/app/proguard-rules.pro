# TensorFlow Lite: keep the interpreter and ignore optional GPU delegate classes.
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.gpu.**
