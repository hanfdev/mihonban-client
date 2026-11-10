# Mihonban Client

[English](CLIENT-FORK.md) · [简体中文](CLIENT-FORK.zh.md) · [繁體中文](CLIENT-FORK.zh-Hant.md) · [日本語](CLIENT-FORK.ja.md) · [한국어](CLIENT-FORK.ko.md) · [Français](CLIENT-FORK.fr.md) · [Español](CLIENT-FORK.es.md)

Un fork independiente del cliente para iPhone/iPad de [Mihonban](https://github.com/hanfdev/mihonban), destinado tanto a oyentes habituales como a administradores. La primera versión se basa en el Build 95 original (`9128f034d3ea52f2eb2e2f01527d6e63b8293126`). El repositorio conserva el historial de origen, la [licencia AGPL-3.0](LICENSE), las fuentes y los avisos de terceros.

## Favoritos personales y selección compartida

| | Mis favoritos | Selección de administradores |
|---|---|---|
| Símbolo | Corazón | Destellos |
| Quién puede modificar | Cualquier persona conectada a un servidor | Administradores del servidor |
| Almacenamiento | Esta instalación de la aplicación, por separado para cada servidor | La selección compartida del servidor |
| Cambios enviados al servidor | Ninguno | API existente de favoritos del administrador |
| Cambios sin conexión | Admitidos para elementos disponibles en la biblioteca local | Requieren conexión con el servidor |

Usa el corazón del reproductor o de la barra de herramientas del álbum, o **Añadir a mis favoritos** en el menú de un álbum o una canción. La pestaña **Favoritos** abre **Mis favoritos**; su enlace **Selección de administradores** abre la lista compartida. Los administradores usan las acciones explícitas **Añadir a la selección de administradores** / **Quitar de la selección de administradores**. Las listas personales admiten álbumes, canciones, reproducción, eliminación y orden manual.

Los favoritos son marcadores, no descargas de audio. La reproducción sin conexión sigue requiriendo audio descargado o almacenado en caché. Los favoritos locales se conservan tras reiniciar la aplicación, desconectar y volver a conectar o borrar la caché de audio. Pertenecen a esta instalación, no al servidor. Desinstalar la aplicación elimina sus datos locales. Esta primera versión no incluye exportación, sincronización entre dispositivos ni migración desde la aplicación original.

El protocolo actual del servidor proporciona roles y contraseñas compartidas, no identificadores estables de cuentas personales. Quienes usan la misma instalación y el mismo servidor comparten los favoritos locales de esa instalación. Los distintos orígenes de servidor y rutas base tienen colecciones independientes. Cambiar de rol no crea una cuenta. Los elementos guardados solo se muestran si están disponibles en el catálogo autorizado actual. Los elementos temporalmente no disponibles conservan sus identificadores guardados sin eludir los permisos del servidor.

Los metadatos personales se escriben de forma atómica en Application Support, fuera de la caché multimedia que puede eliminarse. Las operaciones de archivos se ejecutan fuera del ejecutor de la interfaz. Si falla el guardado, se conserva el estado anterior y se informa del error. Un archivo dañado o con una versión no admitida se conserva en lugar de sustituirse silenciosamente.

## Aplicación independiente y compilación

- Nombre mostrado: **Mihonban Client**
- Identificador del paquete: `org.mihonban.client.ios`
- Versión inicial: `0.3.0`; los números de compilación comienzan de forma independiente en este repositorio.
- Sistema mínimo: iOS/iPadOS 17; interfaz nativa SwiftUI y versión fijada de SFBAudioEngine.

El identificador independiente permite instalar ambas aplicaciones juntas. Sus contraseñas, ajustes, descargas y favoritos están separados. No se realiza ninguna migración automática.

El [flujo de trabajo de iOS](.github/workflows/mobile.yml) se ejecuta en `main`, genera un IPA para dispositivos sin firmar y ejecuta pruebas en simuladores de iPhone e iPad. Descarga el artefacto IPA de una ejecución correcta y fírmalo con tu herramienta de instalación habitual. Un IPA sin firmar no es una publicación en App Store ni TestFlight. Los resultados del simulador no demuestran la tasa de fotogramas en dispositivos físicos, el enrutamiento real en la pantalla bloqueada ni el comportamiento de futuras versiones de iPadOS.

Para compilar localmente en macOS, usa una versión de Xcode compatible con las funciones de Swift requeridas por el código. El flujo de trabajo registra la versión exacta de CI (actualmente Xcode 26.6). Ejecuta estos comandos desde la raíz del repositorio:

```sh
brew install xcodegen ffmpeg
python3 -I ios/tools/check-l10n.py
python3 -I ios/tools/check-fonts.py
mkdir -p ios/TestFixtures ios/Resources/ThirdParty
ffmpeg -v error -f lavfi -i 'sine=frequency=440:duration=8:sample_rate=44100' -ac 2 -c:a libmp3lame -q:a 3 ios/TestFixtures/tone.mp3
ffmpeg -v error -f lavfi -i 'sine=frequency=440:duration=8:sample_rate=44100' -ac 2 -c:a flac ios/TestFixtures/tone.flac
ffmpeg -v error -f lavfi -i 'sine=frequency=440:duration=8:sample_rate=44100' -ac 2 -c:a vorbis -strict experimental -q:a 4 ios/TestFixtures/tone.ogg
xcodegen generate --spec ios/project.yml
xcodebuild -resolvePackageDependencies -project ios/Mihonban.xcodeproj -scheme Mihonban -clonedSourcePackagesDirPath .spm
python3 -I ios/tools/apply-audio-engine-fixes.py .spm/checkouts/SFBAudioEngine
python3 -I ios/tools/acknowledgements.py .spm/checkouts ios/Resources/ThirdParty/Acknowledgements.txt
xcodegen generate --spec ios/project.yml
xcodebuild build -project ios/Mihonban.xcodeproj -scheme Mihonban -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/Simulator -clonedSourcePackagesDirPath .spm \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

Mantén `-clonedSourcePackagesDirPath .spm` en los siguientes comandos de compilación y pruebas para usar el motor corregido. Si se proporciona un archivo `ios/Package.resolved` revisado, cópialo en `ios/Mihonban.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` antes de resolver las dependencias, como hace el flujo de trabajo. Para las pruebas del simulador, inicia `python3 -I ios/tools/fixture-server.py ios/TestFixtures` en otra terminal y elige un destino iPhone o iPad disponible.

Conserva las fuentes compartidas del repositorio y los avisos de licencia. Regenera las traducciones con `node ios/tools/export-locales.mjs`; las traducciones específicas del cliente se mantienen en `ios/tools/personal-locales.json`. Ejecuta `python3 ios/tools/check-l10n.py` y `python3 ios/tools/check-fonts.py` antes de compilar.

## Alcance

Este primer fork incorpora favoritos personales locales en el dispositivo sin modificar la API del servidor ni los permisos de los administradores. Las mejoras futuras se centran en la escucha cotidiana, la reproducción fiable y el uso sin conexión, la accesibilidad y el rendimiento medido. Los rediseños del servidor, web o Android y otros cambios de trabajo no relacionados quedan fuera de esta primera versión del cliente.
