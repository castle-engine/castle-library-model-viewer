# Dynamic library to load and render 3D and 2D models, like X3D, VRML, glTF

This repository contains the code of a dynamic library using [Castle Game Engine](https://castle-engine.io/) to load, render and interact with models in [any format supported by Castle Game Engine](https://castle-engine.io/creating_data_model_formats.php) (like X3D, VRML, glTF).

This repository also contains the precompiled library (DLL, SO etc.) made using _GitHub Actions_.

The library [exposes API in plain C](https://github.com/castle-engine/castle-library-model-viewer/blob/master/castleengine.h) (and is thus useful from any programming language), and is available for all platforms supported by Castle Game Engine (Windows, Linux, macOS, iOS...). It is used "in production" by the [Room Arranger](https://www.roomarranger.com/) for the 3D viewer on multiple platforms.

The library allows to load and render models in an application written in any programming language (C, C++, C#, Python, ...) and display the results using any technology. You initialize OpenGL(ES) context on your side, in any way, and then call library routines to render models and interact with them.

*Note for [Pascal](https://castle-engine.io/why_pascal) developers:* You should not use this library, in short :) Instead use [full Castle Game Engine API in Pascal](https://castle-engine.io/), which is much more powerful (can manage any number of scenes, transformations, creatures, viewports, lights, user interface, physics, sound and more). This library is designed for a more limited purpose: load and render a single model at a time.

## Compiling

Enter this directory, and run `./castleengine_compile.sh` shell script.

This should produce `castleengine.dll` (on Windows), `libcastleengine.dylib` (on macOS) or `libcastleengine.so` (on Unix).

To compile static library for iOS, run `./compile-iOS.sh` shell script.

_Note for Windows_: `castleengine_compile.sh` requires you to have Cygwin or MinGW installed. It may be easier to call `castleengine_compile.bat`, which doesn't require anything special.

_Note_: Make sure that <code>fpc</code> binary is available on the environment variable <code>$PATH</code>. If you don't know how to set the environment variable, search the Internet (e.g. <a href="https://www.computerhope.com/issues/ch000549.htm">these are quick instructions how to do it on various Windows versions</a>).

When using under LGPL license, remember to add <code>--compiler-option=-dCASTLE_ENGINE_LGPL</code> parameter.

## Contents

- [castleengine.lpr](https://github.com/castle-engine/castle-library-model-viewer/tree/master/castleengine.lpr): the only source code file with all the library code

- [castleengine.h](https://github.com/castle-engine/castle-library-model-viewer/tree/master/castleengine.h): header file with the API.

- [castlelib_c_loader.cpp](https://github.com/castle-engine/castle-library-model-viewer/tree/master/castlelib_c_loader.cpp): helper C++ file to load the library dynamically. Contains code for multiplatform Qt and Windows

- [engine examples](https://github.com/castle-engine/castle-library-model-viewer/tree/master/examples) have various example projects using the library.

## Usage examples

### C++

* add `castleengine.h` and `castlelib_c_loader.cpp` to your project source files
* provide the compiled library `castleengine.dll/.dylib/.so` next to your exe file

### iOS

* add `castleengine.h` and `tremolo` sources to your project source files.
* add Pod file with `freetype` dependency. Install pods and use xcworkspace to open the project. Alternatively, compile Freetype as static library (`freetype.a`) separately and just link with it
* link with `libcastleengine.a`
