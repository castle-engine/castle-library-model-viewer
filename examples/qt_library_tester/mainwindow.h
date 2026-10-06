#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QAction>
#include <QHash>
#include <QMdiArea>
#include <QMdiSubWindow>

class GLWidget;
class QSurfaceFormat;

namespace Ui {
class MainWindow;
}

class NavKeeper
{
private:
    float fPosX, fPosY, fPosZ, fDirX, fDirY, fDirZ, fUpX, fUpY, fUpZ, fGravX, fGravY, fGravZ;
    int eNavType;
    bool bToBeApplied;

public:
    NavKeeper();
    void SaveState(int iCgeContext);
    bool ApplyState(int iCgeContext);
};

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = 0);
    ~MainWindow();

    GLWidget *ActiveGlWidget() const;
    void OpenSceneInNewWindow(QString const& sFilename);
    void UpdateNavigationButtons();
    void UpdateAfterSceneLoaded();
    void MoveToViewpoint(int nView);
    void AddNewWarning(QString const& sWarning);
    void SaveSettings();
    static void SetSurfaceFormat(QSurfaceFormat *pFormat);

private:
    Ui::MainWindow *ui;
    QMdiArea *m_pMdiArea;
    QWidget *m_pWindowContainer;
    QHash<QMdiSubWindow *, GLWidget *> m_sceneWindows;
    QDialog *m_pConsoleWnd;
    int m_nViewpointCount, m_iCurrentViewpoint;
    NavKeeper m_aNavKeeper;
    QString m_sLastUsedFolder;

private slots:
    void OnFileOpenClick();
    void OnMdiSubWindowActivated(QMdiSubWindow *pSubWindow);
    void OnWalkClick();
    void OnFlyClick();
    void OnExamineClick();
    void OnTurntableClick();
    void OnMoveToViewpointClick();
    void OnNextViewClick();
    void OnPrevViewClick();
    void MenuSoftShadowsClick();
    void MenuAntiAliasingClick();
    void MenuWalkingEffectClick();
    void MenuMouseLookClick();
    void MenuShowWarningClick();
    void MenuOpenGLInfoClick();
    void on_actionHeadlight_triggered();
    void on_actionSave_Screenshot_triggered();
};

class ActionWithTag : public QAction
{
    Q_OBJECT
public:
    int m_nTag;

    explicit ActionWithTag(QString const& sCaption, int nTag, QObject * parent);
};

#endif // MAINWINDOW_H
