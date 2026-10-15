/*
  Copyright 2014-2026 Jan Adamec, Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
*/

#include "mainwindow.h"
#include <QApplication>

int main(int argc, char *argv[])
{
    // Ensure all QOpenGLContext instances share resources in one shareGroup.
    // Castle Game Engine requires this as it caches resources and shares them to multiple windows.
    QApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QApplication a(argc, argv);
    MainWindow w;
    w.show();

    return a.exec();
}
