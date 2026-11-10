# Mihonban Client

[English](CLIENT-FORK.md) · [简体中文](CLIENT-FORK.zh.md) · [繁體中文](CLIENT-FORK.zh-Hant.md) · [日本語](CLIENT-FORK.ja.md) · [한국어](CLIENT-FORK.ko.md) · [Français](CLIENT-FORK.fr.md) · [Español](CLIENT-FORK.es.md)

Un fork indépendant du client iPhone/iPad de [Mihonban](https://github.com/hanfdev/mihonban), destiné aux auditeurs ordinaires comme aux administrateurs. Sa première version repose sur le Build 95 d’origine (`9128f034d3ea52f2eb2e2f01527d6e63b8293126`). Le dépôt conserve l’historique amont, la [licence AGPL-3.0](LICENSE), les polices et les mentions des tiers.

## Favoris personnels et sélection partagée

| | Mes favoris | Sélection des administrateurs |
|---|---|---|
| Symbole | Cœur | Étincelles |
| Qui peut modifier | Toute personne connectée à un serveur | Les administrateurs du serveur |
| Stockage | Cette installation de l’application, séparément par serveur | La sélection partagée du serveur |
| Modifications envoyées au serveur | Aucune | API existante des favoris administrateur |
| Modifications hors ligne | Pour les éléments disponibles dans la bibliothèque locale | Connexion au serveur nécessaire |

Utilisez le cœur du lecteur ou de la barre d’outils de l’album, ou **Ajouter à mes favoris** dans le menu d’un album ou d’un morceau. L’onglet **Favoris** ouvre **Mes favoris** ; son lien **Sélection des administrateurs** ouvre la liste partagée. Les administrateurs utilisent les actions explicites **Ajouter à la sélection des administrateurs** / **Retirer de la sélection des administrateurs**. Les listes personnelles prennent en charge les albums, les morceaux, la lecture, la suppression et le classement manuel.

Les favoris sont des signets, pas des téléchargements audio. La lecture hors ligne nécessite toujours des fichiers téléchargés ou mis en cache. Les favoris locaux restent disponibles après un redémarrage de l’application, une déconnexion suivie d’une reconnexion ou l’effacement du cache audio. Ils appartiennent à cette installation, pas au serveur. Désinstaller l’application supprime ses données locales. Cette première version ne propose ni export, ni synchronisation entre appareils, ni migration depuis l’application d’origine.

Le protocole actuel fournit des rôles et des mots de passe partagés, pas d’identifiants personnels stables. Les personnes utilisant la même installation et le même serveur partagent les favoris locaux de cette installation. Des origines de serveur ou des chemins de base différents disposent de collections séparées. Changer de rôle ne crée pas de compte. Les éléments enregistrés ne s’affichent que s’ils sont accessibles dans le catalogue actuellement autorisé. Les éléments temporairement indisponibles conservent leur identifiant enregistré sans contourner les permissions du serveur.

Les métadonnées personnelles sont écrites de manière atomique dans Application Support, en dehors du cache multimédia pouvant être purgé. Les opérations sur les fichiers s’exécutent hors de l’exécuteur de l’interface. Un échec d’enregistrement conserve l’état précédent et signale l’erreur. Un fichier corrompu ou d’une version non prise en charge est conservé plutôt que remplacé silencieusement.

## Application indépendante et compilation

- Nom affiché : **Mihonban Client**
- Identifiant du bundle : `org.mihonban.client.ios`
- Version initiale : `0.3.0` ; la numérotation des builds démarre indépendamment dans ce dépôt.
- Système minimum : iOS/iPadOS 17 ; interface native SwiftUI et version fixée de SFBAudioEngine.

L’identifiant distinct permet d’installer les deux applications ensemble. Leurs mots de passe, réglages, téléchargements et favoris sont séparés. Aucune migration automatique n’est effectuée.

Le [workflow iOS](.github/workflows/mobile.yml) s’exécute sur `main`, produit un IPA non signé pour appareil et lance les tests sur simulateurs iPhone et iPad. Téléchargez l’artefact IPA d’une exécution réussie et signez-le avec votre outil d’installation habituel. Un IPA non signé n’est pas une publication App Store ou TestFlight. Les résultats des simulateurs ne démontrent ni la fréquence d’images sur appareil réel, ni le routage réel de l’écran verrouillé, ni le comportement des futures versions d’iPadOS.

Pour compiler localement sous macOS, utilisez une version de Xcode prenant en charge les fonctionnalités Swift requises par les sources. Le workflow indique la version exacte de CI (actuellement Xcode 26.6). Exécutez ces commandes à la racine du dépôt :

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

Conservez `-clonedSourcePackagesDirPath .spm` dans les commandes suivantes de compilation et de test pour utiliser le moteur corrigé. Si un fichier `ios/Package.resolved` vérifié est fourni, copiez-le dans `ios/Mihonban.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` avant de résoudre les dépendances, comme le fait le workflow. Pour les tests sur simulateur, lancez `python3 -I ios/tools/fixture-server.py ios/TestFixtures` dans un autre terminal et choisissez une destination iPhone ou iPad disponible.

Conservez les polices partagées du dépôt et leurs mentions de licence. Régénérez les traductions avec `node ios/tools/export-locales.mjs` ; celles propres au client sont maintenues dans `ios/tools/personal-locales.json`. Exécutez `python3 ios/tools/check-l10n.py` et `python3 ios/tools/check-fonts.py` avant la compilation.

## Périmètre

Ce premier fork ajoute des favoris personnels locaux à l’appareil sans modifier l’API du serveur ni les permissions des administrateurs. Les améliorations futures concernent l’écoute quotidienne, la fiabilité de la lecture et de l’usage hors ligne, l’accessibilité et les performances mesurées. Les refontes serveur, web ou Android et les autres modifications de travail sans rapport sont exclues de cette première version du client.
