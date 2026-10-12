import QtQuick
import QtQuick.Window
import org.kde.taskmanager as TaskManager

// covered = vrai quand une fenêtre maximisée ou plein écran, non minimisée, occupe l'écran
// de ce fond d'écran sur le bureau virtuel et l'activité courants.
// Chargé par un Loader : si ce module n'est pas disponible, rien ne se met en pause.
Item {
    id: watch
    property bool covered: false

    TaskManager.VirtualDesktopInfo { id: vdInfo }
    TaskManager.ActivityInfo { id: actInfo }

    TaskManager.TasksModel {
        id: tasks
        sortMode: TaskManager.TasksModel.SortDisabled
        groupMode: TaskManager.TasksModel.GroupDisabled
        virtualDesktop: vdInfo.currentDesktop
        activity: actInfo.currentActivity
        screenGeometry: Qt.rect(watch.Screen.virtualX, watch.Screen.virtualY, watch.Screen.width, watch.Screen.height)
        filterByVirtualDesktop: true
        filterByActivity: true
        filterByScreen: true
        filterMinimized: true
    }

    Instantiator {
        id: inst
        model: tasks
        delegate: QtObject {
            // rôles du modèle lus via "model." (un nom de propriété ne peut pas commencer par une majuscule)
            readonly property bool hides: model.IsMaximized === true || model.IsFullScreen === true
            onHidesChanged: recheck.restart()
        }
        onObjectAdded: recheck.restart()
        onObjectRemoved: recheck.restart()
    }

    // petit délai : évite de basculer pendant les animations d'ouverture / de restauration
    Timer {
        id: recheck
        interval: 250
        onTriggered: {
            var c = false;
            for (var i = 0; i < inst.count; i++) {
                var o = inst.objectAt(i);
                if (o && o.hides) { c = true; break; }
            }
            watch.covered = c;
        }
    }
}
