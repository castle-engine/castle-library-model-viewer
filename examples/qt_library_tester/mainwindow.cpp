/*
  Copyright 2014-2024 Jan Adamec, Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
*/

#include "mainwindow.h"
#include "ui_mainwindow.h"
#include "glwidget.h"

#include <QDialog>
#include <QFileDialog>
#include <QPlainTextEdit>
#include <QSettings>
#include <QStandardPaths>
#include <QVBoxLayout>

#include <castleengine.h>

MainWindow *g_pMainWnd = nullptr;

MainWindow::MainWindow(QWidget *parent) :
    QMainWindow(parent),
    ui(new Ui::MainWindow)
{
    ui->setupUi(this);

    g_pMainWnd = this;
    m_pConsoleWnd = nullptr;
    m_pMdiArea = new QMdiArea(this);
    m_pMdiArea->setHorizontalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    m_pMdiArea->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    m_pMdiArea->setViewMode(QMdiArea::SubWindowView);
    m_pMdiArea->setOption(QMdiArea::DontMaximizeSubWindowOnActivation, false);
    setCentralWidget(m_pMdiArea);
    connect(m_pMdiArea, SIGNAL(subWindowActivated(QMdiSubWindow*)), this, SLOT(OnMdiSubWindowActivated(QMdiSubWindow*)));

    CGE_LoadLibrary();
    // Get config dir, see https://stackoverflow.com/questions/4369661/qt-how-to-save-a-configuration-file-on-multiple-platforms
    QString configDir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    CGE_Initialize(configDir.toUtf8());

    // load settings
    QSettings aSettings("castleengine", "qt_library_tester");
    m_sLastUsedFolder = aSettings.value("lastFolder", ".").toString();
    ui->actionMultiSampling->setChecked(aSettings.value("multiSampling", true).toBool());

    // define OpenGL context format
    QSurfaceFormat aFormat;
    SetSurfaceFormat(&aFormat);
    aFormat.setSamples(ui->actionMultiSampling->isChecked() ? 4 : 0);
    QSurfaceFormat::setDefaultFormat(aFormat);

    connect(ui->actionOpen, SIGNAL(triggered()), this, SLOT(OnFileOpenClick()));
    connect(ui->actionSSAO, SIGNAL(triggered()), this, SLOT(MenuSoftShadowsClick()));
    connect(ui->actionHead_Bobbing, SIGNAL(triggered()), this, SLOT(MenuWalkingEffectClick()));
    connect(ui->actionMouse_Look, SIGNAL(triggered()), this, SLOT(MenuMouseLookClick()));
    connect(ui->actionMultiSampling, SIGNAL(triggered()), this, SLOT(MenuAntiAliasingClick()));
    connect(ui->actionOpenGL_Information, SIGNAL(triggered()), this, SLOT(MenuOpenGLInfoClick()));
    connect(ui->actionShow_Warnings, SIGNAL(triggered()), this, SLOT(MenuShowWarningClick()));
}

MainWindow::~MainWindow()
{
    SaveSettings();
    for (QMdiSubWindow *pSubWindow : m_pMdiArea->subWindowList())
    {
        GLWidget *pGlWidget = MainWindow::GlWidgetFromMdiSubWindow(pSubWindow);
        if (pGlWidget != nullptr)
            pGlWidget->CloseCGEContext();
    }
    delete ui;
    CGE_Finalize();
    g_pMainWnd = nullptr;
}

MainWindow *MainWindow::Instance()
{
    return g_pMainWnd;
}

void MainWindow::SetSurfaceFormat(QSurfaceFormat *pFormat)
{
    pFormat->setRenderableType(QSurfaceFormat::OpenGL);
    pFormat->setRedBufferSize(8);
    pFormat->setGreenBufferSize(8);
    pFormat->setBlueBufferSize(8);
    pFormat->setAlphaBufferSize(8);
    pFormat->setDepthBufferSize(24);
    pFormat->setStencilBufferSize(8);
    pFormat->setSwapBehavior(QSurfaceFormat::DoubleBuffer);
    pFormat->setSwapInterval(1);
#ifdef Q_OS_MAC
    pFormat->setMajorVersion(3);
    pFormat->setMinorVersion(2);
    pFormat->setProfile(QSurfaceFormat::CoreProfile);
#endif
}

void MainWindow::SaveSettings()
{
    QSettings aSettings("castleengine", "qt_library_tester");
    aSettings.setValue("lastFolder", m_sLastUsedFolder);
    aSettings.setValue("multiSampling", ui->actionMultiSampling->isChecked());
}

GLWidget *MainWindow::GlWidgetFromMdiSubWindow(QMdiSubWindow *pSubWindow)
{
    if (pSubWindow == nullptr)
        return nullptr;
    SceneSubWindow *pSceneWindow = qobject_cast<SceneSubWindow *>(pSubWindow->widget());
    if (pSceneWindow != nullptr)
        return pSceneWindow->GlWidget();
    else
        return nullptr;
}

GLWidget *MainWindow::ActiveGlWidget() const
{
    return MainWindow::GlWidgetFromMdiSubWindow(m_pMdiArea->activeSubWindow());
}

void MainWindow::OpenSceneInNewWindow(QString const& sFilename)
{
    if (sFilename.isEmpty())
        return;

    QSurfaceFormat aFormat;
    SetSurfaceFormat(&aFormat);
    aFormat.setSamples(ui->actionMultiSampling->isChecked() ? 4 : 0);

    GLWidget *pGlWidget = new GLWidget(aFormat);
    SceneSubWindow *pSceneWindow = new SceneSubWindow(pGlWidget, this, this);
    QMdiSubWindow *pSubWindow = m_pMdiArea->addSubWindow(pSceneWindow);
    pSubWindow->setAttribute(Qt::WA_DeleteOnClose, true);
    pSubWindow->setWindowTitle(QFileInfo(sFilename).fileName());
    pSubWindow->resize(400, 300);
    pSubWindow->show();
    m_pMdiArea->setActiveSubWindow(pSubWindow);
    pGlWidget->OpenScene(sFilename);
    OnMdiSubWindowActivated(pSubWindow);
}

void MainWindow::OnFileOpenClick()
{
    QStringList sFiles = QFileDialog::getOpenFileNames(this, tr("Open Scene"), m_sLastUsedFolder, tr("3D scenes") +
        " (*.wrl *.wrl.gz *.wrz *.x3d *.x3dz *.x3d.gz *.x3dv *.x3dvz *.x3dv.gz *.kanim *.castle-anim-frames *.dae *.iv *.3ds *.md3 *.obj *.geo *.json *.stl *.gltf *.glb)");
    if (sFiles.isEmpty())
        return;

    foreach (const QString &sFile, sFiles)
    {
        m_sLastUsedFolder = QFileInfo(sFile).absolutePath();
        OpenSceneInNewWindow(sFile);
    }
}

void MainWindow::OnMdiSubWindowActivated(QMdiSubWindow *pSubWindow)
{
    GLWidget *pGlWidget = MainWindow::GlWidgetFromMdiSubWindow(pSubWindow);
    if (pGlWidget != nullptr)
    {
        ui->actionHead_Bobbing->setChecked(CGE_GetVariableInt(pGlWidget->m_iCgeContext, ecgevarWalkHeadBobbing)>0);
        ui->actionHeadlight->setChecked(CGE_GetVariableInt(pGlWidget->m_iCgeContext, ecgevarHeadlight)>0);
        ui->actionSSAO->setChecked(CGE_GetVariableInt(pGlWidget->m_iCgeContext, ecgevarEffectSSAO)>0);
    }
}

void MainWindow::MenuSoftShadowsClick()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;

    bool bSwitchOn = ui->actionSSAO->isChecked();
    CGE_SetVariableInt(pGlWidget->m_iCgeContext, ecgevarEffectSSAO, bSwitchOn ? 1 : 0);
}

void MainWindow::MenuAntiAliasingClick()
{
    QMdiSubWindow *pSubWindow = m_pMdiArea->activeSubWindow();
    if (pSubWindow == nullptr)
        return;
    SceneSubWindow *pSceneWindow = qobject_cast<SceneSubWindow *>(pSubWindow->widget());
    if (pSceneWindow != nullptr)
        pSceneWindow->SetAntialiasing(ui->actionMultiSampling->isChecked());
}

void MainWindow::MenuWalkingEffectClick()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;

    bool bSwitchOn = ui->actionHead_Bobbing->isChecked();
    CGE_SetVariableInt(pGlWidget->m_iCgeContext, ecgevarWalkHeadBobbing, bSwitchOn ? 1 : 0);
}

void MainWindow::MenuMouseLookClick()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;

    CGE_SetVariableInt(pGlWidget->m_iCgeContext, ecgevarMouseLook, 1);
    CGE_SetVariableInt(pGlWidget->m_iCgeContext, ecgevarCrossHair, 1);
}

void MainWindow::on_actionHeadlight_triggered()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;

    bool bSwitchOn = ui->actionHeadlight->isChecked();
    CGE_SetVariableInt(pGlWidget->m_iCgeContext, ecgevarHeadlight, bSwitchOn ? 1 : 0);
}

void MainWindow::AddNewWarning(QString const& sWarning)
{
    if (m_pConsoleWnd==NULL)
        MenuShowWarningClick();
    QPlainTextEdit *pEdit = qobject_cast<QPlainTextEdit*>(m_pConsoleWnd->layout()->itemAt(0)->widget());
    if (pEdit!=NULL)
        pEdit->appendPlainText(sWarning);
}

void MainWindow::MenuShowWarningClick()
{
    if (m_pConsoleWnd==NULL)
    {
        m_pConsoleWnd = new QDialog(this);
        m_pConsoleWnd->setWindowTitle(tr("Log - Warnings"));
        m_pConsoleWnd->setWindowFlags(m_pConsoleWnd->windowFlags() & ~Qt::WindowContextHelpButtonHint);

        QPlainTextEdit *pEdit = new QPlainTextEdit(m_pConsoleWnd);
        pEdit->setMinimumSize(600, 500);
        pEdit->setReadOnly(true);

        QVBoxLayout *pLayout = new QVBoxLayout(m_pConsoleWnd);
        pLayout->setContentsMargins(0, 0, 0, 0);
        m_pConsoleWnd->setLayout(pLayout);
        pLayout->insertWidget(0, pEdit);
        m_pConsoleWnd->resize(m_pConsoleWnd->minimumSize());
    }
    m_pConsoleWnd->show();
}

void MainWindow::MenuOpenGLInfoClick()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr)
        return;

    pGlWidget->makeCurrent();

    char szBuf[16000];
    memset(szBuf, 0, sizeof(szBuf));
    CGE_GetOpenGLInformation(szBuf, sizeof(szBuf));

    pGlWidget->doneCurrent();

    QDialog aDlg(this);
    aDlg.setWindowTitle(tr("OpenGL Information"));
    aDlg.setWindowFlags(aDlg.windowFlags() & ~Qt::WindowContextHelpButtonHint);

    QPlainTextEdit *pEdit = new QPlainTextEdit(&aDlg);
    pEdit->setPlainText(QString::fromUtf8(szBuf));
    pEdit->setMinimumSize(500, 500);
    pEdit->setReadOnly(true);

    QVBoxLayout *pLayout = new QVBoxLayout(&aDlg);
    pLayout->setContentsMargins(0, 0, 0, 0);
    aDlg.setLayout(pLayout);
    pLayout->insertWidget(0, pEdit);
    aDlg.resize(aDlg.minimumSize());
    aDlg.exec();
}

void MainWindow::on_actionSave_Screenshot_triggered()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;

    QString sFile = QFileDialog::getSaveFileName(this, "Save as image", "CGE-Screenshot.jpg", "JPEG (*.jpg)");
    if (sFile.isEmpty()) return;

    CGE_SaveScreenshotToFile(pGlWidget->m_iCgeContext, sFile.toUtf8());  // TODO: this filename string conversion is not perfect: should be in filesystem representation, not utf8
}

ActionWithTag::ActionWithTag(QString const& sCaption, int nTag, QObject * parent)
    : QAction(parent), m_nTag(nTag)
{
    setText(sCaption);
}

SceneSubWindow::SceneSubWindow(GLWidget *pGlWidget, MainWindow *pMainWindow, QWidget *parent)
    : QWidget(parent),
    m_pMainWindow(pMainWindow),
    m_pGlWidget(pGlWidget),
    m_pLayout(new QVBoxLayout(this)),
    m_pGlWidgetContainer(nullptr),
    m_pToolBar(nullptr),
    m_pViewpointsButton(nullptr),
    m_pViewpointsMenu(nullptr),
    m_pActionWalk(nullptr),
    m_pActionFly(nullptr),
    m_pActionExamine(nullptr),
    m_pActionTurntable(nullptr),
    m_pActionPrevView(nullptr),
    m_pActionNextView(nullptr),
    m_nViewpointCount(0),
    m_iCurrentViewpoint(0)
{
    m_pLayout->setContentsMargins(0, 0, 0, 0);
    m_pLayout->setSpacing(0);

    SetGlWidget(pGlWidget);

    m_pToolBar = new QToolBar(this);
    m_pToolBar->setMovable(false);
    m_pToolBar->setFloatable(false);
    m_pToolBar->setToolButtonStyle(Qt::ToolButtonTextOnly);

    m_pActionWalk = new QAction(tr("Walk"), this);
    m_pActionWalk->setCheckable(true);
    connect(m_pActionWalk, &QAction::triggered, this, [this]() {
        if (m_pGlWidget == nullptr || m_pGlWidget->m_iCgeContext == -1)
            return;
        CGE_SetNavigationType(m_pGlWidget->m_iCgeContext, ecgenavWalk);
    });

    m_pActionFly = new QAction(tr("Fly"), this);
    m_pActionFly->setCheckable(true);
    connect(m_pActionFly, &QAction::triggered, this, [this]() {
        if (m_pGlWidget == nullptr || m_pGlWidget->m_iCgeContext == -1)
            return;
        CGE_SetNavigationType(m_pGlWidget->m_iCgeContext, ecgenavFly);
    });

    m_pActionExamine = new QAction(tr("Examine"), this);
    m_pActionExamine->setCheckable(true);
    connect(m_pActionExamine, &QAction::triggered, this, [this]() {
        if (m_pGlWidget == nullptr || m_pGlWidget->m_iCgeContext == -1)
            return;
        CGE_SetNavigationType(m_pGlWidget->m_iCgeContext, ecgenavExamine);
    });

    m_pActionTurntable = new QAction(tr("Turntable"), this);
    m_pActionTurntable->setCheckable(true);
    connect(m_pActionTurntable, &QAction::triggered, this, [this]() {
        if (m_pGlWidget == nullptr || m_pGlWidget->m_iCgeContext == -1)
            return;
        CGE_SetNavigationType(m_pGlWidget->m_iCgeContext, ecgenavTurntable);
    });

    m_pActionPrevView = new QAction(tr("Prev View"), this);
    connect(m_pActionPrevView, &QAction::triggered, this, [this]() {
        MoveToViewpoint(m_iCurrentViewpoint - 1);
    });

    m_pViewpointsButton = new QToolButton(this);
    m_pViewpointsButton->setText(tr("Viewpoints"));
    m_pViewpointsButton->setPopupMode(QToolButton::InstantPopup);
    m_pViewpointsMenu = new QMenu(this);
    m_pViewpointsButton->setMenu(m_pViewpointsMenu);
    m_pViewpointsButton->setEnabled(false);

    m_pActionNextView = new QAction(tr("Next View"), this);
    connect(m_pActionNextView, &QAction::triggered, this, [this]() {
        MoveToViewpoint(m_iCurrentViewpoint + 1);
    });

    m_pToolBar->addAction(m_pActionWalk);
    m_pToolBar->addAction(m_pActionFly);
    m_pToolBar->addAction(m_pActionExamine);
    m_pToolBar->addAction(m_pActionTurntable);
    m_pToolBar->addSeparator();
    m_pToolBar->addAction(m_pActionPrevView);
    m_pToolBar->addWidget(m_pViewpointsButton);
    m_pToolBar->addAction(m_pActionNextView);
    m_pLayout->addWidget(m_pToolBar);

    UpdateNavigationButtons();
}

GLWidget *SceneSubWindow::GlWidget() const
{
    return m_pGlWidget;
}

void SceneSubWindow::SetGlWidget(GLWidget *pGlWidget)
{
    m_pGlWidget = pGlWidget;
    if (m_pGlWidgetContainer != nullptr)
    {
        m_pLayout->removeWidget(m_pGlWidgetContainer);
        m_pGlWidgetContainer->deleteLater();
        m_pGlWidgetContainer = nullptr;
    }

    if (m_pGlWidget != nullptr)
    {
        m_pGlWidgetContainer = QWidget::createWindowContainer(m_pGlWidget, this);
        m_pLayout->insertWidget(0, m_pGlWidgetContainer, 1);
        m_pGlWidget->SetParentWindow(this);
    }
}

void SceneSubWindow::UpdateAfterSceneLoaded()
{
    SetViewpointsCount(CGE_GetViewpointsCount(m_pGlWidget->m_iCgeContext));
    CGE_SetVariableInt(m_pGlWidget->m_iCgeContext, ecgevarPreventInfiniteFallingDown, 1);

    if (m_aNavKeeper.ApplyState(m_pGlWidget->m_iCgeContext))  // when scene loading was caused by reloading (changing multisampling, etc)
        UpdateNavigationButtons();
}

void SceneSubWindow::UpdateNavigationButtons()
{
    if (m_pGlWidget == nullptr || m_pGlWidget->m_iCgeContext == -1)
        return;

    ECgeNavigationType eNav = (ECgeNavigationType)CGE_GetNavigationType(m_pGlWidget->m_iCgeContext);
    if (m_pActionWalk != nullptr)
        m_pActionWalk->setChecked(eNav == ecgenavWalk);
    if (m_pActionFly != nullptr)
        m_pActionFly->setChecked(eNav == ecgenavFly);
    if (m_pActionExamine != nullptr)
        m_pActionExamine->setChecked(eNav == ecgenavExamine);
    if (m_pActionTurntable != nullptr)
        m_pActionTurntable->setChecked(eNav == ecgenavTurntable);
}

void SceneSubWindow::SetViewpointsCount(int nViewpointsCount)
{
    m_nViewpointCount = nViewpointsCount;
    m_iCurrentViewpoint = 0;

    if (m_pViewpointsMenu == nullptr || m_pViewpointsButton == nullptr)
        return;

    m_pViewpointsMenu->clear();
    if (m_pGlWidget == nullptr || m_pGlWidget->m_iCgeContext == -1)
    {
        m_pViewpointsButton->setEnabled(false);
        return;
    }

    for (int i = 0; i < m_nViewpointCount; ++i)
    {
        char sName[512];
        CGE_GetViewpointName(m_pGlWidget->m_iCgeContext, i, sName, 512);
        QAction *pAct = new QAction(QString::fromUtf8(sName), m_pViewpointsMenu);
        connect(pAct, &QAction::triggered, this, [this, i]() {
            MoveToViewpoint(i);
        });
        m_pViewpointsMenu->addAction(pAct);
    }

    m_pViewpointsButton->setEnabled(m_nViewpointCount > 0);
}

void SceneSubWindow::MoveToViewpoint(int nView)
{
    if (m_pGlWidget == nullptr || m_pGlWidget->m_iCgeContext == -1)
        return;
    if (m_nViewpointCount <= 0)
        return;
    if (nView < 0)
        nView = m_nViewpointCount - 1;
    if (nView >= m_nViewpointCount)
        nView = 0;
    m_iCurrentViewpoint = nView;
    CGE_MoveToViewpoint(m_pGlWidget->m_iCgeContext, m_iCurrentViewpoint, true);
}

void SceneSubWindow::SetAntialiasing(bool bOn)
{
    m_aNavKeeper.SaveState(m_pGlWidget->m_iCgeContext);
    QString sScene = m_pGlWidget->m_sSceneToOpen;
    m_pGlWidget->CloseCGEContext();

    QSurfaceFormat aFormat;
    MainWindow::SetSurfaceFormat(&aFormat);
    aFormat.setSamples(bOn ? 4 : 0);

    GLWidget *pNewGlWidget = new GLWidget(aFormat);
    SetGlWidget(pNewGlWidget);
    pNewGlWidget->OpenScene(sScene);
    setFocus();
}

NavKeeper::NavKeeper()
{
    bToBeApplied = false;
}

void NavKeeper::SaveState(int iCgeContext)
{
    CGE_GetViewCoords(iCgeContext, &fPosX, &fPosY, &fPosZ, &fDirX, &fDirY, &fDirZ, &fUpX, &fUpY, &fUpZ, &fGravX, &fGravY, &fGravZ);
    eNavType = CGE_GetNavigationType(iCgeContext);
    bToBeApplied = true;
}

bool NavKeeper::ApplyState(int iCgeContext)
{
    if (!bToBeApplied) return false;

    CGE_MoveViewToCoords(iCgeContext, fPosX, fPosY, fPosZ, fDirX, fDirY, fDirZ, fUpX, fUpY, fUpZ, fGravX, fGravY, fGravZ, false);
    CGE_SetNavigationType(iCgeContext, eNavType);

    bToBeApplied = false;
    return true;
}
