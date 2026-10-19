import 'dart:io';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  var text = manifest.readAsStringSync();
  if (!text.contains('android.permission.INTERNET')) {
    text = text.replaceFirst('<application', '<uses-permission android:name="android.permission.INTERNET" />\n    <application');
  }
  if (!text.contains('android.software.leanback')) {
    text = text.replaceFirst('<application', '<uses-feature android:name="android.software.leanback" android:required="false" />\n    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />\n    <application');
  }
  if (!text.contains('android:usesCleartextTraffic')) {
    text = text.replaceFirst('<application', '<application android:usesCleartextTraffic="true" android:allowBackup="false" android:banner="@drawable/tv_banner"');
  }
  text = text.replaceAll('android:label="ip360"', 'android:label="IP360"');
  if (!text.contains('android.intent.category.LEANBACK_LAUNCHER')) {
    text = text.replaceFirst('</activity>', '<intent-filter>\n                <action android:name="android.intent.action.MAIN" />\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />\n            </intent-filter>\n        </activity>');
  }
  manifest.writeAsStringSync(text);
  final destination = File('android/app/src/main/res/drawable/tv_banner.png');
  destination.parent.createSync(recursive: true);
  File('branding/tv_banner.png').copySync(destination.path);
}
