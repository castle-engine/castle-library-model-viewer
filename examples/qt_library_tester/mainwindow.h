#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QAction>
#include <QMdiArea>
#include <QMdiSubWindow>
#include <QMenu>
#include <QToolBar>
#include <QToolButton>
#include <QVBoxLayout>

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

    static MainWindow *Instance();
    static GLWidget *GlWidgetFromMdiSubWindow(QMdiSubWindow *pSubWindow);
    GLWidget *ActiveGlWidget() const;
    void OpenSceneInNewWindow(QString const& sFilename);
    void AddNewWarning(QString const& sWarning);
    void SaveSettings();
    static void SetSurfaceFormat(QSurfaceFormat *pFormat);

private:
    Ui::MainWindow *ui;
    QMdiArea *m_pMdiArea;
    QWidget *m_pWindowContainer;
    QDialog *m_pConsoleWnd;
    QString m_sLastUsedFolder;

private slots:
    void OnFileOpenClick();
    void OnMdiSubWindowActivated(QMdiSubWindow *pSubWindow);
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

class SceneSubWindow : public QWidget
{
    Q_OBJECT
public:
    explicit SceneSubWindow(GLWidget *pGlWidget, MainWindow *pMainWindow, QWidget *parent = nullptr);

    GLWidget *GlWidget() const;
    void SetGlWidget(GLWidget *pGlWidget);
    void UpdateAfterSceneLoaded();
    void UpdateNavigationButtons();
    void SetViewpointsCount(int nViewpointsCount);
    void MoveToViewpoint(int nView);
    void SetAntialiasing(bool bOn);

private:
    MainWindow *m_pMainWindow;
    GLWidget *m_pGlWidget;
    QVBoxLayout *m_pLayout;
    QWidget *m_pGlWidgetContainer;
    QToolBar *m_pToolBar;
    QToolButton *m_pViewpointsButton;
    QMenu *m_pViewpointsMenu;
    QAction *m_pActionWalk;
    QAction *m_pActionFly;
    QAction *m_pActionExamine;
    QAction *m_pActionTurntable;
    QAction *m_pActionPrevView;
    QAction *m_pActionNextView;
    int m_nViewpointCount;
    int m_iCurrentViewpoint;
    NavKeeper m_aNavKeeper;
};

#endif // MAINWINDOW_H
