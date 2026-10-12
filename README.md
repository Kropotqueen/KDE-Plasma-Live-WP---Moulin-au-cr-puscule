# Moulin au crépuscule

Fond d'écran animé pour **KDE Plasma 6**, entièrement **vectoriel** et écrit en **QML / Qt Quick**.

Un moulin délabré sur une colline au coucher du soleil : les pales tournent, les nuages défilent sur plusieurs plans, le blé ondule au vent, les câbles électriques se balancent, des vagues de vent glissent sur les collines et une nuée d'étourneaux traverse le ciel de temps en temps.

La scène ne contient aucune image : tout est dessiné en code. Elle reste donc nette en 1080p comme en 4K, et elle est identique à chaque démarrage.

> Nécessite **KDE Plasma 6**. Ça ne fonctionne pas sous Plasma 5.

## Installation express

Copie-colle ce bloc dans un terminal : il télécharge le fond d'écran, l'installe et l'applique directement sur le bureau.

```bash
git clone https://github.com/Kropotqueen/KDE-Plasma-Live-WP---Moulin-au-cr-puscule ~/moulin-au-crepuscule
kpackagetool6 -t Plasma/Wallpaper -i ~/moulin-au-crepuscule/org.local.moulin
QDBUS=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus)
$QDBUS org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
  desktops().forEach(function (d) { d.wallpaperPlugin = "org.local.moulin"; });'
```

Et c'est tout, le moulin s'affiche.

## Mise à jour

```bash
git -C ~/moulin-au-crepuscule pull
kpackagetool6 -t Plasma/Wallpaper -u ~/moulin-au-crepuscule/org.local.moulin
systemctl --user restart plasma-plasmashell
```

## Désinstallation

Ce bloc remet d'abord le fond d'écran image par défaut de Plasma, pour éviter un bureau noir, puis supprime le moulin.

```bash
QDBUS=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus)
$QDBUS org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
  desktops().forEach(function (d) { d.wallpaperPlugin = "org.kde.image"; });'
kpackagetool6 -t Plasma/Wallpaper -r org.local.moulin
rm -rf ~/moulin-au-crepuscule
```

## Options

Clic droit sur le bureau, puis **Configurer le bureau et le fond d'écran…**

**Vitesses d'animation.** Chaque élément a son curseur : de 0 (arrêt) à 3 (trois fois plus vite), 1 = vitesse normale.

| Réglage | Ce qu'il anime |
|---|---|
| Pales du moulin | rotation des pales |
| Nuages | défilement des nuages et des filaments |
| Oiseaux | passage de la nuée d'étourneaux |
| Blé | ondulation du champ au premier plan |
| Câble | balancement des fils électriques |
| Vagues de vent | traînées claires sur les collines |

**Économie d'énergie.**

| Réglage | Par défaut | Effet |
|---|---|---|
| Pause quand une fenêtre maximisée couvre le bureau | activé | L'animation s'arrête quand le bureau est caché et reprend dès qu'il réapparaît. Elle ne consomme presque plus rien pendant ce temps. |
| Images par seconde max | « écran » | « écran » : rendu à chaque rafraîchissement de l'écran, la fluidité maximale. Mettre 30 divise le calcul environ par deux ; seuls les oiseaux paraissent un peu moins fluides. |

## En cas de souci

**Il n'apparaît pas, ou l'écran est noir.** Redémarre Plasma, et si ça ne suffit pas, regarde les erreurs :

```bash
systemctl --user restart plasma-plasmashell
journalctl --user -b | grep -i moulin
```

**Le bureau est bloqué.** Passe sur une console texte avec **Ctrl+Alt+F3**, connecte-toi, puis lance :

```bash
kpackagetool6 -t Plasma/Wallpaper -r org.local.moulin
```

Reviens ensuite sur ta session avec **Ctrl+Alt+F1** ou **Ctrl+Alt+F2**.

## Licence

GPL-3.0-or-later. Auteure : Kropotqueen
