# Water Eject 💧

Aplicación Android que expulsa el agua del altavoz usando ondas de baja frecuencia.
Construida con **Flutter** y compilada desde **Windows** con VS Code + Android SDK
Command-line Tools (sin Android Studio, sin emulador).

## Descarga

- APK: [water-eject.apk](https://water-eject-android.vercel.app/water-eject.apk)
- Página: https://water-eject-android.vercel.app

## Qué hace

- Tono senoidal de **60–300 Hz** (preset por defecto **165 Hz**, el rango que
  suele expulsar agua de la cámara del altavoz).
- El audio se **sintetiza en el teléfono** (WAV PCM 16-bit, 44.1 kHz) con un
  número entero de ciclos → el bucle es perfecto, sin clics.
- Temporizador 15 s / 30 s / 60 s / continuo con cuenta atrás.
- Control de volumen en vivo, vibración al arrancar y animación de ondas.
- 100% offline: sin red, sin cuentas, sin anuncios.

## Estructura

```
lib/main.dart            UI + síntesis de audio + reproductor
android/                 proyecto Android generado por Flutter
site/                    landing page desplegada en Vercel (APK + QR)
tools/build_apk.ps1      compila el APK release
```

## Compilar el APK

Requisitos: Flutter SDK, JDK 17, Android SDK (platform-tools + build-tools + platform 34+).

```powershell
flutter pub get
flutter build apk --release --split-per-abi
# salida: build/app/outputs/flutter-apk/app-release.apk
```

## Desplegar la landing

```powershell
Copy-Item build\app\outputs\flutter-apk\app-release.apk site\water-eject.apk -Force
vercel site --prod --yes
```

## Notas

- `flutter build apk` firma con la keystore de debug: el APK es instalable pero
  no apto para Play Store (requiere keystore propia).
- El QR de `site/qr.png` apunta a la URL de producción.
