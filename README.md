# Dynamic library to load and render 3D and 2D models, like X3D, VRML, glTF

This repository will contain the code of a dynamic library using [Castle Game Engine](https://castle-engine.io/) to load and render models in [any format supported by Castle Game Engine](https://castle-engine.io/creating_data_model_formats.php) (like X3D, VRML, glTF).

TODO: For now the code of library is in another repo, and this repository just contains the precompiled library (DLL, SO etc.) made using _GitHub Actions_.

The library [exposes API in plain C](https://github.com/castle-engine/castle-engine/blob/master/src/deprecated_library/castleengine.h) (and is thus useful from any programming language), and is available for all platforms supported by Castle Game Engine (Windows, Linux, macOS, iOS...). It is used "in production" by the [Room Arranger](https://www.roomarranger.com/) for the 3D viewer on multiple platforms.

The library allows to load and render models in an application written in any programming language and display the results using any technology. You initialize OpenGL(ES) context on your side, in any way, and then call library routines to render models and interact with them.

*Note for [Pascal](https://castle-engine.io/why_pascal) developers:* You should not use this library, in short :) Instead use [full Castle Game Engine API in Pascal](https://castle-engine.io/), which is much more powerful (can manage any number of scenes, transformations, creatures, viewports, lights, user interface, physics, sound and more). This library is designed for a more limited purpose: load and render a single model at a time.

## Right now the code is part of engine

Right now (TODO) the library code and examples are part of the engine, but we plan to move them here:

- [engine src/deprecated_library subdirectory](https://github.com/castle-engine/castle-engine/tree/master/src/deprecated_library) contains the library code.

- [engine examples/deprecated_library](https://github.com/castle-engine/castle-engine/tree/master/examples/deprecated_library) have various examples using the library.

