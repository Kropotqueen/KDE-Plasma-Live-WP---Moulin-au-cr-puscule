import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Page de réglages du fond d'écran (Paramètres du fond d'écran > Moulin au crépuscule)
Kirigami.FormLayout {
    id: page

    property real cfg_SpeedMill
    property real cfg_SpeedClouds
    property real cfg_SpeedBirds
    property real cfg_SpeedWheat
    property real cfg_SpeedCable
    property real cfg_SpeedWind
    property real cfg_SpeedMillDefault: 1
    property real cfg_SpeedCloudsDefault: 1
    property real cfg_SpeedBirdsDefault: 1
    property real cfg_SpeedWheatDefault: 1
    property real cfg_SpeedCableDefault: 1
    property real cfg_SpeedWindDefault: 1
    property bool cfg_PauseWhenCovered
    property bool cfg_PauseWhenCoveredDefault: true
    property int cfg_MaxFps
    property int cfg_MaxFpsDefault: 0

    // Une ligne : curseur 0 → 3 (0 = arrêt), valeur affichée, bouton de remise à 1
    component SpeedRow: RowLayout {
        id: row
        property real value: 1
        signal edited(real v)
        spacing: Kirigami.Units.smallSpacing
        QQC2.Slider {
            id: sl
            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
            from: 0; to: 3; stepSize: 0.05
            value: row.value
            onMoved: row.edited(Math.round(value * 100) / 100)
        }
        QQC2.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            text: row.value <= 0 ? "arrêt" : "×" + row.value.toFixed(2)
            opacity: 0.8
        }
        QQC2.ToolButton {
            icon.name: "edit-undo"
            display: QQC2.AbstractButton.IconOnly
            text: "Vitesse normale"
            enabled: Math.abs(row.value - 1) > 0.001
            onClicked: row.edited(1)
            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
        }
    }

    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Vitesses d'animation" }

    SpeedRow { Kirigami.FormData.label: "Pales du moulin :"; value: page.cfg_SpeedMill;   onEdited: v => page.cfg_SpeedMill = v }
    SpeedRow { Kirigami.FormData.label: "Nuages :";          value: page.cfg_SpeedClouds; onEdited: v => page.cfg_SpeedClouds = v }
    SpeedRow { Kirigami.FormData.label: "Oiseaux :";         value: page.cfg_SpeedBirds;  onEdited: v => page.cfg_SpeedBirds = v }
    SpeedRow { Kirigami.FormData.label: "Blé :";             value: page.cfg_SpeedWheat;  onEdited: v => page.cfg_SpeedWheat = v }
    SpeedRow { Kirigami.FormData.label: "Câble :";           value: page.cfg_SpeedCable;  onEdited: v => page.cfg_SpeedCable = v }
    SpeedRow { Kirigami.FormData.label: "Vagues de vent :";  value: page.cfg_SpeedWind;   onEdited: v => page.cfg_SpeedWind = v }

    QQC2.Button {
        Kirigami.FormData.label: " "
        text: "Tout remettre à la vitesse normale"
        icon.name: "view-refresh"
        onClicked: {
            page.cfg_SpeedMill = 1; page.cfg_SpeedClouds = 1; page.cfg_SpeedBirds = 1;
            page.cfg_SpeedWheat = 1; page.cfg_SpeedCable = 1; page.cfg_SpeedWind = 1;
        }
    }
    QQC2.Label {
        Kirigami.FormData.label: " "
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "0 = arrêt, 1 = normal, 3 = trois fois plus vite. Les changements s'appliquent avec « Appliquer »."
    }

    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Économie d'énergie" }

    QQC2.CheckBox {
        Kirigami.FormData.label: "Pause :"
        text: "quand une fenêtre maximisée ou plein écran couvre le bureau"
        checked: page.cfg_PauseWhenCovered
        onToggled: page.cfg_PauseWhenCovered = checked
    }
    RowLayout {
        Kirigami.FormData.label: "Images par seconde max :"
        spacing: Kirigami.Units.smallSpacing
        QQC2.SpinBox {
            from: 0; to: 240; stepSize: 5
            value: page.cfg_MaxFps
            onValueModified: page.cfg_MaxFps = value
            textFromValue: function(v) { return v <= 0 ? "écran" : v + " i/s"; }
        }
    }
    QQC2.Label {
        Kirigami.FormData.label: " "
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "« écran » = rendu à chaque rafraîchissement, comme à l'origine. 30 divise environ par deux le travail sur un écran 60 Hz ; seule la nuée d'oiseaux paraît un peu moins fluide."
    }
}
