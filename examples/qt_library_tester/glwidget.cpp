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

#include <QOpenGLFunctions>
#include <QMouseEvent>
#include <QTimer>
#include <castleengine.h>

#include "glwidget.h"
#include "mainwindow.h"

QHash<int, GLWidget *> GLWidget::s_contextWidgets;

GLWidget::GLWidget(const QSurfaceFormat &format) :
    QOpenGLWindow()
{
    m_pWnd = nullptr;
    m_bAfterInit = false;
    m_iCgeContext = -1;
    m_bLimitFPS = true;
    m_bNeedsDisplay = false;
    m_bPrintContextInfoAtPaint = false;
    setFormat(format);

    QTimer *pUpdateTimer = new QTimer(this);
    connect(pUpdateTimer, SIGNAL(timeout()), this, SLOT(OnUpdateTimer()));
    pUpdateTimer->start(20);    // 50 fps
}

GLWidget::~GLWidget()
{
    CloseCGEContext();
}

void GLWidget::SetParentWindow(SceneSubWindow *pParent)
{
    m_pWnd = pParent;
}

void GLWidget::OpenScene(QString const &sFilename)
{
    m_sSceneToOpen = sFilename;
    if (!m_bAfterInit)
        return;

    CGE_LoadSceneFromFile(m_iCgeContext, sFilename.toUtf8());
    double dPixRatio = devicePixelRatioF();
    CGE_Resize(m_iCgeContext, width()*dPixRatio, height()*dPixRatio);
    m_pWnd->UpdateAfterSceneLoaded();
}

void GLWidget::CloseCGEContext()
{
    if (m_iCgeContext != -1)
    {
        s_contextWidgets.remove(m_iCgeContext);
        CGE_Close(m_iCgeContext, true);
        m_iCgeContext = -1;
    }
}

int CDECL GLWidget::OpenGlLibraryCallback(int contextHandle, int eCode, int iParam1, int iParam2, const char *szParam)
{
    GLWidget *pThis = s_contextWidgets.value(contextHandle, nullptr);
    if (pThis == nullptr || !pThis->m_bAfterInit)
        return 0;

    switch (eCode)
    {
    case ecgelibNeedsDisplay:
        pThis->m_bNeedsDisplay = true;
        return 1;

    case ecgelibSetMouseCursor:
        {
            QCursor aNewCur;
            switch (iParam1)
            {
            case ecgecursorWait: aNewCur.setShape(Qt::WaitCursor); break;
            case ecgecursorHand: aNewCur.setShape(Qt::PointingHandCursor); break;
            case ecgecursorText: aNewCur.setShape(Qt::IBeamCursor); break;
            case ecgecursorNone: aNewCur.setShape(Qt::BlankCursor); break;
            default: aNewCur.setShape(Qt::ArrowCursor);
            }
            pThis->setCursor(aNewCur);
        }
        return 1;

    case ecgelibNavigationTypeChanged:
        pThis->m_pWnd->UpdateNavigationButtons();
        return 1;

    case ecgelibSetMousePosition:
        {
            QPoint ptNew = pThis->mapToGlobal(QPoint(iParam1, pThis->height() - 1 - iParam2));
            QCursor::setPos(ptNew.x(), ptNew.y());
        }
        return 1;

    case ecgelibWarning:
        {
            if (MainWindow::Instance() != nullptr)
                MainWindow::Instance()->AddNewWarning(QString::fromUtf8(szParam));
        }
        return 1;
    }
    return 0;
}

void GLWidget::initializeGL()
{
    double dPixRatio = devicePixelRatioF();
    m_iCgeContext = CGE_Open(ecgeofLog, width()*dPixRatio, height()*dPixRatio, logicalDpiY());
    s_contextWidgets.insert(m_iCgeContext, this);
    CGE_SetAutoTouchInterface(m_iCgeContext, false);
    CGE_SetLibraryCallbackProc(m_iCgeContext, OpenGlLibraryCallback);
    m_bAfterInit = true;
    if (!m_sSceneToOpen.isEmpty())
        OpenScene(m_sSceneToOpen);

    PrintContextInfo("initializeGL()");
    m_bPrintContextInfoAtPaint = true;
}

void GLWidget::PrintContextInfo(const QString &sTitle)
{
    GLint iSampleBuffers = -1;
    context()->functions()->glGetIntegerv(GL_SAMPLE_BUFFERS, &iSampleBuffers);
    GLint iSamples = -1;
    context()->functions()->glGetIntegerv(GL_SAMPLES, &iSamples);
    qDebug() << "Context info at" << sTitle << "GL_SAMPLE_BUFFERS:" << iSampleBuffers << ", GL_SAMPLES:" << iSamples;
}

void GLWidget::OnUpdateTimer()
{
    if (!m_bAfterInit) return;

    // be sure we have the right context set
    if (QOpenGLContext::currentContext() != context())
        makeCurrent();

    CGE_Update(m_iCgeContext);

    if (!m_bLimitFPS || m_bNeedsDisplay)
    {
        m_bNeedsDisplay = false;
        update();
    }
}

void GLWidget::paintGL()
{
    if (!m_bAfterInit) return;

    if (m_bPrintContextInfoAtPaint)
    {
        PrintContextInfo("paintGL()");
        m_bPrintContextInfoAtPaint = false;
    }

    CGE_Render(m_iCgeContext);
}

void GLWidget::resizeGL(int width, int height)
{
    if (m_bAfterInit && width > 0 && height > 0)
    {
        double dPixRatio = devicePixelRatioF();
        CGE_Resize(m_iCgeContext, width * dPixRatio, height * dPixRatio);
    }
}

QPoint GLWidget::PointFromMousePoint(const QPoint& pt)
{
    QPoint ptNew(pt.x(), height() - 1 - pt.y());
    ptNew *= devicePixelRatioF();
    return ptNew;
}

QPoint GLWidget::PointFromMousePoint(const QPointF& pt)
{
    QPoint ptNew(pt.x(), height() - 1 - pt.y());
    ptNew *= devicePixelRatioF();
    return ptNew;
}

void GLWidget::mousePressEvent(QMouseEvent *event)
{
    if (!m_bAfterInit) return;

    QPoint pt(PointFromMousePoint(event->pos()));
    CGE_MouseDown(m_iCgeContext, pt.x(), pt.y(), event->button()==Qt::LeftButton, 0);
}

void GLWidget::mouseMoveEvent(QMouseEvent *event)
{
    if (!m_bAfterInit) return;

    QPoint pt(PointFromMousePoint(event->pos()));
    CGE_Motion(m_iCgeContext, pt.x(), pt.y(), 0);
}

void GLWidget::mouseReleaseEvent(QMouseEvent *event)
{
    if (!m_bAfterInit) return;

    QPoint pt(PointFromMousePoint(event->pos()));
    CGE_MouseUp(m_iCgeContext, pt.x(), pt.y(), event->button()==Qt::LeftButton, 0);
}

#ifndef QT_NO_WHEELEVENT
void GLWidget::wheelEvent(QWheelEvent *event)
{
    if (event->angleDelta().y() != 0)
        CGE_MouseWheel(m_iCgeContext, event->angleDelta().y(), true);
    else
        CGE_MouseWheel(m_iCgeContext, event->angleDelta().x(), false);

    if (m_bNeedsDisplay)
    {
        m_bNeedsDisplay = false;
        update();
    }
}
#endif

void GLWidget::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape && CGE_GetVariableInt(m_iCgeContext, ecgevarMouseLook)==1)
    {
        CGE_SetVariableInt(m_iCgeContext, ecgevarMouseLook, 0);
        CGE_SetVariableInt(m_iCgeContext, ecgevarCrossHair, 0);
        event->accept();
        return;
    }

    CGE_KeyDown(m_iCgeContext, QKeyToCgeKey(event->key()));
}

void GLWidget::keyReleaseEvent(QKeyEvent *event)
{
    CGE_KeyUp(m_iCgeContext, QKeyToCgeKey(event->key()));
}

int GLWidget::QKeyToCgeKey(int qKey)
{
    if (qKey >= Qt::Key_0 && qKey <= Qt::Key_9)
        return kcge_0 + qKey - Qt::Key_0;
    if (qKey >= Qt::Key_A && qKey <= Qt::Key_Z)
        return kcge_A + qKey - Qt::Key_A;
    if (qKey >= Qt::Key_F1 && qKey <= Qt::Key_F12)
        return kcge_F1 + qKey - Qt::Key_F1;

    switch (qKey)
    {
    case Qt::Key_Print: return kcge_PrintScreen;
    case Qt::Key_CapsLock: return kcge_CapsLock;
    case Qt::Key_ScrollLock: return kcge_ScrollLock;
    case Qt::Key_NumLock: return kcge_NumLock;
    case Qt::Key_Pause: return kcge_Pause;
    case Qt::Key_Apostrophe: return kcge_Apostrophe;
    case Qt::Key_Semicolon: return kcge_Semicolon;
    case Qt::Key_Backspace: return kcge_BackSpace;
    case Qt::Key_Tab: return kcge_Tab;
    case Qt::Key_Slash: return kcge_Slash;
    case Qt::Key_QuoteLeft: return kcge_BackQuote;
    case Qt::Key_Minus: return kcge_Minus;
    case Qt::Key_Return: return kcge_Enter;
    case Qt::Key_Equal: return kcge_Equal;
    case Qt::Key_Backslash: return kcge_BackSlash;
    case Qt::Key_Shift: return kcge_Shift;
    case Qt::Key_Control: return kcge_Ctrl;
    case Qt::Key_Alt: return kcge_Alt;
    case Qt::Key_Plus: return kcge_Plus;
    case Qt::Key_Escape: return kcge_Escape;
    case Qt::Key_Space: return kcge_Space;
    case Qt::Key_PageUp: return kcge_PageUp;
    case Qt::Key_PageDown: return kcge_PageDown;
    case Qt::Key_End: return kcge_End;
    case Qt::Key_Home: return kcge_Home;
    case Qt::Key_Left: return kcge_Left;
    case Qt::Key_Up: return kcge_Up;
    case Qt::Key_Right: return kcge_Right;
    case Qt::Key_Down: return kcge_Down;
    case Qt::Key_Insert: return kcge_Insert;
    case Qt::Key_Delete: return kcge_Delete;
    case Qt::Key_BracketLeft: return kcge_LeftBracket;
    case Qt::Key_BracketRight: return kcge_RightBracket;
    case Qt::Key_Enter: return kcge_Numpad_Enter;
    case Qt::Key_Comma: return kcge_Comma;
    case Qt::Key_Period: return kcge_Period;

    default: return kcge_None;
    }
}
