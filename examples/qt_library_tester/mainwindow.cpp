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

MainWindow::MainWindow(QWidget *parent) :
    QMainWindow(parent),
    ui(new Ui::MainWindow)
{
    ui->setupUi(this);

    m_nViewpointCount = m_iCurrentViewpoint = 0;
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
    connect(ui->actionWalk, SIGNAL(triggered()), this, SLOT(OnWalkClick()));
    connect(ui->actionFly, SIGNAL(triggered()), this, SLOT(OnFlyClick()));
    connect(ui->actionExamine, SIGNAL(triggered()), this, SLOT(OnExamineClick()));
    connect(ui->actionTurntable, SIGNAL(triggered()), this, SLOT(OnTurntableClick()));
    connect(ui->actionNextView, SIGNAL(triggered()), this, SLOT(OnNextViewClick()));
    connect(ui->actionPrevView, SIGNAL(triggered()), this, SLOT(OnPrevViewClick()));

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
    for (GLWidget *pGlWidget : m_sceneWindows.values())
        if (pGlWidget != nullptr)
            pGlWidget->CloseCGEContext();
    delete ui;
    CGE_Finalize();
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

GLWidget *MainWindow::ActiveGlWidget() const
{
    return m_sceneWindows.value(m_pMdiArea->activeSubWindow(), nullptr);
}

void MainWindow::OpenSceneInNewWindow(QString const& sFilename)
{
    if (sFilename.isEmpty())
        return;

    QSurfaceFormat aFormat;
    SetSurfaceFormat(&aFormat);
    aFormat.setSamples(ui->actionMultiSampling->isChecked() ? 4 : 0);

    GLWidget *pGlWidget = new GLWidget(aFormat, this);
    QWidget *pWindowContainer = QWidget::createWindowContainer(pGlWidget, this);
    QMdiSubWindow *pSubWindow = m_pMdiArea->addSubWindow(pWindowContainer);
    pSubWindow->setAttribute(Qt::WA_DeleteOnClose, true);
    pSubWindow->setWindowTitle(QFileInfo(sFilename).fileName());
    pSubWindow->resize(640, 480);
    m_sceneWindows.insert(pSubWindow, pGlWidget);
    pSubWindow->show();
    m_pMdiArea->setActiveSubWindow(pSubWindow);
    pGlWidget->OpenScene(sFilename);
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
    if (pSubWindow == nullptr)
        return;
    GLWidget *pGlWidget = m_sceneWindows.value(pSubWindow, nullptr);
    if (pGlWidget != nullptr)
        UpdateAfterSceneLoaded();
    else
        ui->menuViewpoints->clear();
}

void MainWindow::UpdateNavigationButtons()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;

    ECgeNavigationType eNav = (ECgeNavigationType)CGE_GetNavigationType(pGlWidget->m_iCgeContext);
    ui->actionWalk->setChecked(eNav == ecgenavWalk);
    ui->actionFly->setChecked(eNav == ecgenavFly);
    ui->actionExamine->setChecked(eNav == ecgenavExamine);
    ui->actionTurntable->setChecked(eNav == ecgenavTurntable);
}

void MainWindow::OnWalkClick()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;
    CGE_SetNavigationType(pGlWidget->m_iCgeContext, ecgenavWalk);
}

void MainWindow::OnFlyClick()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;
    CGE_SetNavigationType(pGlWidget->m_iCgeContext, ecgenavFly);
}

void MainWindow::OnExamineClick()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;
    CGE_SetNavigationType(pGlWidget->m_iCgeContext, ecgenavExamine);
}

void MainWindow::OnTurntableClick()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;
    CGE_SetNavigationType(pGlWidget->m_iCgeContext, ecgenavTurntable);
}

void MainWindow::UpdateAfterSceneLoaded()
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;

    ui->menuViewpoints->clear();
    // show viewpoints available
    int nCount = CGE_GetViewpointsCount(pGlWidget->m_iCgeContext);
    for (int i = 0; i < nCount; i++)
    {
        char sName[512];
        CGE_GetViewpointName(pGlWidget->m_iCgeContext, i, sName, 512);
        ActionWithTag *pAct = new ActionWithTag(QString::fromUtf8(sName), i, ui->menuViewpoints);
        connect(pAct, SIGNAL(triggered()), this, SLOT(OnMoveToViewpointClick()));
        ui->menuViewpoints->addAction(pAct);
    }
    m_iCurrentViewpoint = 0;
    m_nViewpointCount = nCount;

    ui->actionHead_Bobbing->setChecked(CGE_GetVariableInt(pGlWidget->m_iCgeContext, ecgevarWalkHeadBobbing)>0);
    ui->actionHeadlight->setChecked(CGE_GetVariableInt(pGlWidget->m_iCgeContext, ecgevarHeadlight)>0);
    ui->actionSSAO->setChecked(CGE_GetVariableInt(pGlWidget->m_iCgeContext, ecgevarEffectSSAO)>0);

    CGE_SetVariableInt(pGlWidget->m_iCgeContext, ecgevarPreventInfiniteFallingDown, 1);

    if (m_aNavKeeper.ApplyState(pGlWidget->m_iCgeContext))  // when scene loading was caused by reloading (changing multisampling, etc)
        UpdateNavigationButtons();
}

void MainWindow::OnMoveToViewpointClick()
{
    ActionWithTag *pAct = qobject_cast<ActionWithTag*>(sender());
    if (pAct == NULL) return;
    MoveToViewpoint(pAct->m_nTag);
}

void MainWindow::OnNextViewClick()
{
    MoveToViewpoint(m_iCurrentViewpoint+1);
}

void MainWindow::OnPrevViewClick()
{
    MoveToViewpoint(m_iCurrentViewpoint-1);
}

void MainWindow::MoveToViewpoint(int nView)
{
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;

    if (nView < 0) nView = m_nViewpointCount-1; // for cycling
    if (nView > m_nViewpointCount) nView = 0;
    m_iCurrentViewpoint = nView;
    CGE_MoveToViewpoint(pGlWidget->m_iCgeContext, m_iCurrentViewpoint, true);
}

ActionWithTag::ActionWithTag(QString const& sCaption, int nTag, QObject * parent)
    : QAction(parent), m_nTag(nTag)
{
    setText(sCaption);
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
    GLWidget *pGlWidget = ActiveGlWidget();
    if (pGlWidget == nullptr || pGlWidget->m_iCgeContext == -1)
        return;

    QMdiSubWindow *pSubWindow = nullptr;
    for (auto it = m_sceneWindows.begin(); it != m_sceneWindows.end(); ++it)
    {
        if (it.value() == pGlWidget)
        {
            pSubWindow = it.key();
            break;
        }
    }
    if (pSubWindow == nullptr)
        return;

    m_aNavKeeper.SaveState(pGlWidget->m_iCgeContext);
    QString sScene = pGlWidget->m_sSceneToOpen;
    pGlWidget->CloseCGEContext();

    QSurfaceFormat aFormat;
    SetSurfaceFormat(&aFormat);
    aFormat.setSamples(ui->actionMultiSampling->isChecked() ? 4 : 0);

    GLWidget *pNewGlWidget = new GLWidget(aFormat, this);
    QWidget *pOldContainer = pSubWindow->widget();
    QWidget *pNewContainer = QWidget::createWindowContainer(pNewGlWidget, pSubWindow);
    pSubWindow->setWidget(pNewContainer);
    m_sceneWindows[pSubWindow] = pNewGlWidget;

    if (pOldContainer != nullptr)
        pOldContainer->deleteLater();

    pNewGlWidget->OpenScene(sScene);
    pNewContainer->setFocus();
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

