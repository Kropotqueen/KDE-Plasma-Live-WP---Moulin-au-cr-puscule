import QtQuick
import QtQuick.Shapes
import org.kde.plasma.plasmoid

// Moulin au crépuscule — fond d'écran Plasma 6 en QML vectoriel (v2).
// Scène 1920x1080 mise à l'échelle en "cover". Palette échantillonnée sur l'original.

WallpaperItem {
    id: root
    clip: true

    // ---- Réglages rapides (durées en ms) ----
    readonly property int bladePeriod: 120000    // un tour de pales
    readonly property int cloudPeriod: 900000    // base des nuages (plans proches = 2x / 3x plus vite)
    readonly property int windPeriod: 600000     // cycle complet du vent (boucle sans à-coup)

    // ---- Vitesses réglables dans les paramètres du fond d'écran (1 = normal, 0 = arrêt) ----
    function cfgSpeed(v) { return (v === undefined || v === null || isNaN(Number(v))) ? 1 : Math.max(0, Number(v)); }
    readonly property real speedMill:   cfgSpeed(root.configuration ? root.configuration.SpeedMill : 1)
    readonly property real speedClouds: cfgSpeed(root.configuration ? root.configuration.SpeedClouds : 1)
    readonly property real speedBirds:  cfgSpeed(root.configuration ? root.configuration.SpeedBirds : 1)
    readonly property real speedWheat:  cfgSpeed(root.configuration ? root.configuration.SpeedWheat : 1)
    readonly property real speedCable:  cfgSpeed(root.configuration ? root.configuration.SpeedCable : 1)
    readonly property real speedWind:   cfgSpeed(root.configuration ? root.configuration.SpeedWind : 1)

    property real bladeAngle: 0
    property real cloudPhase: 0
    property real skyP: 0        // respiration des filaments (suit la vitesse des nuages)
    property real wheatP: 0      // balancement du blé
    property real cableP: 0      // balancement du câble
    property real windClock: 0   // vagues de vent sur les collines (ms)
    property real flockClock: 0  // étourneaux (ms)

    // ---- Économies ----
    // Pause quand une fenêtre maximisée / plein écran recouvre ce bureau (rien de visible ne change).
    readonly property bool pauseWhenCovered: root.configuration ? root.configuration.PauseWhenCovered !== false : true
    // Plafond d'images par seconde : 0 = fréquence de l'écran (comportement d'origine)
    readonly property int maxFps: root.configuration ? Math.max(0, Number(root.configuration.MaxFps) || 0) : 0
    readonly property bool covered: root.pauseWhenCovered && coverWatch.item !== null && coverWatch.item.covered === true
    readonly property bool animating: root.visible && !root.covered
    // Surveillance des fenêtres dans un fichier à part : si le module TaskManager manque,
    // le Loader échoue proprement et l'animation tourne comme avant.
    Loader {
        id: coverWatch
        active: root.pauseWhenCovered
        source: "CoverWatcher.qml"
    }

    function advance(sec) {
        var dt = Math.min(0.1, sec) * 1000;
        root.bladeAngle = (root.bladeAngle + 360 * dt * root.speedMill / root.bladePeriod) % 360;
        root.cloudPhase = (root.cloudPhase + dt * root.speedClouds / root.cloudPeriod) % 1;
        root.skyP = (root.skyP + dt * root.speedClouds / root.windPeriod) % 1;
        root.wheatP = (root.wheatP + dt * root.speedWheat / root.windPeriod) % 1;
        root.cableP = (root.cableP + dt * root.speedCable / root.windPeriod) % 1;
        root.windClock = (root.windClock + dt * root.speedWind) % 3.6e6;
        root.flockClock = root.flockClock + dt * root.speedBirds;
    }

    // Une seule horloge image par image : chaque élément avance à sa propre vitesse,
    // et un changement de vitesse s'applique sans saut.
    FrameAnimation {
        running: root.animating && root.maxFps <= 0
        onTriggered: root.advance(frameTime)
    }
    // Variante plafonnée : un Timer ne force pas le rendu à chaque vsync (FrameAnimation, si).
    Timer {
        id: capped
        property double last: 0
        interval: Math.max(8, Math.round(1000 / Math.max(1, root.maxFps)))
        repeat: true
        running: root.animating && root.maxFps > 0
        onRunningChanged: last = 0
        onTriggered: {
            var now = Date.now();
            root.advance(last > 0 ? (now - last) / 1000 : interval / 1000);
            last = now;
        }
    }

    // Échelle de rendu des Canvas (net en 1440p / 4K)
    readonly property real rs: Math.min(2.5, Math.max(1, Math.max(root.width / 1920, root.height / 1080)))

    // Nuée d'étourneaux : un passage de 9 s toutes les 30 s
    readonly property int flockPass: Math.floor(flockClock / 30000)
    readonly property real flockT: { var l = flockClock % 30000; return (l > 5000 && l < 14000) ? (l - 5000) / 9000 : 0; }

    // Poteaux le long de la route : [échelle, x pied, y pied]
    // ---- Perspective : oeil à 1,80 m au milieu de la route, focale 700 px, horizon y = 620,
    //      pente de 32 % qui se replatit 9 m plus bas (géométrie calculée hors-ligne). ----
    // Poteaux : [x, y pied, y tête, pixels par mètre]
    // Poteaux 6 m : [x, y pied, y tête, px par mètre] — proche au bord du chemin, puis derrière la colline
    readonly property var poles: [[1312, 905, 645, 43.3], [1522, 836, 726, 18.3], [1762, 801, 741, 10.0]]
    // Épaule de la colline de droite : la route passe derrière vers 26 m
    readonly property var flank: [1392,  862,  1480,  876,  1560,  891,  1700,  915,  1820,  940,  1920,  962]
    // Hauteur apparente d'un épi de blé (~1,1 m) selon la ligne de pied, en px
    function wheatPx(y) { return Math.max(4, 0.74 * (y - 845)); }
    function wheatSkip(x, y) { return root.inRoad(x, y); }

    // ================= Géométrie : helpers =================
    // Spline de Catmull-Rom -> chemin SVG lisse. p = [x0,y0,x1,y1,...]
    function spline(p) {
        var n = p.length / 2;
        var s = "M" + p[0] + " " + p[1];
        for (var i = 0; i < n - 1; i++) {
            var a = Math.max(i - 1, 0), b = i, c = i + 1, d = Math.min(i + 2, n - 1);
            var c1x = p[b*2] + (p[c*2] - p[a*2]) / 6, c1y = p[b*2+1] + (p[c*2+1] - p[a*2+1]) / 6;
            var c2x = p[c*2] - (p[d*2] - p[b*2]) / 6, c2y = p[c*2+1] - (p[d*2+1] - p[b*2+1]) / 6;
            s += " C" + c1x + " " + c1y + " " + c2x + " " + c2y + " " + p[c*2] + " " + p[c*2+1];
        }
        return s;
    }
    // Surface fermée sous une crête
    function ground(ridge, bottomY) {
        var n = ridge.length;
        return spline(ridge) + " L" + ridge[n-2] + " " + bottomY + " L" + ridge[0] + " " + bottomY + " Z";
    }
    // Bande entre la crête et la crête décalée de dy (lumière rasante)
    function rim(ridge, dy) {
        var r2 = [];
        for (var i = ridge.length - 2; i >= 0; i -= 2) r2.push(ridge[i], ridge[i+1] + dy);
        return spline(ridge) + " L" + spline(r2).substring(1) + " Z";
    }
    // Ruban entre deux bords (route)
    function ribbon(left, right) {
        var r2 = [];
        for (var i = right.length - 2; i >= 0; i -= 2) r2.push(right[i], right[i+1]);
        return spline(left) + " L" + spline(r2).substring(1) + " Z";
    }
    // Interpolation d'un bord (liste croissante en y) -> x, ou null si hors de la route
    function edgeX(e, y) {
        if (y < e[1]) return null;
        for (var i = 0; i < e.length - 2; i += 2) {
            if (y <= e[i+3]) { var t = (y - e[i+1]) / (e[i+3] - e[i+1]); return e[i] + (e[i+2] - e[i]) * t; }
        }
        return e[e.length-2];
    }

    // Hauteur d'une crête (interpolation linéaire) — pour poser textures et vagues sur les collines
    function ridgeY(r, x) {
        if (x <= r[0]) return r[1];
        for (var i = 0; i < r.length - 2; i += 2)
            if (x <= r[i + 2]) { var f = (x - r[i]) / (r[i + 2] - r[i]); return r[i + 1] + (r[i + 3] - r[i + 1]) * f; }
        return r[r.length - 1];
    }

    // Bords de la route (de loin vers proche) — le bord droit se cache sous la colline de droite
    readonly property var roadLeft:  [1384,  856,  1357.5,  859.5,  1320,  866,  1275,  877.5,  1230,  892.5,  1185,  911,  1140,  937.5,  1102.5,  967.5,  1080,  997.5,  1040,  1040,  995,  1085,  950,  1130]
    readonly property var roadRight: [1391,  856.5,  1376,  861,  1350,  870,  1324,  881,  1301,  896,  1284,  915,  1276.5,  937.5,  1275,  967.5,  1275,  997.5,  1270,  1040,  1262,  1085,  1254,  1130]
    function inRoad(x, y) {
        var l = edgeX(root.roadLeft, y), r = edgeX(root.roadRight, y);
        if (l === null || r === null) return false;
        return x > l - 5 && x < r + 5;
    }

    // Crêtes (scène 1920x1080)
    readonly property var ridgeFar:  [800,722, 880,704, 965,685, 1125,645, 1275,615, 1425,595, 1475,593, 1605,615, 1725,642, 1790,668]
    readonly property var ridgeR1:   [1180,802, 1255,775, 1340,752, 1425,735, 1520,712, 1625,677, 1725,648, 1825,625, 1920,603]
    readonly property var ridgeHill: [-20,596, 40,592, 120,600, 185,622, 232,634, 300,612, 340,586, 362,576, 380,574, 610,574, 640,578, 700,587, 770,609, 825,645, 925,700, 1075,755, 1180,780, 1275,793, 1400,807, 1520,817]
    readonly property var ridgeLeft: [-20,700, 60,688, 150,655, 232,640, 330,655, 450,690, 560,735, 700,780, 825,813, 920,836, 1000,848, 1120,854, 1250,856, 1400,858]
    readonly property var ridgeR2:   [1255,1130, 1262,1085, 1271,1040, 1276,997, 1276,967, 1277,937, 1285,915, 1302,896, 1325,881, 1351,870, 1385,856, 1450,836, 1525,817, 1625,800, 1725,775, 1825,755, 1920,735]

    // ================= Composants =================
    component Poly: Shape {
        id: poly
        property string d
        property color col
        preferredRendererType: Shape.CurveRenderer
        ShapePath { fillColor: poly.col; strokeColor: "transparent"; strokeWidth: -1; PathSvg { path: poly.d } }
    }

    component GPoly: Shape {
        id: gp
        property string d
        property real gx1: 0
        property real gy1: 0
        property real gx2: 0
        property real gy2: 100
        property color c0: "white"
        property color cm: "white"
        property color c1: "white"
        property real pm: 0.5
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"; strokeWidth: -1
            fillGradient: LinearGradient {
                x1: gp.gx1; y1: gp.gy1; x2: gp.gx2; y2: gp.gy2
                GradientStop { position: 0.0; color: gp.c0 }
                GradientStop { position: gp.pm; color: gp.cm }
                GradientStop { position: 1.0; color: gp.c1 }
            }
            PathSvg { path: gp.d }
        }
    }

    // Cumulus en aplats nets façon cel-shading : chaque bosse = 3 disques emboîtés
    // (ombre, corps, lumière décalée vers le soleil à gauche). Tour à droite, traîne à gauche,
    // base plate, bord droit arrondi et entièrement contenu (pas de découpe au retour).
    component Cumulus: Item {
        id: cu
        property real phase: 0
        property real k: 3
        property real x0: 1500
        property real sc: 1
        property color cShade: "#e89b9b"
        property color cBody: "#f5ae9e"
        property color cLight: "#fbc5ae"
        property color cHi: "#fedccb"
        property color cInner: cShade
        // seed > 0 : silhouette générée (tours, tailles et espacements aléatoires)
        property int seed: 0
        property var custom: null
        property real extW: 560
        property real genW: 480
        property real genH: 170
        readonly property real base: 205
        readonly property var layout: custom ? custom : (seed > 0 ? cu.gen() : ({ lumps: cu.hand, top: 15, hiFrom: 7, hiTo: 11, inner: [] }))
        readonly property var lumps: layout.lumps
        readonly property int topCount: layout.top

        function gen() {
            var s = (cu.seed * 7919 + 13) >>> 0;
            function rnd() {
                s = (s + 0x6D2B79F5) >>> 0;
                var t = s;
                t = Math.imul(t ^ (t >>> 15), t | 1);
                t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            }
            var W = cu.genW, H = cu.genH, B = cu.base;
            function sm(e) { e = Math.max(0, Math.min(1, e)); return e * e * (3 - 2 * e); }
            var towers = [], nT = 1 + Math.floor(rnd() * 3);
            for (var i = 0; i < nT; i++)
                towers.push({ c: W * (0.3 + 0.62 * rnd()), h: H * (0.42 + 0.58 * rnd()), w: W * (0.08 + 0.15 * rnd()) });
            towers[0].h = H;   // au moins une vraie tour
            function prof(x) {
                var p = H * (0.12 + 0.12 * rnd()) * sm(x / (W * 0.3));
                for (var k = 0; k < towers.length; k++) {
                    var u = (x - towers[k].c) / towers[k].w;
                    p = Math.max(p, towers[k].h * Math.exp(-u * u));
                }
                return p * sm((W - x) / (W * 0.1)) * (0.9 + 0.2 * rnd());
            }
            var L = [], inner = [], x = 24;
            while (x < W - 26) {
                var p = Math.max(10, prof(x));
                var r = Math.max(9, Math.min(36, 0.24 * p + 9)) * (0.7 + 0.6 * rnd());
                var cy = Math.min(B - p + r * 0.95, B - r * 0.35);
                L.push([x, cy, r]);
                if (rnd() < 0.3 && p > 50) L.push([x + r * 0.35, cy - r * (0.35 + 0.3 * rnd()), r * (0.45 + 0.2 * rnd())]);
                // bosses intérieures sous la crête (relief)
                var depth = cy + r * (0.9 + 0.6 * rnd());
                while (depth < B - 22) {
                    var ri = r * (0.6 + 0.35 * rnd());
                    inner.push([x + (rnd() - 0.3) * r, depth, ri]);
                    depth += ri * (1.4 + 0.8 * rnd());
                }
                x += r * (0.42 + 0.33 * rnd());
            }
            var top = L.length, last = L[L.length - 1];
            var xr = last[0], yr = last[1];
            while (yr < B - 28) {
                var rr = 18 + rnd() * 16;
                yr += rr * (0.7 + 0.3 * rnd());
                xr = Math.min(W + 8, xr + (rnd() - 0.4) * 12);
                L.push([xr, Math.min(yr, B - rr * 0.5), rr]);
            }
            var xb = xr - 26;
            while (xb > 58) {
                var rb = 16 + rnd() * 16;
                L.push([xb, B - rb * (0.35 + 0.25 * rnd()), rb]);
                xb -= rb * (0.8 + 0.6 * rnd());
            }
            var hi = 1, best = 1e9;
            for (var j = 1; j < top; j++) if (L[j][1] - L[j][2] < best) { best = L[j][1] - L[j][2]; hi = j; }
            return { lumps: L, top: top, hiFrom: Math.max(1, hi - 3), hiTo: Math.min(top, hi + 3), inner: inner };
        }

        // silhouette dessinée à la main (petit nuage)
        property var hand: [
            [40,198,14], [70,188,20], [104,177,26], [140,168,24], [176,157,31],
            [212,141,34], [246,122,37], [286,103,43], [326,90,36], [360,66,51],
            [404,44,38], [436,46,27], [458,66,30], [474,94,33], [486,126,28],
            [488,158,27], [458,184,30], [404,192,30], [344,194,32], [284,194,30], [224,196,28], [164,198,24], [104,200,18]
        ]
        readonly property real ext: extW * sc
        // twin : une copie suit à distance "span" ; dès que le nuage sort d'un côté,
        // la copie entre déjà de l'autre => il y en a toujours un à l'écran
        property bool twin: false
        property real overlap: 0.55
        readonly property real cloudW: { var m = 0; for (var i = 0; i < lumps.length; i++) m = Math.max(m, lumps[i][0] + lumps[i][2]); return (m + 50) * sc; }
        readonly property real span: twin ? 1920 + overlap * cloudW : 1920 + 2 * ext + 40
        x: twin ? ((x0 + phase * k * span) % span) : ((x0 + ext + phase * k * span) % span) - ext
        scale: sc
        transformOrigin: Item.TopLeft


        // union de disques ; rf = rayon relatif, ox/oy = décalage relatif au rayon
        function disks(rf, ox, oy, from, to) {
            var d = "";
            for (var i = from; i < to; i++) {
                var c = cu.lumps[i];
                var r = c[2] * rf, x = c[0] + c[2] * ox, y = c[1] + c[2] * oy;
                d += "M" + (x - r) + " " + y + " A" + r + " " + r + " 0 1 1 " + (x + r) + " " + y
                   + " A" + r + " " + r + " 0 1 1 " + (x - r) + " " + y + " Z ";
            }
            return d;
        }
        // calotte éclairée continue : demi-disques supérieurs + bande qui les relie (pas de "perles")
        function caps(rf, ox, oy, drop, from, to) {
            var top = [], bot = [], d = "";
            for (var i = from; i < to; i++) {
                var c = cu.lumps[i];
                var r = c[2] * rf, x = c[0] + c[2] * ox, y = c[1] + c[2] * oy;
                d += "M" + (x - r) + " " + y + " A" + r + " " + r + " 0 1 1 " + (x + r) + " " + y
                   + " A" + r + " " + r + " 0 1 1 " + (x - r) + " " + y + " Z ";
                top.push([x, y]);
                bot.push([x, y + c[2] * drop]);
            }
            if (top.length > 1) {
                d += "M" + top[0][0] + " " + top[0][1];
                for (var j = 1; j < top.length; j++) d += " L" + top[j][0] + " " + top[j][1];
                for (var k = bot.length - 1; k >= 0; k--) d += " L" + bot[k][0] + " " + bot[k][1];
                d += " Z ";
            }
            return d;
        }
        function blobs(list, rf, ox, oy) {
            var d = "";
            for (var i = 0; i < list.length; i++) {
                var c = list[i], r = c[2] * rf, x = c[0] + c[2] * ox, y = c[1] + c[2] * oy;
                d += "M" + (x - r) + " " + y + " A" + r + " " + r + " 0 1 1 " + (x + r) + " " + y
                   + " A" + r + " " + r + " 0 1 1 " + (x - r) + " " + y + " Z ";
            }
            return d === "" ? "M0 0 Z" : d;
        }
        // polygone qui relie les centres (remplit l'intérieur)
        function core(ox, oy) {
            var d = "";
            for (var i = 0; i < cu.lumps.length; i++) {
                var c = cu.lumps[i];
                d += (i === 0 ? "M" : " L") + (c[0] + c[2] * ox) + " " + (c[1] + c[2] * oy);
            }
            return d + " Z ";
        }
        function solid(rf, ox, oy) { return cu.core(ox, oy) + cu.disks(rf, ox, oy, 0, cu.lumps.length); }

        Repeater {
            model: cu.twin ? 2 : 1
            Item {
                required property int index
                x: -60 - index * cu.span / cu.sc; y: -20
                width: cu.extW + 80; height: 260
                layer.enabled: true
                layer.samples: 8
                layer.smooth: true
                layer.textureSize: Qt.size(Math.ceil((cu.extW + 80) * cu.sc * root.rs * 1.25), Math.ceil(260 * cu.sc * root.rs * 1.25))
            Shape {
                x: 60; y: 20
                preferredRendererType: Shape.GeometryRenderer
                // traînées effilées à gauche
                ShapePath { fillColor: cu.cShade; strokeColor: "transparent"; strokeWidth: -1
                    PathSvg { path: "M-20 212 C 40 205 130 203 230 207 C 130 214 40 217 -20 212 Z" } }
                ShapePath { fillColor: cu.cBody; strokeColor: "transparent"; strokeWidth: -1
                    PathSvg { path: "M-46 202 C 0 194 52 191 116 195 C 60 202 8 207 -46 202 Z" } }
                // ombre : silhouette complète + base plate
                ShapePath { fillColor: cu.cShade; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.WindingFill
                    PathSvg { path: cu.solid(1.0, 0, 0) + "M40 " + (cu.base - 9) + " L" + (cu.lumps[cu.topCount - 1][0]) + " " + (cu.base - 9)
                                  + " L" + (cu.lumps[cu.topCount - 1][0] - 10) + " " + (cu.base + 7) + " L60 " + (cu.base + 9) + " Z" } }
                // corps : légèrement plus petit et décalé vers la lumière
                ShapePath { fillColor: cu.cBody; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.WindingFill
                    PathSvg { path: cu.solid(0.86, -0.07, -0.1) } }
                // bosses intérieures : un croissant d'ombre sous chaque bosse
                ShapePath { fillColor: cu.cInner; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.WindingFill
                    PathSvg { path: cu.blobs(cu.layout.inner, 1.0, 0, 0) } }
                ShapePath { fillColor: cu.cBody; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.WindingFill
                    PathSvg { path: cu.blobs(cu.layout.inner, 0.9, -0.08, -0.12) } }
                // lumière rasante sur la rangée du haut
                ShapePath { fillColor: cu.cLight; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.WindingFill
                    PathSvg { path: cu.caps(0.8, -0.12, -0.17, 0.12, 1, cu.topCount) } }
                // reflet sur le sommet de la tour
                ShapePath { fillColor: cu.cHi; strokeColor: "transparent"; strokeWidth: -1; fillRule: ShapePath.WindingFill
                    PathSvg { path: cu.caps(0.6, -0.24, -0.3, 0.0, cu.layout.hiFrom, cu.layout.hiTo) } }
            }
            }
        }
    }

    // Filaments de nuages (deux ellipses superposées)
    component Streak: Item {
        id: st
        property real phase: 0
        property real k: 1
        property real x0: 1300
        property real sw: 300
        property color col: "#f0b09b"
        property color col2: "#f9cbb8"
        readonly property real span: 1920 + 2 * sw
        // transparence aléatoire : chaque filament apparaît / s'estompe à son rythme
        property real op: 0.5
        property int f1: 7
        property int f2: 19
        property real ph: 0
        opacity: op * (0.55 + 0.3 * Math.sin(6.283185307 * f1 * root.skyP + ph) + 0.15 * Math.sin(6.283185307 * f2 * root.skyP + ph * 2.3))
        x: ((x0 + sw + phase * k * span) % span) - sw
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: st.col; strokeColor: "transparent"; strokeWidth: -1
                PathSvg { path: "M0 6 A" + (st.sw / 2) + " 5 0 1 0 " + st.sw + " 6 A" + (st.sw / 2) + " 5 0 1 0 0 6 Z" }
            }
            ShapePath {
                fillColor: st.col2; strokeColor: "transparent"; strokeWidth: -1
                PathSvg { path: "M" + (st.sw * 0.18) + " 4 A" + (st.sw * 0.32) + " 2.6 0 1 0 " + (st.sw * 0.82) + " 4 A" + (st.sw * 0.32) + " 2.6 0 1 0 " + (st.sw * 0.18) + " 4 Z" }
            }
        }
    }

    // Pale délabrée : arbre + longeron épais + voile en treillis aux barreaux manquants
    component Blade: Shape {
        id: bl
        property real len: 215
        property int seed: 1
        property real damage: 0.5
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        function lattice() {
            var s = bl.seed >>> 0;
            function rnd() {
                s = (s + 0x6D2B79F5) >>> 0;
                var t = s;
                t = Math.imul(t ^ (t >>> 15), t | 1);
                t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            }
            var x0 = 72, x1 = bl.len - 4, d = "", dm = bl.damage;
            function yt(x) { return -12 - (x - x0) / (x1 - x0) * 15; }
            function yb(x) { return 26 + (x - x0) / (x1 - x0) * 20; }
            function seg(ax, ay, bx, by) { d += "M" + ax.toFixed(1) + " " + ay.toFixed(1) + " L" + bx.toFixed(1) + " " + by.toFixed(1) + " "; }
            var i, j, n = 8;
            // cadre : morceaux manquants
            for (i = 0; i < n; i++) {
                var xa = x0 + (x1 - x0) * i / n, xb = x0 + (x1 - x0) * (i + 1) / n;
                if (rnd() > dm * 0.40) seg(xa, yt(xa), xb, yt(xb));
                if (rnd() > dm * 0.40) seg(xa, yb(xa), xb, yb(xb) + (rnd() - 0.5) * 3 * dm);
            }
            if (rnd() > dm * 0.55) seg(x0, yt(x0), x0, yb(x0));
            if (rnd() > dm * 0.55) seg(x1, yt(x1), x1 + (rnd() - 0.5) * 6, yb(x1));
            // barres longitudinales, par tronçons
            for (j = 1; j < 6; j++) {
                var f = j / 6;
                for (i = 0; i < 4; i++) {
                    if (rnd() < dm * 0.32) continue;
                    var xa2 = x0 + (x1 - x0) * i / 4, xb2 = x0 + (x1 - x0) * (i + 1) / 4;
                    var ya = yt(xa2) + (yb(xa2) - yt(xa2)) * f, yb2 = yt(xb2) + (yb(xb2) - yt(xb2)) * f;
                    seg(xa2, ya, xb2, yb2);
                }
            }
            // barres transversales, certaines cassées / de travers
            var m = 13;
            for (i = 1; i < m; i++) {
                if (rnd() < dm * 0.22) continue;
                var x = x0 + (x1 - x0) * i / m;
                var top = yt(x) + rnd() * dm * 16, bot = yb(x) - rnd() * dm * 16;
                var sk = (rnd() - 0.5) * 5 * (0.5 + dm);
                seg(x, top, x + sk, bot);
            }
            // fils de renfort tordus
            for (i = 0; i < 2; i++) {
                var xs = x0 + rnd() * (x1 - x0) * 0.6;
                seg(xs, yt(xs), xs + 24 + rnd() * 30, yb(xs + 30) - rnd() * 18);
            }
            return d;
        }

        // reflet clair sous le treillis
        ShapePath {
            fillColor: "transparent"; strokeColor: "#40ffd6c4"; strokeWidth: 2.6
            PathSvg { path: bl.lattice() }
        }
        // treillis sombre
        ShapePath {
            fillColor: "transparent"; strokeColor: "#ee283556"; strokeWidth: 1.3
            PathSvg { path: bl.lattice() }
        }
        // arbre (fin près du moyeu)
        ShapePath {
            fillColor: "#18233b"; strokeColor: "transparent"; strokeWidth: -1
            PathSvg { path: "M8 -4 L70 -5.5 L70 5.5 L8 4 Z" }
        }
        // longeron épais, extrémité irrégulière
        ShapePath {
            fillColor: "#18233b"; strokeColor: "transparent"; strokeWidth: -1
            PathSvg {
                path: "M55 -4 L" + (bl.len * 0.35) + " -7.5 L" + (bl.len * 0.7) + " -9.5 L" + (bl.len - 7) + " -8.5 L" + bl.len + " -5 L"
                      + (bl.len - 2) + " 4 L" + (bl.len - 9) + " 8.5 L" + (bl.len * 0.7) + " 9.5 L" + (bl.len * 0.35) + " 7.5 L55 4.5 Z"
            }
        }
    }

    // Touffes d'herbe sèche le long d'une ligne (crête, bord de route...)
    component RidgeTufts: Canvas {
        id: rt
        property var pts: []
        property int count: 160
        property real hMin: 6
        property real hMax: 18
        property real dropMax: 4
        property string c0: "#6a3a40"
        property string c1: "#d98a60"
        property int seed: 1
        property var hs: null           // si défini : hauteur(px) = hs(y) * [hMin..hMax]
        property real hBox: hs ? 260 : hMax
        readonly property real minX: { var m = 1e9; for (var i = 0; i < pts.length; i += 2) m = Math.min(m, pts[i]); return m; }
        readonly property real maxX: { var m = -1e9; for (var i = 0; i < pts.length; i += 2) m = Math.max(m, pts[i]); return m; }
        readonly property real minY: { var m = 1e9; for (var i = 1; i < pts.length; i += 2) m = Math.min(m, pts[i]); return m; }
        readonly property real maxY: { var m = -1e9; for (var i = 1; i < pts.length; i += 2) m = Math.max(m, pts[i]); return m; }
        x: minX - 30
        y: minY - hBox - 30
        width: (maxX - minX + 60) * root.rs
        height: (Math.min(1100, maxY + 30) - (minY - hBox - 30)) * root.rs
        transform: Scale { xScale: 1 / root.rs; yScale: 1 / root.rs }
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.scale(root.rs, root.rs);
            var s = rt.seed >>> 0;
            function rnd() {
                s = (s + 0x6D2B79F5) >>> 0;
                var t = s;
                t = Math.imul(t ^ (t >>> 15), t | 1);
                t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            }
            var lens = [], tot = 0, i;
            for (i = 0; i < pts.length - 2; i += 2) {
                var l = Math.hypot(pts[i+2] - pts[i], pts[i+3] - pts[i+1]);
                lens.push(l); tot += l;
            }
            for (var n = 0; n < rt.count; n++) {
                var d = rnd() * tot, k = 0;
                while (k < lens.length - 1 && d > lens[k]) { d -= lens[k]; k++; }
                var t2 = d / lens[k];
                var px = pts[k*2] + (pts[k*2+2] - pts[k*2]) * t2 - rt.x;
                var py = pts[k*2+1] + (pts[k*2+3] - pts[k*2+1]) * t2 - rt.y + rnd() * rt.dropMax;
                var nb = 1 + Math.floor(rnd() * 3.5);
                for (var b = 0; b < nb; b++) {
                    var h = rt.hs ? rt.hs(py + rt.y) * (rt.hMin + rnd() * (rt.hMax - rt.hMin)) : rt.hMin + rnd() * (rt.hMax - rt.hMin);
                    var bx = px + (rnd() - 0.5) * 7 * (rt.hs ? Math.max(0.3, h / 20) : 1), bend = (rnd() - 0.45) * h * 0.7, w = 1 + rnd() * 1.4;
                    var g = ctx.createLinearGradient(0, py, 0, py - h);
                    g.addColorStop(0, rt.c0);
                    g.addColorStop(1, rt.c1);
                    ctx.fillStyle = g;
                    ctx.beginPath();
                    ctx.moveTo(bx - w / 2, py);
                    ctx.quadraticCurveTo(bx + bend * 0.25, py - h * 0.55, bx + bend, py - h);
                    ctx.quadraticCurveTo(bx + bend * 0.25 + w * 0.5, py - h * 0.5, bx + w / 2, py);
                    ctx.closePath();
                    ctx.fill();
                }
            }
        }
    }

    // Herbe de premier plan : touffes, brins isolés, épis ; hauteur/forme/densité variables,
    // par plaques (bruit lisse), couleurs alternées, trouée pour la route.
    component GrassLayer: Item {
        id: gl
        property real baseY: 900
        property int segments: 8
        property real hMin: 40
        property real hMax: 100
        property real wMin: 2
        property real wMax: 3
        property real spacing: 2.4
        property real amp: 0.05
        property real canvasH: root.wheatPx(baseY + waveAmp + carpetDepth) * 1.45 + 40 + carpetDepth + waveAmp
        property real jitter: 14
        property real carpetDepth: 0
        property real carpetFrac: 0.8
        property int seed: 1
        property string c0: "#7a3a47"
        property string c1: "#d85a4c"
        property var tips: ["#f26a4f"]
        // fondu atmosphérique : plus le plan est loin, plus il prend la couleur du flanc de colline
        property color fadeCol: "#e06a56"
        property real fade: 0
        function mixc(hex, k) {
            var h = ("" + hex).replace("#", "");
            if (h.length === 8) h = h.substring(2);
            var f = ("" + gl.fadeCol).replace("#", "");
            if (f.length === 8) f = f.substring(2);
            var out = "#";
            for (var i = 0; i < 6; i += 2) {
                var a = parseInt(h.substring(i, i + 2), 16), b = parseInt(f.substring(i, i + 2), 16);
                var v = Math.round(a + (b - a) * k);
                out += (v < 16 ? "0" : "") + v.toString(16);
            }
            return out;
        }
        readonly property string fc0: mixc(c0, fade)
        readonly property string fc1: mixc(c1, fade * 0.85)
        readonly property var ftips: { var t = []; for (var i = 0; i < tips.length; i++) t.push(mixc(tips[i], fade * 0.6)); return t; }
        property real windP: 0
        property var skip: function(x, y) { return false; }
        property real waveAmp: 18
        property real earProb: 0.3
        readonly property real segW: 1920 / segments
        readonly property real pad: 60

        // bruit lisse 1D (même graine pour tous les segments)
        function hash(i) {
            var h = (((gl.seed * 2654435761) >>> 0) + i * 374761393) >>> 0;
            h = Math.imul(h ^ (h >>> 13), 1274126177);
            return (((h ^ (h >>> 16)) >>> 0) / 4294967296);
        }
        function nz(x) {
            var i = Math.floor(x), f = x - i;
            f = f * f * (3 - 2 * f);
            return gl.hash(i) * (1 - f) + gl.hash(i + 1) * f;
        }
        // ligne de pied ondulée (plus de bord droit)
        function baseOff(x) {
            return (gl.nz(x * 0.0055 + 51.7) - 0.5) * 2 * gl.waveAmp + (gl.nz(x * 0.021 + 7.1) - 0.5) * gl.waveAmp * 0.6;
        }
        function rgba(hex, a) {
            var h = ("" + hex).replace("#", "");
            if (h.length === 8) h = h.substring(2);
            return "rgba(" + parseInt(h.substring(0, 2), 16) + "," + parseInt(h.substring(2, 4), 16) + "," + parseInt(h.substring(4, 6), 16) + "," + a + ")";
        }

        // ombre douce au pied de l'herbe, qui suit la ligne ondulée
        Canvas {
            id: shade
            readonly property real headroom: 70
            x: 0
            y: gl.baseY - shade.headroom
            width: 1920 * root.rs
            height: (shade.headroom + gl.carpetDepth + gl.waveAmp + 70) * root.rs
            transform: Scale { xScale: 1 / root.rs; yScale: 1 / root.rs }
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.scale(root.rs, root.rs);
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.strokeStyle = gl.fc0;
                var k = Math.max(0.25, Math.min(1.2, root.wheatPx(gl.baseY) / 120));
                var passes = [[80 * k, 0.09, 30 * k], [50 * k, 0.12, 22 * k], [26 * k, 0.14, 14 * k]];
                for (var p = 0; p < passes.length; p++) {
                    ctx.lineWidth = passes[p][0];
                    ctx.globalAlpha = passes[p][1];
                    ctx.beginPath();
                    var open = false;
                    for (var x = -30; x <= 1950; x += 8) {
                        var yy = shade.headroom + gl.baseOff(x) + passes[p][2];
                        if (gl.skip(x, gl.baseY + yy - shade.headroom)) { open = false; continue; }
                        if (!open) { ctx.moveTo(x, yy); open = true; } else ctx.lineTo(x, yy);
                    }
                    ctx.stroke();
                }
            }
        }

        function wind(xn, p) {
            var T = 6.283185307;
            var base = Math.sin(T * (75 * p - 1.3 * xn)) * 0.55;
            var flutter = Math.sin(T * (181 * p - 3.1 * xn + 0.3)) * 0.16;
            var g1 = 0.5 + 0.5 * Math.sin(T * (23 * p - 0.9 * xn));
            var g2 = 0.5 + 0.5 * Math.sin(T * (61 * p - 1.7 * xn + 0.4));
            var gust = g1 * g1 * g2;
            return (0.35 + 0.65 * gust) * (base + flutter) + 0.30 * gust;
        }

        // Cisaillement des 8 segments mis à jour en une seule passe par image
        // (au lieu de 2 bindings par segment, soit 112 bindings réévalués à chaque image pour 7 plans).
        function applyWind() {
            var n = gl.segments, p = gl.windP, amp = gl.amp;
            for (var i = 0; i < n; i++) {
                var c = segRep.itemAt(i);
                if (!c) continue;
                var sh = gl.wind((i + 0.5) / n, p) * amp, bl = c.baseLocal;
                c.transform[1].matrix = Qt.matrix4x4(1, -sh, 0, sh * bl,
                                              0, 1, 0, 0,
                                              0, 0, 1, 0,
                                              0, 0, 0, 1);
            }
        }
        onWindPChanged: applyWind()

        Repeater {
            id: segRep
            model: gl.segments
            onItemAdded: gl.applyWind()
            Canvas {
                id: cv
                required property int index
                readonly property real baseLocal: gl.canvasH - 14 - gl.carpetDepth - gl.waveAmp
                x: index * gl.segW - gl.pad
                y: gl.baseY - baseLocal
                width: (gl.segW + 2 * gl.pad) * root.rs
                height: gl.canvasH * root.rs
                transform: [
                    Scale { xScale: 1 / root.rs; yScale: 1 / root.rs },
                    Matrix4x4 { }
                ]
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.scale(root.rs, root.rs);
                    var s = (gl.seed * 7919 + index * 104729) >>> 0;
                    function rnd() {
                        s = (s + 0x6D2B79F5) >>> 0;
                        var t = s;
                        t = Math.imul(t ^ (t >>> 15), t | 1);
                        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
                        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
                    }
                    var segX0 = index * gl.segW;
                    var blades = [];
                    var tufts = Math.round(gl.segW / gl.spacing);
                    var total = tufts + Math.round(tufts * (gl.carpetDepth > 0 ? gl.carpetFrac : 0));
                    for (var i = 0; i < total; i++) {
                        var deep = i >= tufts;
                        var xs = segX0 + rnd() * gl.segW;
                        var dy = deep ? (0.15 + rnd() * 0.85) * gl.carpetDepth : (rnd() - 0.5) * gl.jitter;
                        dy += gl.baseOff(xs);
                        var ys = gl.baseY + dy;
                        if (gl.skip(xs, ys)) continue;
                        var dens = gl.nz(xs * 0.011 + 3.7);
                        if (rnd() > 0.30 + 0.95 * dens) continue;              // plaques clairsemées
                        var hf = (0.8 + 0.35 * gl.nz(xs * 0.0045 + 11.3)) * (deep ? 0.5 : 1);            // plaques hautes / basses
                        var tip = gl.ftips[Math.floor(rnd() * gl.ftips.length)];
                        var kind = rnd();
                        var lx = gl.pad + (xs - segX0), ly = baseLocal + dy;
                        var nb = 1, spread = 0;
                        var wp = root.wheatPx(ys);
                        if (kind > 0.45) { nb = 2 + Math.floor(rnd() * 5); spread = (4 + rnd() * 7) * Math.max(0.3, wp / 150); }
                        var lean = (rnd() - 0.4) * 0.5;
                        for (var b = 0; b < nb; b++) {
                            var h = wp * hf * (0.55 + 0.5 * Math.pow(rnd(), 0.7));
                            var fan = nb > 1 ? ((b / (nb - 1)) - 0.5) * 2 : 0;
                            blades.push({
                                x: lx + fan * spread * 0.6 + (rnd() - 0.5) * 3,
                                y: ly,
                                h: Math.max(3, h),
                                w: gl.wMin + rnd() * (gl.wMax - gl.wMin),
                                b1: (lean + fan * 0.35 + (rnd() - 0.5) * 0.3) * h,
                                b2: (lean + fan * 0.55 + (rnd() - 0.5) * 0.5) * h,
                                kink: rnd() < 0.18 ? (rnd() - 0.5) * h * 0.5 : 0,
                                tip: tip,
                                head: rnd() < gl.earProb && h > 12,
                                a: 0.82 + 0.18 * rnd(),
                                lit: 0.8 + 0.4 * rnd()
                            });
                        }
                    }
                    blades.sort(function(a, b) { return a.y - b.y; });
                    for (var q = 0; q < blades.length; q++) {
                        var bd = blades[q];
                        var g = ctx.createLinearGradient(0, bd.y, 0, bd.y - bd.h);
                        g.addColorStop(0, gl.rgba(gl.fc0, 0));
                        g.addColorStop(0.2, gl.fc0);
                        g.addColorStop(0.55, gl.fc1);
                        g.addColorStop(1, bd.tip);
                        ctx.fillStyle = g;
                        ctx.strokeStyle = bd.tip;
                        ctx.globalAlpha = bd.a;
                        var tx = bd.x + bd.b2 + bd.kink, ty = bd.y - bd.h;
                        ctx.beginPath();
                        ctx.moveTo(bd.x - bd.w / 2, bd.y);
                        ctx.bezierCurveTo(bd.x + bd.b1 * 0.35 - bd.w * 0.4, bd.y - bd.h * 0.35,
                                          bd.x + bd.b1 - bd.w * 0.3, bd.y - bd.h * 0.7, tx, ty);
                        ctx.bezierCurveTo(bd.x + bd.b1 + bd.w * 0.3, bd.y - bd.h * 0.7,
                                          bd.x + bd.b1 * 0.35 + bd.w * 0.4, bd.y - bd.h * 0.35, bd.x + bd.w / 2, bd.y);
                        ctx.closePath();
                        ctx.fill();
                        if (bd.head) {   // épi de blé : grains alternés + barbes
                            var mx = bd.x + bd.b1, my = bd.y - bd.h * 0.7;
                            var ux = tx - mx, uy = ty - my, ul = Math.sqrt(ux * ux + uy * uy) || 1;
                            ux /= ul; uy /= ul;
                            var pxv = -uy, pyv = ux;
                            var el = Math.max(3, bd.h * 0.13), ew = Math.max(0.9, bd.h * 0.024);
                            var nk = 5;
                            ctx.fillStyle = bd.tip;
                            for (var kk = 0; kk < nk; kk++) {
                                var sg = (kk % 2) ? 1 : -1, fpos = el * (kk + 0.5) / nk;
                                var kx = tx - ux * fpos + pxv * sg * ew * 0.38, ky = ty - uy * fpos + pyv * sg * ew * 0.38;
                                var kw = ew * (0.85 - 0.25 * kk / nk), kh = el / nk * 1.9;
                                ctx.beginPath(); ctx.ellipse(kx - kw / 2, ky - kh / 2, kw, kh); ctx.fill();
                                if (bd.h > 55) {
                                    ctx.strokeStyle = bd.tip;
                                    ctx.lineWidth = 0.5;
                                    ctx.beginPath();
                                    ctx.moveTo(kx, ky);
                                    ctx.lineTo(kx + ux * el * 0.55 + pxv * sg * ew * 1.3, ky + uy * el * 0.55 + pyv * sg * ew * 1.3);
                                    ctx.stroke();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Vague de vent "anime" sur le flanc d'une colline : traits clairs qui suivent la pente,
    // glissent avec le vent puis s'effacent. Dessinée juste après sa colline => les plans
    // plus proches la recouvrent naturellement.
    component WindWave: Shape {
        id: ww
        property var ridge: []
        property real depth: 60
        property real x0: 0
        property real travel: 240
        property real len: 150
        property real thick: 4.2
        property int strands: 3
        property color col: "#ffdcc6"
        property real peak: 0.55
        property int dur: 4400
        property int delay: 0
        property int rest: 9000
        readonly property real t: {
            var per = ww.delay + ww.dur + ww.rest, l = root.windClock % per;
            if (l < ww.delay || l > ww.delay + ww.dur) return 0;
            var x = (l - ww.delay) / ww.dur;
            return -(Math.cos(Math.PI * x) - 1) / 2;
        }
        preferredRendererType: Shape.CurveRenderer
        visible: t > 0.001 && t < 0.999
        opacity: peak * Math.pow(Math.sin(Math.PI * t), 1.3)

        // copie locale de la crête (évite les allers-retours QML <-> JS à chaque point)
        readonly property var rg: ridge
        function build() {
            var t = ww.t;
            if (t <= 0.001 || t >= 0.999) return "M0 0 Z";
            var r = ww.rg, rn = r.length, len = ww.len, depth = ww.depth, thick = ww.thick, ns = ww.strands;
            var d = "", cx = ww.x0 + ww.travel * t;
            var grow = 0.55 + 0.45 * Math.sin(Math.PI * Math.min(1, t * 1.4) / 2);
            for (var k = 0; k < ns; k++) {
                var L = len * (1 - 0.22 * k) * grow;
                var ox = cx - k * len * 0.16 + (k % 2) * len * 0.1;
                var dy = depth + k * thick * 2.8;
                var th = thick * (1 - 0.18 * k);
                var top = [], bot = [];
                for (var i = 0; i <= 16; i++) {
                    var u = i / 16, x = ox + (u - 0.5) * L, bb = Math.sin(Math.PI * u);
                    // root.ridgeY en ligne, mêmes opérations
                    var ry;
                    if (x <= r[0]) ry = r[1];
                    else {
                        ry = r[rn - 1];
                        for (var j = 0; j < rn - 2; j += 2)
                            if (x <= r[j + 2]) { var f = (x - r[j]) / (r[j + 2] - r[j]); ry = r[j + 1] + (r[j + 3] - r[j + 1]) * f; break; }
                    }
                    var base = ry + dy, xr = Math.round(x * 10) / 10;
                    top.push(xr, Math.round((base - th * bb * (0.6 + 0.7 * u)) * 10) / 10);
                    bot.push(xr, Math.round((base + th * 0.25 * bb) * 10) / 10);
                }
                for (var m = bot.length - 2; m >= 0; m -= 2) top.push(bot[m], bot[m + 1]);
                d += "M" + top.join(" ") + " Z ";
            }
            return d;
        }
        ShapePath { fillColor: ww.col; strokeColor: "transparent"; strokeWidth: -1; PathSvg { path: ww.build() } }
    }

    // Texture "coups de pinceau" qui suivent les courbes de niveau d'une colline
    component HillStrokes: Canvas {
        id: hs
        property var ridge: []
        property real xMin: 0
        property real xMax: 1920
        property real dMin: 8
        property real dMax: 200
        property int count: 150
        property real lenMin: 30
        property real lenMax: 120
        property var cols: ["#ffffff"]
        property real aMin: 0.05
        property real aMax: 0.13
        property real wMin: 0.8
        property real wMax: 2.2
        property int seed: 1
        property var floor: []
        readonly property real minRidge: { var m = 1e9; for (var i = 1; i < ridge.length; i += 2) m = Math.min(m, ridge[i]); return m; }
        x: Math.max(-40, xMin - 20)
        y: minRidge - 20
        width: (Math.min(1960, xMax + 20) - x) * root.rs
        height: (Math.min(1080, minRidge + dMax + 60) - y) * root.rs
        transform: Scale { xScale: 1 / root.rs; yScale: 1 / root.rs }
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.scale(root.rs, root.rs);
            ctx.translate(-hs.x, -hs.y);
            ctx.lineCap = "round";
            var s = (hs.seed * 48271) >>> 0;
            function rnd() {
                s = (s + 0x6D2B79F5) >>> 0;
                var t = s;
                t = Math.imul(t ^ (t >>> 15), t | 1);
                t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            }
            var r = hs.ridge, rx0 = Math.max(hs.xMin, r[0]), rx1 = Math.min(hs.xMax, r[r.length - 2]);
            for (var n = 0; n < hs.count; n++) {
                var dn = Math.pow(rnd(), 1.25);
                var d = hs.dMin + dn * (hs.dMax - hs.dMin);
                var L = (hs.lenMin + rnd() * (hs.lenMax - hs.lenMin)) * (0.6 + 0.8 * dn);
                var x = rx0 + L / 2 + rnd() * Math.max(1, rx1 - rx0 - L);
                var bow = (rnd() - 0.5) * 6;
                ctx.strokeStyle = hs.cols[Math.floor(rnd() * hs.cols.length)];
                ctx.globalAlpha = hs.aMin + rnd() * (hs.aMax - hs.aMin);
                ctx.lineWidth = (hs.wMin + rnd() * (hs.wMax - hs.wMin)) * (0.7 + 0.6 * dn);
                ctx.beginPath();
                for (var i = 0; i <= 10; i++) {
                    var u = i / 10, px = x + (u - 0.5) * L;
                    var py = root.ridgeY(r, px) + d + bow * Math.sin(Math.PI * u);
                    if (hs.floor.length && py > root.ridgeY(hs.floor, px) - 4) break;
                    if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                }
                ctx.stroke();
            }
        }
    }

    // Arbres nus (branches récursives + houppier clairsemé)
    component BareTrees: Canvas {
        id: bt
        property var trees: []          // [x, yPied, hauteur, graine]
        property string col: "#5a4658"
        property string crown: "#7a5a68"
        property real crownAlpha: 0.3
        property real baseFade: 0          // > 0 : la base devient transparente sur cette fraction de hauteur
        property real bx: 0
        property real by: 0
        property real bw: 100
        property real bh: 100
        x: bx; y: by
        width: bw * root.rs
        height: bh * root.rs
        transform: Scale { xScale: 1 / root.rs; yScale: 1 / root.rs }
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.scale(root.rs, root.rs);
            ctx.translate(-bt.bx, -bt.by);
            ctx.lineCap = "round";
            var s = 1;
            function rnd() {
                s = (s + 0x6D2B79F5) >>> 0;
                var t = s;
                t = Math.imul(t ^ (t >>> 15), t | 1);
                t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            }
            function branch(x, y, len, ang, w, depth) {
                var x2 = x + Math.cos(ang) * len, y2 = y - Math.sin(ang) * len;
                ctx.lineWidth = w;
                ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x2, y2); ctx.stroke();
                if (depth <= 0 || len < 1.0) return;
                var n = rnd() < 0.3 ? 3 : 2;
                for (var i = 0; i < n; i++) {
                    var a = ang + (i - (n - 1) / 2) * (0.42 + rnd() * 0.32) + (rnd() - 0.5) * 0.28;
                    branch(x2, y2, len * (0.62 + rnd() * 0.16), a, Math.max(0.35, w * 0.64), depth - 1);
                }
            }
            for (var k = 0; k < bt.trees.length; k++) {
                var tr = bt.trees[k], h = tr[2];
                s = (tr[3] * 9973) >>> 0;
                ctx.globalAlpha = bt.crownAlpha;
                ctx.fillStyle = bt.crown;
                for (var c = 0; c < 5; c++) {
                    var cx = tr[0] + (rnd() - 0.5) * h * 0.45, cy = tr[1] - h * (0.72 + rnd() * 0.3);
                    var rw = h * (0.16 + rnd() * 0.14), rh = h * (0.12 + rnd() * 0.1);
                    ctx.beginPath(); ctx.ellipse(cx - rw, cy - rh, 2 * rw, 2 * rh); ctx.fill();
                }
                ctx.globalAlpha = 1;
                if (bt.baseFade > 0) {
                    var hc = ("" + bt.col).replace("#", "");
                    if (hc.length === 8) hc = hc.substring(2);
                    var rgb = parseInt(hc.substring(0, 2), 16) + "," + parseInt(hc.substring(2, 4), 16) + "," + parseInt(hc.substring(4, 6), 16);
                    var fg = ctx.createLinearGradient(0, tr[1] + 2, 0, tr[1] - h * bt.baseFade);
                    fg.addColorStop(0, "rgba(" + rgb + ",0)");
                    fg.addColorStop(1, "rgba(" + rgb + ",1)");
                    ctx.strokeStyle = fg;
                } else ctx.strokeStyle = bt.col;
                branch(tr[0], tr[1], h * 0.36, Math.PI / 2 + (rnd() - 0.5) * 0.16, Math.max(0.8, h * 0.055), 5);
            }
        }
    }

    // Petit poteau en bois (6 m) : fût fin légèrement conique, chapeau, petite console
    // à gauche avec un seul isolateur (ppm = pixels par mètre à sa distance)
    component Pole: Shape {
        id: po
        property real bx: 0
        property real by: 0
        property real ty: 0
        property real ppm: 10
        readonly property real wt: Math.max(1.0, 0.13 * ppm)
        readonly property real wb: Math.max(1.2, 0.19 * ppm)
        readonly property real by2: ty + 0.42 * ppm          // pied de la console
        readonly property real ax: bx - 0.3 * ppm            // isolateur (attache du câble)
        readonly property real ay: ty + 0.2 * ppm
        readonly property real iw: Math.max(0.7, 0.05 * ppm)
        readonly property real ih: Math.max(1.0, 0.1 * ppm)
        preferredRendererType: Shape.CurveRenderer
        // fût
        ShapePath { fillColor: "#2d2433"; strokeColor: "transparent"; strokeWidth: -1
            PathSvg { path: "M" + (po.bx - po.wb / 2) + " " + po.by + " L" + (po.bx - po.wt / 2) + " " + po.ty
                          + " Q" + po.bx + " " + (po.ty - po.wt * 0.35) + " " + (po.bx + po.wt / 2) + " " + po.ty
                          + " L" + (po.bx + po.wb / 2) + " " + po.by + " Z" } }
        // arête éclairée par le couchant
        ShapePath { fillColor: "#90d08a66"; strokeColor: "transparent"; strokeWidth: -1
            PathSvg { path: "M" + (po.bx - po.wb / 2) + " " + po.by + " L" + (po.bx - po.wt / 2) + " " + po.ty
                          + " L" + (po.bx - po.wt / 2 + po.wt * 0.3) + " " + po.ty + " L" + (po.bx - po.wb / 2 + po.wb * 0.3) + " " + po.by + " Z" } }
        // veines du bois
        ShapePath { fillColor: "transparent"; strokeColor: "#30140f1a"; strokeWidth: Math.max(0.4, 0.012 * po.ppm)
            PathSvg { path: "M" + (po.bx + po.wb * 0.12) + " " + po.by + " L" + (po.bx + po.wt * 0.12) + " " + po.ty } }
        // console : petite pièce de bois en biais
        ShapePath { fillColor: "transparent"; strokeColor: "#2d2433"; strokeWidth: Math.max(0.7, 0.05 * po.ppm); capStyle: ShapePath.RoundCap
            PathSvg { path: "M" + (po.bx - po.wt * 0.4) + " " + po.by2 + " L" + po.ax + " " + (po.ay + po.ih) } }
        // isolateur unique
        ShapePath { fillColor: "#4a3c46"; strokeColor: "transparent"; strokeWidth: -1
            PathSvg { path: "M" + (po.ax - po.iw / 2) + " " + (po.ay + po.ih) + " L" + (po.ax - po.iw / 2) + " " + po.ay
                          + " Q" + po.ax + " " + (po.ay - po.iw * 0.7) + " " + (po.ax + po.iw / 2) + " " + po.ay
                          + " L" + (po.ax + po.iw / 2) + " " + (po.ay + po.ih) + " Z" } }
    }

    // Tout le visuel est dans UN conteneur plein écran : les widgets d'effets
    // (Wallpaper Effects : flou, grain…) floutent le dernier enfant plein écran du fond.
    Item {
        id: canvasRoot
        anchors.fill: parent
        clip: true

        // ================= Fond de sécurité =================
        Rectangle { anchors.fill: parent; color: "#2a2538" }

        // ================= Scène =================
        Item {
            id: scene
            width: 1920
            height: 1080
            anchors.centerIn: parent
            scale: Math.max(root.width / 1920, root.height / 1080)

            // Ciel
            Rectangle {
                x: 0; y: 0; width: 1920; height: 620
                gradient: Gradient {
                    GradientStop { position: 0.00; color: "#7f9db6" }
                    GradientStop { position: 0.08; color: "#8da3b8" }
                    GradientStop { position: 0.23; color: "#9aa3b2" }
                    GradientStop { position: 0.38; color: "#b1a2a7" }
                    GradientStop { position: 0.53; color: "#d0a499" }
                    GradientStop { position: 0.69; color: "#eba38b" }
                    GradientStop { position: 0.84; color: "#f19e84" }
                    GradientStop { position: 0.94; color: "#ed9784" }
                    GradientStop { position: 1.00; color: "#e29585" }
                }
            }
            Rectangle {
                x: 0; y: 590; width: 1920; height: 330
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#e29585" }
                    GradientStop { position: 0.4; color: "#b88f94" }
                    GradientStop { position: 1.0; color: "#8f7a8c" }
                }
            }
            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"; strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: 190; centerY: 250; centerRadius: 760
                        focalX: 190; focalY: 250
                        GradientStop { position: 0.0; color: "#8cf3bda4" }
                        GradientStop { position: 0.55; color: "#80ecb29d" }
                        GradientStop { position: 1.0; color: "#00ecb29d" }
                    }
                    PathSvg { path: "M0 0 L1920 0 L1920 620 L0 620 Z" }
                }
            }

            // ----- Nuages, comme sur la photo : deux filaments en haut à droite, un long filament,
            //       et la grande masse moutonneuse qui monte derrière la montagne -----
            Streak { y: 196; x0: 1600; sw: 260; k: 1; phase: root.cloudPhase; col: "#b8a8b4"; col2: "#d2c2c8"; op: 0.55; f1: 6;  f2: 17; ph: 0.4 }
            Streak { y: 209; x0: 1690; sw: 130; k: 1; phase: root.cloudPhase; col: "#bcabb6"; col2: "#d6c4c8"; op: 0.4;  f1: 9;  f2: 23; ph: 2.1 }
            Streak { y: 371; x0: 1420; sw: 235; k: 2; phase: root.cloudPhase; col: "#f0b09b"; col2: "#f9cdb9"; op: 0.75; f1: 5;  f2: 13; ph: 1.0 }
            // filaments fins répartis pour que le ciel ne se vide jamais
            Streak { y: 238; x0: 300;  sw: 330; k: 1; phase: root.cloudPhase; col: "#c4aab0"; col2: "#dcc4c4"; op: 0.38; f1: 4;  f2: 21; ph: 0.9 }
            Streak { y: 252; x0: 420;  sw: 150; k: 1; phase: root.cloudPhase; col: "#c8acb0"; col2: "#e0c6c4"; op: 0.28; f1: 11; f2: 29; ph: 3.3 }
            Streak { y: 282; x0: 980;  sw: 380; k: 1; phase: root.cloudPhase; col: "#d0aca8"; col2: "#e6c4bc"; op: 0.42; f1: 8;  f2: 15; ph: 5.0 }
            Streak { y: 330; x0: 60;   sw: 300; k: 2; phase: root.cloudPhase; col: "#dcb0a2"; col2: "#f0c8b8"; op: 0.45; f1: 3;  f2: 19; ph: 1.7 }
            Streak { y: 345; x0: 180;  sw: 140; k: 2; phase: root.cloudPhase; col: "#dcb0a2"; col2: "#f0c8b8"; op: 0.3;  f1: 10; f2: 27; ph: 4.2 }
            Streak { y: 418; x0: 780;  sw: 290; k: 2; phase: root.cloudPhase; col: "#efa894"; col2: "#f8c0ac"; op: 0.45; f1: 7;  f2: 18; ph: 2.8 }
            Streak { y: 462; x0: 420;  sw: 420; k: 3; phase: root.cloudPhase; col: "#f2a58e"; col2: "#f8bca6"; op: 0.35; f1: 5;  f2: 22; ph: 0.2 }
            Streak { y: 478; x0: 1250; sw: 220; k: 3; phase: root.cloudPhase; col: "#f2a58e"; col2: "#f8bca6"; op: 0.3;  f1: 12; f2: 25; ph: 3.9 }
            Cumulus {
                y: 262; x0: 1440; k: 1; phase: root.cloudPhase; extW: 640; twin: true
                cShade: "#e2908e"; cBody: "#efa898"; cLight: "#f9c3ad"; cHi: "#fdd9c6"; cInner: "#eb9f95"
                custom: {"lumps": [[80, 194.2, 15.9], [90.2, 194.6, 18.3], [102.7, 187.3, 13.0], [111.5, 189.7, 17.3], [119.4, 187.5, 16.4], [128.8, 186.7, 17.5], [137.2, 181.5, 16.2], [147.5, 170.2, 17.5], [155.5, 172.0, 21.7], [164.6, 172.1, 24.4], [176.3, 168.9, 26.6], [189.6, 160.8, 28.8], [207.2, 144.1, 23.5], [219.0, 141.5, 26.1], [234.4, 133.7, 22.9], [247.1, 141.2, 25.6], [258.0, 147.1, 30.0], [270.8, 140.8, 32.3], [286.0, 120.5, 41.0], [307.2, 90.9, 37.7], [331.4, 87.5, 45.8], [358.4, 87.2, 46.7], [382.2, 81.0, 34.8], [402.0, 92.2, 38.3], [418.5, 98.0, 38.6], [441.5, 83.1, 44.6], [463.9, 55.5, 39.3], [483.6, 47.1, 38.5], [509.1, 36.2, 37.8], [528.0, 39.8, 39.8], [550.8, 41.3, 36.0], [590, 58, 30], [605, 98, 32], [608, 138, 30], [600, 176, 26], [560, 192.2, 24.6], [525.9, 192.8, 25.5], [496.2, 195.6, 16.8], [473.1, 194.4, 20.2], [447.6, 195.9, 23.0], [417.9, 194.0, 21.4], [394.2, 193.1, 21.9], [367.5, 196.8, 22.9], [345.1, 194.8, 19.9], [325.0, 193.6, 22.5], [304.3, 196.8, 20.2], [285.5, 197.9, 16.5], [269.2, 198.9, 17.1], [249.8, 195.4, 19.2], [226.9, 194.9, 17.6], [211.0, 196.8, 19.5], [189.5, 195.9, 16.3], [171.9, 197.2, 15.4], [157.3, 195.9, 21.0], [132.3, 190.8, 25.5], [103.9, 192.8, 23.9]], "top": 31, "hiFrom": 24, "hiTo": 31, "inner": [[220.6, 176.3, 17.8], [212.7, 167.2, 15.5], [233.9, 162.1, 14.9], [240.8, 170.4, 19.5], [261.3, 175.8, 23.4], [308.0, 161.4, 31.9], [299.5, 134.7, 29.5], [321.4, 129.5, 38.1], [367.3, 137.2, 38.6], [393.3, 113.7, 20.7], [373.3, 157.2, 20.9], [419.0, 131.3, 27.9], [392.4, 179.3, 25.9], [432.3, 149.0, 22.8], [434.1, 125.6, 30.3], [486.7, 110.5, 31.6], [477.9, 164.8, 27.3], [506.3, 84.5, 25.5], [489.4, 137.4, 28.4], [481.5, 183.8, 22.2], [521.4, 85.1, 29.6], [510.1, 140.2, 29.4], [526.6, 90.9, 30.1], [536.8, 153.0, 29.6], [566.4, 85.8, 24.8], [551.2, 131.8, 28.4], [566.8, 184.4, 27.8]]}
            }

            // ----- Montagne (cône, flanc gauche éclairé) -----
            GPoly {
                gx1: 1380; gx2: 1920; gy1: 0; gy2: 0
                c0: "#9a9bb2"; cm: "#7f89a6"; c1: "#6c7896"; pm: 0.55
                d: root.ground([1380,612, 1440,577, 1500,548, 1567,525, 1650,495, 1710,461, 1759,436, 1766,436, 1815,457, 1867,480, 1920,503], 760)
            }
            Poly { col: "#d6b7bf"; opacity: 0.5; d: "M1578 524 L1655 493 L1713 460 L1759 436 L1752 449 L1700 480 L1640 508 L1576 534 Z" }
            Poly { col: "#e9d4d8"; opacity: 0.55; d: "M1759 436 L1740 446 L1722 458 L1745 452 Z" }

            // ----- Reliefs lointains -----
            GPoly {
                gx1: 0; gy1: 550; gx2: 0; gy2: 640
                c0: "#9a93a8"; cm: "#8f8ea4"; c1: "#a39aaa"; pm: 0.5
                d: "M640 602 L697 592 L735 580 L772 570 L810 578 L847 581 L890 570 L937 566 L985 574 L1035 573 L1080 562 L1125 559 L1180 566 L1230 556 L1285 560 L1335 551 L1380 556 L1425 559 L1470 572 L1530 600 L1560 720 L640 720 Z"
            }
            Rectangle {
                x: 0; y: 520; width: 1920; height: 130
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00f4a58d" }
                    GradientStop { position: 0.55; color: "#5af4a58d" }
                    GradientStop { position: 1.0; color: "#00f4a58d" }
                }
            }
            // ----- Nuée d'étourneaux (passe en arrière-plan toutes les 30 s) -----
            // Le Canvas ne couvre plus tout le ciel (1920 x 620) mais une bande de 300 de haut qui suit
            // la nuée, calée au pixel entier près sur la grille de l'ancien Canvas : mêmes pixels,
            // au même endroit, mais on efface / dessine / envoie au GPU deux fois moins de pixels.
            // - Largeur gardée identique exprès : un Canvas plus petit passerait dans l'atlas de textures
            //   de Qt, ce qui décale d'un cheveu l'échantillonnage du blé (testé : 1/255 sur ~400 px).
            // - Si 620 x échelle n'est pas un entier (1440p, 16:10…), Qt arrondit et étire l'image de
            //   l'ancien Canvas d'une fraction de pixel ; impossible à reproduire au bit près avec une
            //   bande, donc on garde alors le Canvas plein ciel d'origine.
            Canvas {
                id: flock
                readonly property real fullH: 620 * root.rs
                readonly property bool strip: fullH === Math.round(fullH)
                readonly property real bh: 300
                x: 0
                y: strip ? oy / root.rs : 0
                width: 1920 * root.rs
                height: strip ? Math.ceil(bh * root.rs) : fullH
                transform: Scale { xScale: 1 / root.rs; yScale: 1 / root.rs }
                visible: root.flockT > 0 && root.flockT < 1
                property real t: root.flockT
                // centre vertical de la nuée (même formule que dans onPaint)
                readonly property int pass: root.flockPass
                function h1(i) { var v = Math.sin(i * 127.1 + pass * 311.7) * 43758.5453; return v - Math.floor(v); }
                readonly property real fcy: 300 + h1(1) * 120 + 55 * Math.sin(6.283185307 * (0.11 * t * 9 + h1(2)))
                // origine de la bande en pixels entiers de l'ancien Canvas, bornée à son cadre
                readonly property int oy: strip ? Math.max(0, Math.min(fullH - Math.ceil(bh * root.rs), Math.floor((fcy - bh / 2) * root.rs))) : 0
                onTChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    if (t <= 0 || t >= 1) return;
                    ctx.translate(0, -oy);
                    ctx.scale(root.rs, root.rs);
                    var pass = root.flockPass;
                    function h1(i) { var v = Math.sin(i * 127.1 + pass * 311.7) * 43758.5453; return v - Math.floor(v); }
                    var T = 6.283185307, tau = t * 9;
                    var dir = (pass % 2 === 0) ? 1 : -1;
                    var cx = dir > 0 ? -260 + t * 2440 : 2180 - t * 2440;
                    var cy = 300 + h1(1) * 120 + 55 * Math.sin(T * (0.11 * tau + h1(2)));
                    var rx = 85 + 45 * Math.sin(T * (0.13 * tau + h1(3)));
                    var ry = 26 + 14 * Math.sin(T * (0.19 * tau + h1(4)));
                    var rot = 0.45 * Math.sin(T * (0.09 * tau + h1(5)));
                    var cr = Math.cos(rot), sr = Math.sin(rot);
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    ctx.strokeStyle = "#1c1826";
                    for (var i = 0; i < 90; i++) {
                        var a = h1(i + 10) * T, r = Math.sqrt(h1(i + 200));
                        var ux = r * Math.cos(a), uy = r * Math.sin(a);
                        var fx = 30 * Math.sin(3.1 * uy + 0.9 * tau + h1(6) * T);
                        var fy = 20 * Math.sin(2.7 * ux + 1.3 * tau + h1(7) * T);
                        var wx = 5 * Math.sin(tau * (1.5 + h1(i + 300)) + h1(i + 400) * T);
                        var wy = 4 * Math.sin(tau * (1.7 + h1(i + 500)) + h1(i + 600) * T);
                        var lx = ux * rx + fx + wx, ly = uy * ry + fy + wy;
                        var px = cx + lx * cr - ly * sr, py = cy + lx * sr + ly * cr;
                        var z = 0.6 + 0.5 * h1(i + 700), sz = 2.6 * z;
                        var flap = Math.sin(tau * T * (3.6 + 1.2 * h1(i + 800)) + h1(i + 900) * T);
                        ctx.globalAlpha = 0.55 + 0.4 * z;
                        ctx.lineWidth = 0.9 + 0.5 * z;
                        ctx.beginPath();
                        ctx.moveTo(px - sz, py - sz * 0.55 * flap);
                        ctx.quadraticCurveTo(px - sz * 0.4, py - sz * 0.15 * flap - 0.4, px, py);
                        ctx.quadraticCurveTo(px + sz * 0.4, py - sz * 0.15 * flap - 0.4, px + sz, py - sz * 0.55 * flap);
                        ctx.stroke();
                    }
                }
            }

            // Colline pâle du fond + arbres nus
            GPoly {
                gy1: 593; gy2: 780
                c0: "#d9a49a"; cm: "#c69a9a"; c1: "#ae8f98"; pm: 0.45
                d: root.ground(root.ridgeFar, 800)
            }
            Poly { col: "#f2b8a6"; opacity: 0.45; d: root.rim(root.ridgeFar, 10) }
            // flanc droit dans l'ombre (lumière venant de gauche)
            GPoly {
                gx1: 1470; gy1: 0; gx2: 1790; gy2: 0
                c0: "#00988aa0"; cm: "#50988aa0"; c1: "#90988aa0"; pm: 0.5
                d: root.ground(root.ridgeFar, 780)
            }
            HillStrokes { ridge: root.ridgeFar; xMin: 800; xMax: 1790; dMin: 6; dMax: 160; count: 90; seed: 4
                          cols: ["#f4c2b2", "#a07c8c"]; aMin: 0.05; aMax: 0.12; wMin: 0.8; wMax: 1.6; lenMin: 30; lenMax: 110 }
            // petit village sur la crête lointaine : maisons, clocher, arbres
            Poly { col: "#8f6f80"; d: "M1418 597 L1418 591 L1422 588 L1426 591 L1426 597 Z" }
            Poly { col: "#9a7785"; d: "M1426 597 L1426 592 L1434 592 L1434 597 Z" }
            Poly { col: "#8a6a7c"; d: "M1436 597 L1436 586 L1438 581 L1440 586 L1440 597 Z" }
            Poly { col: "#9a7785"; d: "M1440 597 L1440 590 L1445 587 L1450 590 L1450 597 Z" }
            Poly { col: "#a07c88"; d: "M1405 598 L1405 594 L1411 594 L1411 598 Z" }
            Poly { col: "#f4c6b0"; opacity: 0.55; d: "M1418 591 L1422 588 L1423 589 L1419 592 Z M1440 590 L1445 587 L1446 588 L1441 591 Z" }
            BareTrees { bx: 1440; by: 570; bw: 50; bh: 32; col: "#a98490"; crown: "#b48a92"; crownAlpha: 0.5
                        trees: [[1452,596,9,1], [1462,597,7,2], [1471,596,10,3]] }
            // arbres nus au fond, dans le creux entre les collines
            BareTrees { bx: 1210; by: 700; bw: 160; bh: 60; col: "#94707e"; crown: "#a87e88"; crownAlpha: 0.25
                        trees: [[1238,752,20,11], [1252,748,26,12], [1270,750,18,13], [1300,746,24,14], [1322,749,16,15], [1345,752,20,16]] }

            // Colline droite du fond (derrière la colline sombre)
            GPoly {
                gy1: 603; gy2: 960
                c0: "#f8865f"; cm: "#e46c5a"; c1: "#9a4c5a"; pm: 0.4
                d: root.ground(root.ridgeR1, 1000)
            }
            Poly { col: "#ffb48a"; opacity: 0.35; d: root.rim(root.ridgeR1, 8) }
            Poly { col: "#ffb48a"; opacity: 0.15; d: root.rim(root.ridgeR1, 22) }
            HillStrokes { ridge: root.ridgeR1; xMin: 1180; xMax: 1920; dMin: 8; dMax: 210; count: 150; seed: 6
                          cols: ["#ffc6a6", "#c95f58", "#e2786a"]; aMin: 0.06; aMax: 0.15; wMin: 1; wMax: 2.2 }
            WindWave { ridge: root.ridgeR1; x0: 1560; travel: 240; depth: 30; len: 150; delay: 4200; dur: 4400; rest: 11000 }
            WindWave { ridge: root.ridgeR1; x0: 1700; travel: 180; depth: 62; len: 120; delay: 9000; dur: 4000; rest: 9500 }

            // Colline sombre du moulin (plateau plat au sommet)
            GPoly {
                gx1: 400; gy1: 574; gx2: 1500; gy2: 840
                c0: "#26364f"; cm: "#363b57"; c1: "#45455d"; pm: 0.5
                d: root.ground(root.ridgeHill, 960)
            }
            HillStrokes { ridge: root.ridgeHill; xMin: -20; xMax: 1520; dMin: 8; dMax: 260; count: 210; seed: 7
                          cols: ["#56628a", "#1a2338", "#7a6f8e"]; aMin: 0.05; aMax: 0.13; wMin: 1; wMax: 2.4; lenMin: 40; lenMax: 140 }
            WindWave { ridge: root.ridgeHill; x0: 640; travel: 280; depth: 40; len: 170; col: "#8e88b0"; peak: 0.32; delay: 2500; dur: 5000; rest: 10000 }
            WindWave { ridge: root.ridgeHill; x0: 880; travel: 220; depth: 80; len: 140; col: "#8e88b0"; peak: 0.3; delay: 8000; dur: 4500; rest: 12000 }
            // lumière rasante sur le flanc gauche + herbe sèche
            Poly { col: "#c27c52"; opacity: 0.4; d: root.rim([232,634, 300,612, 340,586, 362,576], 6) }
            RidgeTufts {
                pts: [200,626, 232,634, 300,612, 340,586, 362,576, 380,574, 470,574, 610,574, 640,578, 700,587, 770,609]
                count: 170; hMin: 5; hMax: 17; dropMax: 3; seed: 5
                c0: "#5c3a3a"; c1: "#d89a68"
            }

            // ----- Moulin : tonneau arrondi, dôme sous le moyeu -----
            GPoly {
                gx1: 414; gx2: 578; gy1: 0; gy2: 0
                c0: "#2c3b59"; cm: "#23314c"; c1: "#1c2841"; pm: 0.45
                d: root.spline([414,571, 433,470, 445,384, 448,338, 455,314, 486,301, 508,304, 523,317, 531,338, 551,384, 565,470, 578,571]) + " L579 578 L413 578 Z"
            }
            // liseré orangé sur le dôme
            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"; strokeColor: "#e98a60"; strokeWidth: 2; capStyle: ShapePath.RoundCap
                    PathSvg { path: "M486 301 C494.83 299.33 501.83 301.33 508 304 C514.17 306.67 519.17 311.33 523 317 C526.83 322.67 526.33 326.83 531 338 C535.67 349.17 545.33 362 551 384" }
                }
            }
            // face éclairée à gauche (dégradé vers le bas)
            GPoly {
                gy1: 384; gy2: 571
                c0: "#00f4a276"; cm: "#a0f4a276"; c1: "#f2f4a276"; pm: 0.5
                d: "M445 384 C440 420 436 450 433 470 C427 508 421 540 414 571 L413 578 L441 578 L441 571 C441 530 444 500 447 470 C450 440 452 410 453 388 Z"
            }
            // ceinture
            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"; strokeColor: "#f0956a"; strokeWidth: 2.6
                    PathSvg { path: "M445 384 Q498 389 551 384" }
                }
            }
            // fenêtres
            Rectangle { x: 463; y: 395; width: 10; height: 15; radius: 1.5; color: "#cdbcc2"; opacity: 0.9
                Rectangle { x: 4.5; y: 0; width: 1; height: 15; color: "#3a4560" } Rectangle { x: 0; y: 7; width: 10; height: 1; color: "#3a4560" } }
            Rectangle { x: 458; y: 442; width: 12; height: 17; radius: 1.5; color: "#cdbcc2"; opacity: 0.9
                Rectangle { x: 5.5; y: 0; width: 1; height: 17; color: "#3a4560" } Rectangle { x: 0; y: 8; width: 12; height: 1; color: "#3a4560" } }
            // porte
            Rectangle { x: 454; y: 502; width: 22; height: 76; color: "#fb4248" }
            Rectangle { x: 454; y: 502; width: 22; height: 3; color: "#ff7a6e" }
            // pied du moulin caché derrière le rebord du plateau : même courbe exacte que la crête
            // (segment de la spline entre 380 et 610) et même dégradé que la colline, limité à la
            // largeur du moulin. Dessiné avant l'escalier et le garde-corps, qui restent intacts.
            Item {
                x: 413; y: 560; width: 166; height: 24
                clip: true
                GPoly {
                    x: -413; y: -560
                    gx1: 400; gy1: 574; gx2: 1500; gy2: 840
                    c0: "#26364f"; cm: "#363b57"; c1: "#45455d"; pm: 0.5
                    // = segment 380 -> 610 de root.spline(ridgeHill), points de contrôle recopiés
                    d: "M380 574 C421.3333 573.6667 566.6667 573.3333 610 574 L610 584 L380 584 Z"
                }
            }

            // ----- Escalier : part du plateau et descend derrière la dune de gauche -----
            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "#3a4a6c"; strokeColor: "transparent"; strokeWidth: -1
                    PathSvg { path: "M446 576 L472 576 L346 712 L292 702 Z" }
                }
                ShapePath {
                    fillColor: "transparent"; strokeColor: "#1e293f"; strokeWidth: 1.3
                    PathSvg { path: {
                        var d = "";
                        for (var i = 1; i < 20; i++) {
                            var t = i / 20;
                            var lx = 446 + (292 - 446) * t, ly = 576 + (702 - 576) * t;
                            var rx = 472 + (346 - 472) * t, ry = 576 + (712 - 576) * t;
                            d += "M" + lx + " " + ly + " L" + rx + " " + ry + " ";
                        }
                        return d;
                    } }
                }
                ShapePath {
                    fillColor: "transparent"; strokeColor: "#1e293f"; strokeWidth: 1.6
                    PathSvg { path: "M446 568 L292 692 M472 568 L346 702" }
                }
            }

            // ----- Garde-corps bas, posé sur le plateau, ouvert au niveau de l'escalier -----
            Rectangle { x: 384; y: 556; width: 61; height: 2.2; color: "#1f2a42" }
            Rectangle { x: 473; y: 556; width: 128; height: 2.2; color: "#1f2a42" }
            Rectangle { x: 384; y: 566; width: 61; height: 1.6; color: "#1f2a42" }
            Rectangle { x: 473; y: 566; width: 128; height: 1.6; color: "#1f2a42" }
            Repeater {
                model: [384, 396, 408, 420, 432, 443.2, 473, 485, 497, 509, 521, 533, 545, 557, 569, 581, 593, 599.2]
                Rectangle { required property real modelData
                    x: modelData; y: 555; width: 1.8; height: 21; color: "#1f2a42" }
            }

            // ----- Moyeu + pales (qui tournent) : le moyeu repose sur le dôme -----
            Item {
                x: 480; y: 308
                rotation: root.bladeAngle
                Blade { rotation: -52; len: 214; seed: 11; damage: 0.28 }
                Blade { rotation: 38;  len: 209; seed: 23; damage: 0.6 }
                Blade { rotation: 128; len: 218; seed: 37; damage: 0.4 }
                Blade { rotation: 218; len: 212; seed: 52; damage: 0.78 }
            }
            Rectangle { x: 462; y: 290; width: 36; height: 36; radius: 18; color: "#1d2a45" }
            Rectangle { x: 468; y: 296; width: 24; height: 24; radius: 12; color: "#2b3a59" }
            Rectangle { x: 474; y: 301; width: 9; height: 7; radius: 3.5; color: "#5a6a8c"; opacity: 0.7 }

            // ----- Colline de gauche (premier plan) -----
            GPoly {
                gx1: 232; gy1: 640; gx2: 1100; gy2: 1100
                c0: "#f8925f"; cm: "#d4584f"; c1: "#2e2238"; pm: 0.48
                d: root.ground(root.ridgeLeft, 1100)
            }
            Poly { col: "#fcb090"; opacity: 0.14; d: root.rim(root.ridgeLeft, 14) }
            // ombre douce côté route
            GPoly {
                gx1: 760; gx2: 1400; gy1: 0; gy2: 0
                c0: "#00a04050"; cm: "#18a04050"; c1: "#40803048"; pm: 0.5
                d: root.ground(root.ridgeLeft, 1100)
            }
            HillStrokes { ridge: root.ridgeLeft; xMin: -20; xMax: 1400; dMin: 8; dMax: 330; count: 280; seed: 8
                          cols: ["#ffc4a2", "#c4554f", "#a8455a"]; aMin: 0.05; aMax: 0.14; wMin: 1; wMax: 2.6; lenMin: 40; lenMax: 160 }
            WindWave { ridge: root.ridgeLeft; x0: 30;  travel: 270; depth: 48;  len: 180; delay: 0;     dur: 4800; rest: 9000 }
            WindWave { ridge: root.ridgeLeft; x0: 250; travel: 240; depth: 105; len: 160; delay: 3600;  dur: 4400; rest: 11500 }
            WindWave { ridge: root.ridgeLeft; x0: 520; travel: 200; depth: 42;  len: 130; delay: 7200;  dur: 4000; rest: 8500 }
            WindWave { ridge: root.ridgeLeft; x0: 120; travel: 300; depth: 160; len: 200; delay: 11000; dur: 5200; rest: 9000 }
            RidgeTufts {
                pts: [450,690, 560,735, 700,780, 825,813, 920,836, 1000,848, 1120,854, 1250,856, 1340,860]
                count: 260; hMin: 6; hMax: 22; dropMax: 6; seed: 9
                c0: "#5a2f40"; c1: "#e0804f"
            }

            // ----- Petit chemin sombre (tracé de la photo) : part du bas, tourne et passe derrière la colline -----
            GPoly {
                gy1: 856; gy2: 1130
                c0: "#3a4560"; cm: "#2b3550"; c1: "#232b40"; pm: 0.35
                d: "M1384 856 L1357.5 859.5 L1320 866 L1275 877.5 L1230 892.5 L1185 911 L1140 937.5 L1102.5 967.5 L1080 997.5 L1040 1040 L995 1085 L950 1130 L1254 1130 L1262 1085 L1270 1040 L1275 997.5 L1275 967.5 L1276.5 937.5 L1284 915 L1301 896 L1324 881 L1350 870 L1376 861 L1391 856.5 Z"
            }
            GPoly {
                gy1: 856; gy2: 940
                c0: "#50e8a088"; cm: "#14e8a088"; c1: "#00e8a088"; pm: 0.5
                d: "M1384 856 L1357.5 859.5 L1320 866 L1275 877.5 L1230 892.5 L1185 911 L1140 937.5 L1102.5 967.5 L1080 997.5 L1040 1040 L995 1085 L950 1130 L1254 1130 L1262 1085 L1270 1040 L1275 997.5 L1275 967.5 L1276.5 937.5 L1284 915 L1301 896 L1324 881 L1350 870 L1376 861 L1391 856.5 Z"
            }
            Poly { col: "#151a2a"; opacity: 0.45; d: "M1384 856 L1357.5 859.5 L1320 866 L1275 877.5 L1230 892.5 L1185 911 L1140 937.5 L1102.5 967.5 L1080 997.5 L1040 1040 L995 1085 L950 1130 L983.6 1130 L1023.2 1085 L1062.8 1040 L1097.7 997.5 L1116.6 967.5 L1150.5 937.5 L1192.3 911 L1235.1 892.5 L1278.3 877.5 L1321.9 866 L1359.0 859.5 L1385.5 856 Z" }
            // herbes du talus de gauche, éclairées, qui débordent sur le chemin
            RidgeTufts {
                pts: [1384,  856,  1357.5,  859.5,  1320,  866,  1275,  877.5,  1230,  892.5,  1185,  911,  1140,  937.5,  1102.5,  967.5,  1080,  997.5,  1040,  1040,  995,  1085,  950,  1130]
                count: 240; hMin: 0.3; hMax: 0.95; dropMax: 4; seed: 14
                hs: function(y) { return root.wheatPx(y); }
                c0: "#5a2f40"; c1: "#f0a070"
            }

            // poteau lointain : son pied passe derrière l'épaule de la colline, seule la tête dépasse
            Pole { bx: root.poles[1][0]; by: root.poles[1][1]; ty: root.poles[1][2]; ppm: root.poles[1][3] }
            Pole { bx: root.poles[2][0]; by: root.poles[2][1]; ty: root.poles[2][2]; ppm: root.poles[2][3] }
            // arbres au bout de la route, derrière la crête
            BareTrees { bx: 1370; by: 760; bw: 160; bh: 105; col: "#3c3046"; crown: "#6a4a58"; crownAlpha: 0.2
                        trees: [[1400,858,46,21], [1418,853,34,22], [1440,847,54,23], [1478,839,30,24], [1502,834,40,25]] }

            // ----- Colline de droite (premier plan) : son pied borde le chemin -----
            GPoly {
                gy1: 735; gy2: 1100
                c0: "#f6825c"; cm: "#ea6450"; c1: "#5a2c40"; pm: 0.5
                d: root.ground(root.ridgeR2, 1130)
            }
            Poly { col: "#fcb48f"; opacity: 0.28; d: root.rim(root.ridgeR2.slice(20), 12) }
            Poly { col: "#fcb48f"; opacity: 0.18; d: root.rim(root.ridgeR2.slice(20), 30) }
            // flanc gauche de la colline dans l'ombre (côté chemin)
            GPoly {
                gx1: 1250; gx2: 1600; gy1: 0; gy2: 0
                c0: "#c0802438"; cm: "#50802438"; c1: "#00802438"; pm: 0.45
                d: root.ground(root.ridgeR2, 1130)
            }
            HillStrokes { ridge: root.ridgeR2; xMin: 1255; xMax: 1920; dMin: 8; dMax: 300; count: 240; seed: 9
                          cols: ["#ffc2a0", "#c8564e", "#a8455a"]; aMin: 0.05; aMax: 0.14; wMin: 1; wMax: 2.6; lenMin: 40; lenMax: 150 }
            WindWave { ridge: root.ridgeR2; x0: 1560; travel: 240; depth: 30; len: 150; delay: 1500; dur: 4600; rest: 10000 }
            WindWave { ridge: root.ridgeR2; x0: 1660; travel: 200; depth: 62; len: 120; delay: 6000; dur: 4200; rest: 9000 }
            RidgeTufts {
                pts: [1385,855, 1450,836, 1525,817, 1625,800, 1725,775, 1825,755, 1920,735]
                count: 300; hMin: 8; hMax: 28; dropMax: 5; seed: 21
                c0: "#6a3a3a"; c1: "#e3a878"
            }
            // arbustes et petits arbres nus le long de la crête, comme sur la photo
            BareTrees { bx: 1380; by: 690; bw: 560; bh: 175; col: "#7a4a50"; crown: "#b06a5e"; crownAlpha: 0.22; baseFade: 0.55
                        trees: [[1402,852,16,31], [1446,840,11,32], [1530,818,22,33], [1600,805,13,34], [1652,795,19,35],
                                [1700,783,12,36], [1745,772,24,37], [1800,760,14,38], [1846,750,20,39], [1898,739,15,40]] }
            // herbes hautes au pied de la colline, le long du chemin
            RidgeTufts {
                pts: [1391,  856.5,  1376,  861,  1350,  870,  1324,  881,  1301,  896,  1284,  915,  1276.5,  937.5,  1275,  967.5,  1275,  997.5,  1270,  1040,  1262,  1085,  1254,  1130]
                count: 220; hMin: 0.3; hMax: 0.85; dropMax: 4; seed: 33
                hs: function(y) { return root.wheatPx(y); }
                c0: "#2a2234"; c1: "#e3805a"
            }

            // ----- Poteau proche et fils qui arrivent de derrière la caméra (flèche + balancement au vent) -----
            Pole { bx: root.poles[0][0]; by: root.poles[0][1]; ty: root.poles[0][2]; ppm: root.poles[0][3] }
            // ----- Blé : 7 plans, taille réglée par la perspective (petit au loin, grand devant) -----
            GrassLayer { baseY: 868;  waveAmp: 8;  carpetDepth: 8;  spacing: 1.5; wMin: 0.7; wMax: 1.2; jitter: 8;  amp: 0.03;  earProb: 0.03; seed: 11; fade: 0.78
                windP: root.wheatP; skip: root.wheatSkip; c0: "#7a3442"; c1: "#c94c4a"; tips: ["#ec7650", "#f28a5e", "#f39a6a"] }
            GrassLayer { baseY: 895;  waveAmp: 10; carpetDepth: 12; spacing: 1.5; wMin: 0.8; wMax: 1.4; jitter: 10; amp: 0.035; earProb: 0.06; seed: 12; fade: 0.62
                windP: root.wheatP; skip: root.wheatSkip; c0: "#6e3040"; c1: "#c44a4a"; tips: ["#ea6c4c", "#f07e56", "#f39468"] }
            GrassLayer { baseY: 930;  waveAmp: 12; carpetDepth: 18; spacing: 1.6; wMin: 1.0; wMax: 1.7; jitter: 12; amp: 0.045; earProb: 0.12; seed: 13; fade: 0.45
                windP: root.wheatP; skip: root.wheatSkip; c0: "#5c2a3c"; c1: "#b84448"; tips: ["#e8644a", "#f07a54", "#e0584a", "#f39468"] }
            GrassLayer { baseY: 972;  waveAmp: 14; carpetDepth: 32; spacing: 1.6; wMin: 1.2; wMax: 2.1; jitter: 14; amp: 0.055; earProb: 0.2;  seed: 14; fade: 0.28
                windP: root.wheatP; skip: root.wheatSkip; c0: "#3e2638"; c1: "#9a3c48"; tips: ["#e45a46", "#f07850", "#f28c5e", "#d8524a"] }
            GrassLayer { baseY: 1020; waveAmp: 16; carpetDepth: 40; spacing: 2.0; wMin: 1.5; wMax: 2.6; jitter: 16; amp: 0.07;  earProb: 0.28; seed: 15; fade: 0.12
                windP: root.wheatP; skip: root.wheatSkip; c0: "#2a2234"; c1: "#7a3446"; tips: ["#e05644", "#ee7450", "#c8484a", "#f08a5c"] }
            GrassLayer { baseY: 1072; waveAmp: 18; carpetDepth: 45; spacing: 2.6; wMin: 1.9; wMax: 3.3; jitter: 18; amp: 0.09;  earProb: 0.32; seed: 16
                windP: root.wheatP; skip: root.wheatSkip; c0: "#1f2233"; c1: "#4e2c44"; tips: ["#d64e42", "#ec7050", "#b24048", "#f0865a"] }
            GrassLayer { baseY: 1125; waveAmp: 20; carpetDepth: 0;  spacing: 3.2; wMin: 2.4; wMax: 4.0; jitter: 20; amp: 0.11;  earProb: 0.32; seed: 17
                windP: root.wheatP; skip: root.wheatSkip; c0: "#1a1d2c"; c1: "#3a2840"; tips: ["#c84840", "#e6684a", "#8a3446", "#f0865a"] }

            // ----- Poteau au premier plan (bord droit, coupé par le cadre) : le câble en sort -----
            Pole { bx: 1828; by: 1200; ty: 360; ppm: 140 }
            Shape {
                id: wires
                preferredRendererType: Shape.CurveRenderer
                // poteaux en 3D (mètres) : [X, sol Y, Z] — derrière la caméra, proche, lointain
                readonly property var pZ: [9.0, 2.0, -10.0]
                readonly property var pA: [6.2, -2.343, 5.0]
                readonly property var pB: [8.129, -4.782, 16.166]
                readonly property var pC: [30.71, -10.003, 38.251]
                readonly property var pD: [80.2, -16.3, 70.0]
                // Tout ce qui ne dépend pas du temps est calculé une seule fois (points de la chaînette,
                // pas géométrique, flèche) ; à chaque image il ne reste que sin/cos de l'angle.
                // Mêmes opérations dans le même ordre que l'original => mêmes nombres, au bit près.
                function prep(P, Q, side, ph, geo) {
                    var xa = P[0] + side * 0.3, ya = P[1] + 5.8, za = P[2];
                    var xb = Q[0] + side * 0.3, yb = Q[1] + 5.8, zb = Q[2];
                    var dx = xb - xa, dz = zb - za, span = Math.sqrt(dx * dx + dz * dz);
                    var sag = 0.055 * span;
                    var nx = dz / span, nz = -dx / span, N = 90;
                    var A = [], B = [], C = [], S = [], KX = [], KZ = [];
                    for (var i = 0; i <= N; i++) {
                        var t;
                        if (geo) { var zz = 0.6 * Math.pow(zb / 0.6, i / N); t = (zz - za) / dz; }
                        else t = i / N;
                        var sg = 4 * sag * t * (1 - t);
                        A.push(xa + dx * t); C.push(za + dz * t); B.push(ya + (yb - ya) * t);
                        KX.push(nx * sg); KZ.push(nz * sg); S.push(sg);
                    }
                    return { A: A, B: B, C: C, S: S, KX: KX, KZ: KZ, n: N + 1, ph: ph };
                }
                readonly property var pre: [prep(pZ, pA, -1, 0.0, true), prep(pA, pB, -1, 0.6, false),
                                            prep(pB, pC, -1, 1.1, false), prep(pC, pD, -1, 2.0, false)]
                function wire(w, p) {
                    var T = 6.283185307, ph = w.ph;
                    var th = 0.15 * Math.sin(T * 37 * p + ph) + 0.06 * Math.sin(T * 89 * p + ph * 1.7);
                    var st = Math.sin(th), ct = Math.cos(th);
                    var A = w.A, B = w.B, C = w.C, S = w.S, KX = w.KX, KZ = w.KZ, n = w.n, out = [];
                    for (var i = 0; i < n; i++) {
                        var Z = C[i] + KZ[i] * st;
                        if (Z < 0.6) continue;
                        var X = A[i] + KX[i] * st;
                        var Y = B[i] - S[i] * ct;
                        var qx = 960 + 700 * X / Z, qy = 620 + 700 * (1.8 - Y) / Z;
                        if (qx < -2500 || qx > 4500 || qy < -2500 || qy > 3000) continue;
                        // arrondi au dixième, comme toFixed(1), sans passer par une chaîne par coordonnée
                        out.push(Math.round(qx * 10) / 10, Math.round(qy * 10) / 10);
                    }
                    // "M x y x y ..." : en SVG les paires qui suivent un M sont des L implicites
                    return out.length ? "M" + out.join(" ") : "M0 0";
                }
                ShapePath { fillColor: "transparent"; strokeColor: "#e02a2233"; strokeWidth: 2.2; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: wires.wire(wires.pre[0], root.cableP) + " " + wires.wire(wires.pre[1], root.cableP) } }
                ShapePath { fillColor: "transparent"; strokeColor: "#d02a2233"; strokeWidth: 1.2; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: wires.wire(wires.pre[2], root.cableP) } }
                ShapePath { fillColor: "transparent"; strokeColor: "#b82a2233"; strokeWidth: 0.9; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: wires.wire(wires.pre[3], root.cableP) } }
            }

        }

        // ----- Grain fin sur toute l'image (texture) -----
        Image {
            anchors.fill: parent
            source: Qt.resolvedUrl("../images/grain.png")
            fillMode: Image.Tile
            smooth: false
            opacity: 0.5
        }
    }
}
