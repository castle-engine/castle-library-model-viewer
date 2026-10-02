{ -*- compile-command: "./castleengine_compile.sh" -*- }
{
  Copyright 2013-2026 Jan Adamec, Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ The castleengine library main source code.
  This compiles to castleengine.dll / libcastleengine.so / libcastleengine.dylib.

  Development notes:

  Adapted from Jonas Maebe's example project :
  http://users.elis.ugent.be/~jmaebe/fpc/FPC_Objective-C_Cocoa.tbz
  http://julien.marcel.free.fr/ObjP_Part7.html

  To make c-compatible (and Xcode-compatible) libraries, you must :
  1- use c-types arguments
  2- add a "cdecl" declaration after your functions declarations
  3- export your functions

  See FPC CTypes unit (source rtl/unix/ctypes.inc) for a full list of c-types.
}

library castleengine;

uses CTypes, Math, SysUtils, CastleUtils,
  Classes, Contnrs, CastleKeysMouse, CastleCameras, CastleVectors, CastleGLUtils, CastleGLVersion,
  CastleImages, CastleSceneCore, CastleUIControls, X3DNodes, X3DFields, X3DLoad, CastleLog,
  CastleBoxes, CastleControls, CastleInputs, CastleApplicationProperties,
  CastleWindow, CastleViewport, CastleScene, CastleTransform, CastleStringUtils;

type
  ppcchar = ^pcchar;
  TCgeLibraryCallbackProc = function (ContextHandle: cInt32; eCode: cInt32; iParam1, iParam2: cInt32; szParam: pcchar): cInt32; cdecl;

  TLibraryContext = class;

  TCrosshairManager = class(TObject)
  private
    FOwnerCtx: TLibraryContext;
  public
    CrosshairCtl: TCastleCrosshair;
    CrosshairActive: boolean;

    constructor Create(const AOwner: TLibraryContext);
    destructor Destroy; override;

    procedure UpdateCrosshairImage;
    procedure OnPointingDeviceSensorsChange(Sender: TObject);
  end;

  TLibraryContext = class(TObject)
  public
    Handle: cInt32;
    Window: TCastleWindow;
    { Using TCastleAutoNavigationViewport in this case is justified,
      it is the most straightforward solution to make viewport navigation
      follow X3D navigation. }
    {$warnings off}
    Viewport: TCastleAutoNavigationViewport;
    {$warnings on}
    MainScene: TCastleScene; //< Always equal to Viewport.Items.MainScene
    PreviousNavigationType: TNavigationType;
    TouchNavigation: TCastleTouchNavigation;
    Crosshair: TCrosshairManager;
    LibraryCallbackProc: TCgeLibraryCallbackProc;

    constructor Create;
    destructor Destroy; override;
  end;

var
  ContextList: TObjectList = nil;
  NextContextHandle: cInt32 = 1;

constructor TLibraryContext.Create;
begin
  inherited;
end;

destructor TLibraryContext.Destroy;
begin
  FreeAndNil(Crosshair);
  FreeAndNil(Window);
  inherited;
end;

function CGE_FindContextByHandle(const ContextHandle: cInt32): TLibraryContext;
var
  I: Integer;
  Ctx: TLibraryContext;
begin
  Result := nil;
  if (ContextList = nil) or (ContextList.Count = 0) then
    exit;
  for I := 0 to ContextList.Count - 1 do
  begin
    Ctx := TLibraryContext(ContextList[I]);
    if Ctx.Handle = ContextHandle then
      exit(Ctx);
  end;
end;

function CGE_FindContextByWindow(Window: TCastleWindow): TLibraryContext;
var
  I: Integer;
  Ctx: TLibraryContext;
begin
  Result := nil;
  if (ContextList = nil) or (ContextList.Count = 0) then
    exit;
  for I := 0 to ContextList.Count - 1 do
  begin
    Ctx := TLibraryContext(ContextList[I]);
    if Ctx.Window = Window then
      exit(Ctx);
  end;
end;

function CGE_CreateContext: TLibraryContext;
begin
  Result := TLibraryContext.Create;
  Result.Handle := NextContextHandle;
  Inc(NextContextHandle);
  ContextList.Add(Result);
end;

procedure CGE_ContextDestroy(Ctx: TLibraryContext); cdecl;
var
  Index: Integer;
begin
  try
    if (Ctx = nil) or (ContextList = nil) then
      Exit;

    Index := ContextList.IndexOf(Ctx);
    if Index >= 0 then
      ContextList.Delete(Index);    // also calls Destroy on the object, as the list owns them
  except
    on E: TObject do WritelnWarning('Window', 'CGE_ContextDestroy: ' + ExceptMessage(E));
  end;
end;

{$WARN 6058 off: Ignore warning Call to subroutine "$1" marked as inline is not inlined}

{ Check that CGE_Open was called, and at least Window and Viewport are created. }
function CGE_VerifyWindow(const FromFunc: string; Ctx: TLibraryContext): boolean;
begin
  Result :=
    (Ctx <> nil) and
    (Ctx.Window <> nil) and
    (Ctx.Viewport <> nil);
  if not Result then
    WarningWrite(FromFunc + ' : CGE window not initialized (CGE_Open not called)');
end;

{ Check that CGE_LoadSceneFromFile was called,
  and at least Window and Viewport and MainScene are created. }
function CGE_VerifyScene(const FromFunc: string; Ctx: TLibraryContext): boolean;
begin
  Result :=
    (Ctx <> nil) and
    (Ctx.Window <> nil) and
    (Ctx.Viewport <> nil) and
    (Ctx.MainScene <> nil);
  {$warnings off} // using Viewport.Items.MainScene is this case is justified
  Assert((not Result) or (Ctx.Viewport.Items.MainScene = Ctx.MainScene));
  if not Result then
    WarningWrite(FromFunc + ': CGE scene not initialized (CGE_LoadSceneFromFile not called)');
end;

procedure CGE_Initialize(ApplicationConfigDirectory: PChar); cdecl;
begin
  if ContextList = nil then
    ContextList := TObjectList.Create;
  CGEApp_Initialize(ApplicationConfigDirectory);
end;

procedure CGE_Finalize(); cdecl;
begin
  CGEApp_Finalize();
  if ContextList <> nil then
  begin
    ContextList.Free;
    ContextList := nil;
  end;
end;

function CGE_Open(flags: cUInt32; InitialWidth, InitialHeight, Dpi: cUInt32): cInt32; cdecl;
var
  Ctx: TLibraryContext;
begin
  Result := -1;
  try
    if (flags and 1 {ecgeofSaveMemory}) > 0 then
    begin
      DefaultTriangulationSlices := 16;
      DefaultTriangulationStacks := 16;
    end;
    if (flags and 2 {ecgeofLog}) > 0 then
      InitializeLog;

    Ctx := CGE_CreateContext;

    Ctx.Window := TCastleWindow.Create(nil);
    Ctx.Viewport := TCastleAutoNavigationViewport.Create(Ctx.Window);
    Ctx.Viewport.FullSize := true;
    { AutoCamera is necessary for Viewport.Camera to follow X3D file camera,
      not only at initialization (this is done by AssignDefaultCamera) but also
      when new viewpoint node is bound using X3D events or
      TCastleSceneCore.MoveToViewpoint call. }
    Ctx.Viewport.AutoCamera := true;
    { AutoNavigation is necessary for navigation to follow routes in X3D file.
      For example when changing navigation by X3D events in
      demo-models/navigation/navigation_info_bind.x3dv , to make it affect actual
      CGE navigation. }
    Ctx.Viewport.AutoNavigation := true;
    Ctx.Window.Controls.InsertFront(Ctx.Viewport);

    Ctx.TouchNavigation := TCastleTouchNavigation.Create(Ctx.Window);
    Ctx.TouchNavigation.FullSize := true;
    Ctx.TouchNavigation.Viewport := Ctx.Viewport;
    Ctx.Window.Controls.InsertFront(Ctx.TouchNavigation);

    Ctx.PreviousNavigationType := Ctx.Viewport.NavigationType;

    Application.MainWindow := Ctx.Window;
    CGEApp_Open(InitialWidth, InitialHeight, 0, 0, 0, 0, Dpi);

    Ctx.Crosshair := TCrosshairManager.Create(Ctx);
    Result := Ctx.Handle;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Open: ' + ExceptMessage(E));
  end;
end;

procedure CGE_Close(ContextHandle: cInt32; QuitWhenNoOpenWindows: CBool); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_Close', Ctx) then exit;

    if Ctx.MainScene <> nil then
      Ctx.MainScene.OnPointingDeviceSensorsChange := nil;
    FreeAndNil(Ctx.Crosshair);

    Application.MainWindow := Ctx.Window;
    CGEApp_Close(QuitWhenNoOpenWindows);
    Application.MainWindow := nil;

    CGE_ContextDestroy(Ctx);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Close: ' + ExceptMessage(E));
  end;
end;

procedure CGE_GetOpenGLInformation(szBuffer: pchar; nBufSize: cInt32); cdecl;
var
  sText: string;
begin
  try
    sText := GLInformationString;
    StrPLCopy(szBuffer, sText, nBufSize-1);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetOpenGLInformation: ' + ExceptMessage(E));
  end;
end;

procedure CGE_GetCastleEngineVersion(szBuffer: pchar; nBufSize: cInt32); cdecl;
var
  sText: string;
begin
  try
    sText := CastleEngineVersion;
    StrPLCopy(szBuffer, sText, nBufSize-1);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetCastleEngineVersion: ' + ExceptMessage(E));
  end;
end;

procedure CGE_Resize(ContextHandle: cInt32; uiViewWidth, uiViewHeight: cUInt32); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_Resize', Ctx) then exit;
    Application.MainWindow := Ctx.Window;
    CGEApp_Resize(uiViewWidth, uiViewHeight, 0, 0, 0, 0);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Resize: ' + ExceptMessage(E));
  end;
end;

procedure CGE_Render(ContextHandle: cInt32); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_Render', Ctx) then exit;
    Application.MainWindow := Ctx.Window;
    CGEApp_Render;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Render: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SaveScreenshotToFile(ContextHandle: cInt32; szFile: pcchar); cdecl;
var
  Ctx: TLibraryContext;
  Image: TRGBImage;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_SaveScreenshotToFile', Ctx) then exit;

    // hide touch controls
    Ctx.TouchNavigation.Exists := false;

    // make screenshot
    Image := Ctx.Window.SaveScreen;
    try
      SaveImage(Image, StrPas(PChar(szFile)));
    finally FreeAndNil(Image) end;

    // restore hidden controls
    Ctx.TouchNavigation.Exists := true;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SaveScreenshotToFile: ' + ExceptMessage(E));
  end;
end;

function CGE_InternalLibraryCallback(eCode, iParam1, iParam2: cInt32; szParam: pcchar): cInt32; cdecl;
var
  Ctx: TLibraryContext;
  Window: TCastleWindow;  // this should be a function parameter
  I: Integer;
begin
  Window := Application.MainWindow; // TODO: extend TLibraryCallbackProc with Window (Sender) parameter
  if Window = nil then
  begin
    // when Window is nil, pass to all callbacks
    for I := 0 to ContextList.Count - 1 do
    begin
      Ctx := TLibraryContext(ContextList[I]);
      if Assigned(Ctx.LibraryCallbackProc) then
        Ctx.LibraryCallbackProc(-1, eCode, iParam1, iParam2, szParam);
    end;
    Result := 0;
    exit;
  end;
  Ctx := CGE_FindContextByWindow(Window);
  if (Ctx <> nil) and Assigned(Ctx.LibraryCallbackProc) then
    Result := Ctx.LibraryCallbackProc(Ctx.Handle, eCode, iParam1, iParam2, szParam)
  else
    Result := 0;
end;

procedure CGE_SetLibraryCallbackProc(ContextHandle: cInt32; aProc: TCgeLibraryCallbackProc); cdecl;
var
  Ctx: TLibraryContext;
begin
  Ctx := CGE_FindContextByHandle(ContextHandle);
  if not CGE_VerifyWindow('CGE_SetLibraryCallbackProc', Ctx) then exit;
  Ctx.LibraryCallbackProc := aProc;
  CGEApp_SetLibraryCallbackProc(@CGE_InternalLibraryCallback);
end;

procedure CGE_Update(ContextHandle: cInt32); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_Update', Ctx) then exit;

    { Call LibraryCallbackProc(ecgelibNavigationTypeChanged,...) when necessary.
      For this, we just query the Viewport.NavigationType every frame. }
    if Ctx.PreviousNavigationType <> Ctx.Viewport.NavigationType then
    begin
      Ctx.PreviousNavigationType := Ctx.Viewport.NavigationType;
      if Assigned(Ctx.LibraryCallbackProc) then
      begin
        case Ctx.Viewport.NavigationType of
          ntWalk     : Ctx.LibraryCallbackProc(Ctx.Handle, ecgelibNavigationTypeChanged, ecgenavWalk     , 0, nil);
          ntFly      : Ctx.LibraryCallbackProc(Ctx.Handle, ecgelibNavigationTypeChanged, ecgenavFly      , 0, nil);
          ntExamine  : Ctx.LibraryCallbackProc(Ctx.Handle, ecgelibNavigationTypeChanged, ecgenavExamine  , 0, nil);
          ntTurntable: Ctx.LibraryCallbackProc(Ctx.Handle, ecgelibNavigationTypeChanged, ecgenavTurntable, 0, nil);
          ntNone     : Ctx.LibraryCallbackProc(Ctx.Handle, ecgelibNavigationTypeChanged, ecgenavNone     , 0, nil);
          // nt2D: TODO
          else WritelnWarning('Window', 'Current NavigationType cannot be expressed as enum for ecgelibNavigationTypeChanged');
        end;
      end;
    end;

    { Set Cursor = mcHand when we're over or keeping active
      some pointing-device sensors. The engine doesn't do it automatically
      (after https://github.com/castle-engine/castle-engine/commit/5b2810d9ef2fd0f851bc50b0a6aa7b414381dd2c )
      but it makes total sense for X3D viewers with single viewport and single
      TCastleScene. }
    if (Ctx.MainScene <> nil) and
      ( ( (Ctx.MainScene.PointingDeviceSensors <> nil) and
          (Ctx.MainScene.PointingDeviceSensors.EnabledCount <> 0)
        ) or
        (Ctx.MainScene.PointingDeviceActiveSensors.Count <> 0)
      ) then
      Ctx.Viewport.Cursor := mcHand
    else
      Ctx.Viewport.Cursor := mcDefault;

    Application.MainWindow := Ctx.Window;
    CGEApp_Update;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Update: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MouseDown(ContextHandle: cInt32; X, Y: CInt32; bLeftBtn: cBool; FingerIndex: CInt32); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_MouseDown', Ctx) then exit;
    Application.MainWindow := Ctx.Window;
    CGEApp_MouseDown(X, Y, bLeftBtn, FingerIndex);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MouseDown: ' + ExceptMessage(E));
  end;
end;

procedure CGE_Motion(ContextHandle: cInt32; X, Y: CInt32; FingerIndex: CInt32); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_Motion', Ctx) then exit;
    Application.MainWindow := Ctx.Window;
    CGEApp_Motion(X, Y, FingerIndex);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Motion: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MouseUp(ContextHandle: cInt32; X, Y: cInt32; bLeftBtn: cBool;
  FingerIndex: CInt32); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_MouseUp', Ctx) then exit;
    Application.MainWindow := Ctx.Window;
    CGEApp_MouseUp(X, Y, bLeftBtn, FingerIndex);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MouseUp: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MouseWheel(ContextHandle: cInt32; zDelta: cFloat; bVertical: cBool); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_MouseWheel', Ctx) then exit;
    // TODO: no corresponding CGEApp callback, as not implemented in iOS code
    // (in ios_tested not used anyway, because USE_GESTURE_RECOGNIZERS
    // undefined, and also --- pinch is not really a mouse wheel)
    Ctx.Window.LibraryMouseWheel(zDelta/120, bVertical);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MouseWheel: ' + ExceptMessage(E));
  end;
end;

procedure CGE_KeyDown(ContextHandle: cInt32; eKey: CInt32); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_KeyDown', Ctx) then exit;
    Application.MainWindow := Ctx.Window;
    CGEApp_KeyDown(eKey);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_KeyDown: ' + ExceptMessage(E));
  end;
end;

procedure CGE_KeyUp(ContextHandle: cInt32; eKey: CInt32); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_KeyUp', Ctx) then exit;
    Application.MainWindow := Ctx.Window;
    CGEApp_KeyUp(eKey);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_KeyUp: ' + ExceptMessage(E));
  end;
end;

procedure CGE_LoadSceneFromFile(ContextHandle: cInt32; szFile: pcchar); cdecl;
var
  Ctx: TLibraryContext;
begin
  Ctx := CGE_FindContextByHandle(ContextHandle);
  if (Ctx = nil) or (Ctx.Window = nil) then exit;
  try
    FreeAndNil(Ctx.MainScene); // if any previous scene exists, remove it

    Ctx.MainScene := TCastleScene.Create(Ctx.Window);
    Ctx.MainScene.Load(StrPas(PChar(szFile)));
    Ctx.MainScene.PreciseCollisions := true;
    Ctx.MainScene.ProcessEvents := true;
    Ctx.MainScene.ListenPressRelease := true; // necessary to pass keys to X3D sensors
    Ctx.Viewport.Items.Add(Ctx.MainScene);
    { While CGE deprecated Items.MainScene, it is justified and recommended
      solution in this case, to make MainScene affect various things
      (skybox, fog, camera, navigation etc.). }
    {$warnings off}
    Ctx.Viewport.Items.MainScene := Ctx.MainScene;
    {$warnings on}

    Ctx.Viewport.AssignDefaultCamera;
    Ctx.Viewport.AssignDefaultNavigation;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_LoadSceneFromFile: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SaveSceneToFile(ContextHandle: cInt32; szFile: pcchar; eUrlProcessing: cInt32); cdecl;
var
  SaveFileName: string;
  UrlProcessing: TUrlProcessing;
  RootNodeCopy: TX3DRootNode;
  SaveOptions: TCastleSceneSaveOptions;
  Ctx: TLibraryContext;
begin
  Ctx := CGE_FindContextByHandle(ContextHandle);
  if not CGE_VerifyScene('CGE_SaveSceneToFile', Ctx) then
    exit;
  try
    SaveFileName := StrPas(PChar(szFile));
    case eUrlProcessing of
      0: UrlProcessing := suNone;
      1: UrlProcessing := suChangeCastleDataToRelative;
      2: UrlProcessing := suChangeAllPathsToRelative;
      3: UrlProcessing := suEmbedResources;
      4: UrlProcessing := suCopyResourcesToSubdirectory;
      else raise EInternalError.CreateFmt('CGE_SaveSceneToFile: Invalid URL processing mode %d', [eUrlProcessing]);
    end;
    if UrlProcessing = suNone then
    begin
      Ctx.MainScene.Save(SaveFileName)
    end else
    begin
      RootNodeCopy := Ctx.MainScene.RootNode.DeepCopy as TX3DRootNode;
      try
        ProcessUrls(RootNodeCopy, SaveFileName, UrlProcessing);
        SaveOptions := TCastleSceneSaveOptions.Create(nil);
        try
          SaveOptions.Generator := 'Castle Game Engine (library)';
          SaveNode(RootNodeCopy, SaveFileName, SaveOptions);
        finally
          FreeAndNil(SaveOptions);
        end;
      finally
        FreeAndNil(RootNodeCopy);
      end;
    end;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SaveSceneToFile: ' + ExceptMessage(E));
  end;
end;

function CGE_GetViewpointsCount(ContextHandle: cInt32): cInt32; cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_GetViewpointsCount', Ctx) then
    begin
      Result := 0;
      exit;
    end;

    Result := Ctx.MainScene.ViewpointsCount;
  except
    on E: TObject do
    begin
      WritelnLog('Window', 'CGE_GetViewpointsCount: ' + ExceptMessage(E));
      Result := 0;
    end;
  end;
end;

procedure CGE_GetViewpointName(ContextHandle: cInt32; iViewpointIdx: cInt32; szName: pchar; nBufSize: cInt32); cdecl;
var
  Ctx: TLibraryContext;
  sName: string;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_GetViewpointName', Ctx) then exit;

    sName := Ctx.MainScene.GetViewpointName(iViewpointIdx);
    StrPLCopy(szName, sName, nBufSize-1);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetViewpointName: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MoveToViewpoint(ContextHandle: cInt32; iViewpointIdx: cInt32; bAnimated: cBool); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_MoveToViewpoint', Ctx) then exit;

    Ctx.MainScene.MoveToViewpoint(iViewpointIdx, bAnimated);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MoveToViewpoint: ' + ExceptMessage(E));
  end;
end;

procedure CGE_AddViewpointFromCurrentView(ContextHandle: cInt32; szName: pcchar); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_AddViewpointFromCurrentView', Ctx) then exit;

    Ctx.MainScene.AddViewpointFromNavigation(
      Ctx.Viewport.RequiredNavigation, StrPas(PChar(szName)));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_AddViewpointFromCurrentView: ' + ExceptMessage(E));
  end;
end;

procedure CGE_GetBoundingBox(ContextHandle: cInt32; pfXMin, pfXMax, pfYMin, pfYMax, pfZMin, pfZMax: pcfloat); cdecl;
var
  Ctx: TLibraryContext;
  BBox: TBox3D;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_GetBoundingBox', Ctx) then exit;

    BBox := Ctx.MainScene.BoundingBox;
    pfXMin^ := BBox.Data[0].X; pfXMax^ := BBox.Data[1].X;
    pfYMin^ := BBox.Data[0].Y; pfYMax^ := BBox.Data[1].Y;
    pfZMin^ := BBox.Data[0].Z; pfZMax^ := BBox.Data[1].Z;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetBoundingBox: ' + ExceptMessage(E));
  end;
end;

procedure CGE_GetViewCoords(ContextHandle: cInt32; pfPosX, pfPosY, pfPosZ, pfDirX, pfDirY, pfDirZ,
                            pfUpX, pfUpY, pfUpZ, pfGravX, pfGravY, pfGravZ: pcfloat); cdecl;
var
  Ctx: TLibraryContext;
  Pos, Dir, Up, GravityUp: TVector3;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_GetViewCoords', Ctx) then exit;

    Ctx.Viewport.Camera.GetWorldView(Pos, Dir, Up);
    GravityUp := Ctx.Viewport.Camera.GravityUp;
    pfPosX^ := Pos.X; pfPosY^ := Pos.Y; pfPosZ^ := Pos.Z;
    pfDirX^ := Dir.X; pfDirY^ := Dir.Y; pfDirZ^ := Dir.Z;
    pfUpX^ := Up.X; pfUpY^ := Up.Y; pfUpZ^ := Up.Z;
    pfGravX^ := GravityUp.X; pfGravY^ := GravityUp.Y; pfGravZ^ := GravityUp.Z;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetViewCoords: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MoveViewToCoords(ContextHandle: cInt32; fPosX, fPosY, fPosZ, fDirX, fDirY, fDirZ,
                               fUpX, fUpY, fUpZ, fGravX, fGravY, fGravZ: cFloat;
                               bAnimated: cBool); cdecl;
var
  Ctx: TLibraryContext;
  Pos, Dir, Up, GravityUp: TVector3;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_MoveViewToCoords', Ctx) then exit;

    Pos.X := fPosX; Pos.Y := fPosY; Pos.Z := fPosZ;
    Dir.X := fDirX; Dir.Y := fDirY; Dir.Z := fDirZ;
    Up.X := fUpX; Up.Y := fUpY; Up.Z := fUpZ;
    GravityUp.X := fGravX; GravityUp.Y := fGravY; GravityUp.Z := fGravZ;
    if bAnimated then
      Ctx.Viewport.Camera.AnimateTo(Pos, Dir, Up, 0.5)
    else
      Ctx.Viewport.Camera.SetWorldView(Pos, Dir, Up);
    Ctx.Viewport.Camera.GravityUp := GravityUp;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MoveViewToCoords: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNavigationInputShortcut(ContextHandle: cInt32; eInput, eKey1, eKey2,
                               eMouseButton, eMouseWheel: cInt32); cdecl;
var
  Ctx: TLibraryContext;
  Nav: TCastleNavigation;
  WalkNavigation: TCastleWalkNavigation;
  ExamineNavigation: TCastleExamineNavigation;
  InputShortcut: TInputShortcut;
  InKey1: TKey;
  InKey2: TKey = keyNone;
  InKeyString: String = '';
  InMouseButtonUse: boolean;
  InMouseButton: TCastleMouseButton;
  InMouseWheel: TMouseWheelDirection;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_SetNavigationInputShortcut', Ctx) then exit;

    InKey1 := TKey(eKey1);
    InKey2 := TKey(eKey2);
    InMouseButtonUse := (eMouseButton <> 0);
    case eMouseButton of
      0: InMouseButton := buttonLeft;
      1: InMouseButton := buttonLeft;
      2: InMouseButton := buttonMiddle;
      3: InMouseButton := buttonRight;
      4: InMouseButton := buttonExtra1;
      5: InMouseButton := buttonExtra2;
    end;
    case eMouseWheel of
      0: InMouseWheel := mwNone;
      1: InMouseWheel := mwUp;
      2: InMouseWheel := mwDown;
      3: InMouseWheel := mwLeft;
      4: InMouseWheel := mwRight;
    end;

    InputShortcut := nil;
    Nav := Ctx.Viewport.RequiredNavigation;
    if Nav is TCastleWalkNavigation then
    begin
      WalkNavigation := TCastleWalkNavigation(Nav);
      case eInput of
        1: InputShortcut := WalkNavigation.Input_ZoomIn;
        2: InputShortcut := WalkNavigation.Input_ZoomOut;
        11: InputShortcut := WalkNavigation.Input_Forward;
        12: InputShortcut := WalkNavigation.Input_Backward;
        13: InputShortcut := WalkNavigation.Input_LeftRotate;
        14: InputShortcut := WalkNavigation.Input_RightRotate;
        15: InputShortcut := WalkNavigation.Input_LeftStrafe;
        16: InputShortcut := WalkNavigation.Input_RightStrafe;
        17: InputShortcut := WalkNavigation.Input_UpRotate;
        18: InputShortcut := WalkNavigation.Input_DownRotate;
        19: InputShortcut := WalkNavigation.Input_IncreasePreferredHeight;
        20: InputShortcut := WalkNavigation.Input_DecreasePreferredHeight;
        21: InputShortcut := WalkNavigation.Input_GravityUp;
        22: InputShortcut := WalkNavigation.Input_Run;
        23: InputShortcut := WalkNavigation.Input_MoveSpeedInc;
        24: InputShortcut := WalkNavigation.Input_MoveSpeedDec;
        25: InputShortcut := WalkNavigation.Input_Jump;
        26: InputShortcut := WalkNavigation.Input_Crouch;
        else raise EInternalError.CreateFmt('CGE_SetNavigationInputShortcut: Invalid input type %d for walk navigation', [eInput]);
      end;
      if InputShortcut <> nil then
        InputShortcut.Assign(InKey1, InKey2, InKeyString, InMouseButtonUse, InMouseButton, InMouseWheel);
    end
    else if Nav is TCastleExamineNavigation then
    begin
      ExamineNavigation := TCastleExamineNavigation(Nav);
      case eInput of
        1: InputShortcut := ExamineNavigation.Input_ZoomIn;
        2: InputShortcut := ExamineNavigation.Input_ZoomOut;
        31: InputShortcut := ExamineNavigation.Input_Rotate;
        32: InputShortcut := ExamineNavigation.Input_Move;
        33: InputShortcut := ExamineNavigation.Input_Zoom;
        else raise EInternalError.CreateFmt('CGE_SetNavigationInputShortcut: Invalid input type %d for examine navigation', [eInput]);
      end;
      if InputShortcut <> nil then
        InputShortcut.Assign(InKey1, InKey2, InKeyString, InMouseButtonUse, InMouseButton, InMouseWheel);
    end;
  except
    on E: TObject do WritelnLog('Window', 'CGE_SetNavigationInputShortcut: ' + ExceptMessage(E));
  end;
end;

function CGE_GetNavigationType(ContextHandle: cInt32): cInt32; cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_GetNavigationType', Ctx) then Exit(-1);

    case Ctx.Viewport.NavigationType of
      ntWalk     : Result := 0;
      ntFly      : Result := 1;
      ntExamine  : Result := 2;
      ntTurntable: Result := 3;
      ntNone     : Result := 4;
      // nt2D: TODO
      else raise EInternalError.Create('CGE_GetNavigationType: Unrecognized Viewport.NavigationType');
    end;
  except
    on E: TObject do
    begin
      WritelnLog('Window', 'CGE_GetNavigationType: ' + ExceptMessage(E));
      Result := -1;
    end;
  end;
end;

procedure CGE_SetNavigationType(ContextHandle: cInt32; NewType: cInt32); cdecl;
var
  Ctx: TLibraryContext;
  aNavType: TNavigationType;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyWindow('CGE_SetNavigationType', Ctx) then exit;

    case NewType of
      0: aNavType := ntWalk;
      1: aNavType := ntFly;
      2: aNavType := ntExamine;
      3: aNavType := ntTurntable;
      4: aNavType := ntNone;
      // TODO: aNavType := nt2D;
      else raise EInternalError.CreateFmt('CGE_SetNavigationType: Invalid navigation type %d', [NewType]);
    end;
    Ctx.Viewport.NavigationType := aNavType;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNavigationType: ' + ExceptMessage(E));
  end;
end;

function cgehelper_TouchInterfaceFromConst(eMode: cInt32): TTouchInterface;
begin
  case eMode of
    0: Result := tiNone;
    1: Result := tiWalk;
    2: Result := tiWalkRotate;
    3: Result := tiFlyWalk;
    4: Result := tiPan;
    else raise EInternalError.CreateFmt('cgehelper_TouchInterfaceFromConst: Invalid touch interface mode %d', [eMode]);
  end;
end;

function cgehelper_ConstFromTouchInterface(eMode: TTouchInterface): cInt32;
begin
  Result := 0;
  case eMode of
    tiWalk: Result := 1;
    tiWalkRotate: Result := 2;
    tiFlyWalk: Result := 3;
    tiPan: Result := 4;
  end;
end;

procedure CGE_SetTouchInterface(ContextHandle: cInt32; eMode: cInt32); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if Ctx = nil then exit;
    Ctx.TouchNavigation.TouchInterface := cgehelper_TouchInterfaceFromConst(eMode);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetTouchInterface: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetAutoTouchInterface(ContextHandle: cInt32; bAutomaticTouchInterface: cBool); cdecl;
var
  Ctx: TLibraryContext;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if Ctx = nil then exit;
    Ctx.TouchNavigation.AutoTouchInterface := bAutomaticTouchInterface;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetAutoTouchInterface: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetWalkNavigationMouseDragMode(ContextHandle: cInt32; eMode: cInt32); cdecl;
var
  Ctx: TLibraryContext;
  NewMode: TMouseDragMode;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if Ctx = nil then exit;
    case eMode of
      0: NewMode := mdWalkRotate;
      1: NewMode := mdRotate;
      2: NewMode := mdNone;
      else raise EInternalError.CreateFmt('Invalid MouseDragMode mode %d', [eMode]);
    end;
    Ctx.Viewport.InternalWalkNavigation.MouseDragMode := NewMode;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetWalkNavigationMouseDragMode: ' + ExceptMessage(E));
  end;
end;

procedure CGE_IncreaseSceneTime(ContextHandle: cInt32; fTimeS: cFloat); cdecl;
var
  Ctx: TLibraryContext;
  DummyRemoveType: TRemoveType;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if Ctx = nil then exit;

    Ctx.MainScene.IncreaseTime(fTimeS);
    DummyRemoveType := rtNone;
    Ctx.Viewport.Camera.Update(fTimeS, DummyRemoveType);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_IncreaseSceneTime: ' + ExceptMessage(E));
  end;
end;

function GetWalkNavigation(Ctx: TLibraryContext): TCastleWalkNavigation;
var
  Nav: TCastleNavigation;
begin
  Nav := Ctx.Viewport.RequiredNavigation;
  if Nav is TCastleWalkNavigation then
    Result := TCastleWalkNavigation(Nav)
  else
    Result := nil;
end;

procedure CGE_SetVariableInt(ContextHandle: cInt32; eVar: cInt32; nValue: cInt32); cdecl;
var
  Ctx: TLibraryContext;
  WalkNavigation: TCastleWalkNavigation;
  NewUIScaling: TUIScaling;
begin
  Ctx := CGE_FindContextByHandle(ContextHandle);
  if (Ctx = nil) or (Ctx.Window = nil) then exit;
  try
    case eVar of
      0: begin    // ecgevarWalkHeadBobbing
           WalkNavigation := GetWalkNavigation(Ctx);
           if WalkNavigation <> nil then
           begin
             if nValue > 0 then
               WalkNavigation.HeadBobbing := TCastleWalkNavigation.DefaultHeadBobbing
             else
               WalkNavigation.HeadBobbing := 0.0;
           end;
         end;

      1: begin    // ecgevarEffectSSAO
           if Ctx.Viewport.ScreenSpaceAmbientOcclusionAvailable then
             Ctx.Viewport.ScreenSpaceAmbientOcclusion := (nValue > 0);
         end;

      2: begin    // ecgevarMouseLook
           WalkNavigation := GetWalkNavigation(Ctx);
           if WalkNavigation <> nil then
               WalkNavigation.MouseLook := (nValue > 0);
         end;

      3: begin    // ecgevarCrossHair
           Ctx.Crosshair.CrosshairCtl.Exists := (nValue > 0);
           if nValue > 0 then
           begin
             if nValue = 2 then
               Ctx.Crosshair.CrosshairCtl.Shape := csCrossRect
             else
               Ctx.Crosshair.CrosshairCtl.Shape := csCross;
             Ctx.Crosshair.UpdateCrosshairImage;
             Ctx.MainScene.OnPointingDeviceSensorsChange := @Ctx.Crosshair.OnPointingDeviceSensorsChange;
           end;
         end;

      5: begin    // ecgevarAutoWalkTouchInterface
           Ctx.TouchNavigation.AutoWalkTouchInterface := cgehelper_TouchInterfaceFromConst(nValue);
         end;

      6: begin    // ecgevarScenePaused
           Ctx.Viewport.Items.Paused := (nValue > 0);
         end;

      7: begin    // ecgevarAutoRedisplay
           Ctx.Window.AutoRedisplay := (nValue > 0);
         end;

      8: begin    // ecgevarHeadlight
           if Ctx.MainScene <> nil then
              Ctx.MainScene.HeadlightOn := (nValue > 0);
         end;

      9: begin    // ecgevarOcclusionCulling
           if Ctx.Viewport <> nil then
              Ctx.Viewport.OcclusionCulling := (nValue > 0);
         end;

      10: begin    // ecgevarPhongShading
            if Ctx.MainScene <> nil then
               Ctx.MainScene.RenderOptions.PhongShading := (nValue > 0);
          end;

      11: begin    // ecgevarPreventInfiniteFallingDown
            Ctx.Viewport.PreventInfiniteFallingDown := (nValue > 0);
          end;

      12: begin    // ecgevarUIScaling
            case nValue of
              0: NewUIScaling := usNone;
              1: NewUIScaling := usEncloseReferenceSize;
              2: NewUIScaling := usEncloseReferenceSizeAutoOrientation;
              3: NewUIScaling := usFitReferenceSize;
              4: NewUIScaling := usExplicitScale;
              5: NewUIScaling := usDpiScale;
              else raise EInternalError.CreateFmt('Invalid UIScaling mode %d', [nValue]);
            end;
            Ctx.Window.Container.UIScaling := NewUIScaling;
          end;
    end;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetVariableInt: ' + ExceptMessage(E));
  end;
end;

function CGE_GetVariableInt(ContextHandle: cInt32; eVar: cInt32): cInt32; cdecl;
var
  Ctx: TLibraryContext;
  WalkNavigation: TCastleWalkNavigation;
begin
  Result := -1;
  Ctx := CGE_FindContextByHandle(ContextHandle);
  if (Ctx = nil) or (Ctx.Window = nil) then exit;
  try
    case eVar of
      0: begin    // ecgevarWalkHeadBobbing
           WalkNavigation := GetWalkNavigation(Ctx);
           if (WalkNavigation <> nil) and (WalkNavigation.HeadBobbing > 0) then
             Result := 1
           else
             Result := 0;
         end;

      1: begin    // ecgevarEffectSSAO
           if Ctx.Viewport.ScreenSpaceAmbientOcclusionAvailable and
              Ctx.Viewport.ScreenSpaceAmbientOcclusion then
             Result := 1
           else
             Result := 0;
         end;

      2: begin    // ecgevarMouseLook
           WalkNavigation := GetWalkNavigation(Ctx);
           if (WalkNavigation <> nil) and WalkNavigation.MouseLook then
             Result := 1
           else
             Result := 0;
         end;

      3: begin    // ecgevarCrossHair
           if not Ctx.Crosshair.CrosshairCtl.Exists then
             Result := 0
           else
           if Ctx.Crosshair.CrosshairCtl.Shape = csCross then
             Result := 1
           else
           if Ctx.Crosshair.CrosshairCtl.Shape = csCrossRect then
             Result := 2
           else
             Result := 1;
         end;

      4: begin    // ecgevarAnimationRunning
           if Ctx.Viewport.Camera.Animation then
             Result := 1
           else
             Result := 0;
         end;

      5: begin    // ecgevarAutoWalkTouchInterface
           Result := cgehelper_ConstFromTouchInterface(Ctx.TouchNavigation.AutoWalkTouchInterface);
         end;

      6: begin    // ecgevarScenePaused
           if Ctx.Viewport.Items.Paused then
             Result := 1
           else
             Result := 0;
         end;

      7: begin    // ecgevarAutoRedisplay
           if Ctx.Window.AutoRedisplay then
             Result := 1
           else
             Result := 0;
         end;

      8: begin    // ecgevarHeadlight
           if (Ctx.MainScene <> nil) and Ctx.MainScene.HeadlightOn then
             Result := 1
           else
             Result := 0;
         end;

      9: begin    // ecgevarOcclusionCulling
           if (Ctx.Viewport <> nil) and Ctx.Viewport.OcclusionCulling then
             Result := 1
           else
             Result := 0;
         end;

      10: begin    // ecgevarPhongShading
            if (Ctx.MainScene <> nil) and Ctx.MainScene.RenderOptions.PhongShading then
              Result := 1 else
              Result := 0;
          end;

      11: begin    // ecgevarPreventInfiniteFallingDown
            if Ctx.Viewport.PreventInfiniteFallingDown then
              Result := 1 else
              Result := 0;
          end;

      12: begin    // ecgevarUIScaling
            case Ctx.Window.Container.UIScaling of
              usNone:                 Result := 0;
              usEncloseReferenceSize: Result := 1;
              usEncloseReferenceSizeAutoOrientation: Result := 2;
              usFitReferenceSize:     Result := 3;
              usExplicitScale:        Result := 4;
              usDpiScale:             Result := 5;
              else Result := 0;
            end;
          end;

      else Result := -1; // unsupported variable
    end;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetVariableInt: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFFloat(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; value: cFloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFFloat', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFFloat).Send(value);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFFloat: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFDouble(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; value: cDouble); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFDouble', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFDouble).Send(value);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFDouble: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFInt32(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; value: cInt32); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFInt32', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFInt32).Send(value);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFInt32: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFBool(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; value: cBool); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFBool', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFBool).Send(value);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFBool: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFString(ContextHandle: cInt32; szNodeName, szFieldName, szValue: pcchar); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFString', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFString).Send(PChar(szValue));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFString: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFVec2f(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; val1, val2: cFloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFVec2f', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFVec2f).Send(Vector2(val1, val2));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFVec2f: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFVec3f(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; val1, val2, val3: cFloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFVec3f', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFVec3f).Send(Vector3(val1, val2, val3));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFVec3f: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFVec4f(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; val1, val2, val3, val4: cFloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFVec4f', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFVec4f).Send(Vector4(val1, val2, val3, val4));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFVec4f: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFVec2d(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; val1, val2: cDouble); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFVec2d', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFVec2d).Send(Vector2Double(val1, val2));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFVec2d: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFVec3d(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; val1, val2, val3: cDouble); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFVec3d', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFVec3d).Send(Vector3Double(val1, val2, val3));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFVec3d: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFVec4d(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; val1, val2, val3, val4: cDouble); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFVec4d', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFVec4d).Send(Vector4Double(val1, val2, val3, val4));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFVec4d: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_SFRotation(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; axisX, axisY, axisZ, rotation: cFloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_SFRotation', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField <> nil then
       (aField as TSFRotation).Send(Vector4(axisX, axisY, axisZ, rotation));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_SFRotation: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_MFFloat(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcfloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TSingleList;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFFloat', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TSingleList.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(Single) * iCount);
    (aField as TMFFloat).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFFloat: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_MFDouble(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcdouble); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TDoubleList;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFDouble', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TDoubleList.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(Double) * iCount);
    (aField as TMFDouble).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFDouble: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_MFInt32(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcInt32); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TInt32List;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFInt32', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TInt32List.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(Int32) * iCount);
    (aField as TMFInt32).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFInt32: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue_MFBool(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcbool); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TBooleanList;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFBool', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TBooleanList.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(boolean) * iCount);
    (aField as TMFBool).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFBool: ' + ExceptMessage(E));
  end;
end;

// Set MFVec2f. We expect "2 * count" floats in the array "values"
procedure CGE_SetNodeFieldValue_MFVec2f(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcfloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TVector2List;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFVec2f', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TVector2List.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(TVector2) * iCount);
    (aField as TMFVec2f).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFVec2f: ' + ExceptMessage(E));
  end;
end;

// Set MFVec3f. We expect "3 * count" floats in the array "values"
procedure CGE_SetNodeFieldValue_MFVec3f(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcfloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TVector3List;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFVec3f', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TVector3List.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(TVector3) * iCount);
    (aField as TMFVec3f).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFVec3f: ' + ExceptMessage(E));
  end;
end;

// Set MFVec4f. We expect "4 * count" floats in the array "values"
procedure CGE_SetNodeFieldValue_MFVec4f(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcfloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TVector4List;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFVec4f', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TVector4List.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(TVector4) * iCount);
    (aField as TMFVec4f).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFVec4f: ' + ExceptMessage(E));
  end;
end;

// Set MFVec2f. We expect "2 * count" doubles in the array "values"
procedure CGE_SetNodeFieldValue_MFVec2d(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcdouble); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TVector2DoubleList;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFVec2d', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TVector2DoubleList.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(TVector2Double) * iCount);
    (aField as TMFVec2d).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFVec2d: ' + ExceptMessage(E));
  end;
end;

// Set MFVec3f. We expect "3 * count" doubles in the array "values"
procedure CGE_SetNodeFieldValue_MFVec3d(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcdouble); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TVector3DoubleList;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFVec3d', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TVector3DoubleList.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(TVector3Double) * iCount);
    (aField as TMFVec3d).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFVec3d: ' + ExceptMessage(E));
  end;
end;

// Set MFVec4f. We expect "4 * count" doubles in the array "values"
procedure CGE_SetNodeFieldValue_MFVec4d(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcdouble); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TVector4DoubleList;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFVec4d', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TVector4DoubleList.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(TVector4Double) * iCount);
    (aField as TMFVec4d).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFVec4d: ' + ExceptMessage(E));
  end;
end;

// Set MFRotation. We expect "4 * count" floats in the array "values"
procedure CGE_SetNodeFieldValue_MFRotation(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: pcfloat); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TVector4List;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFRotation', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TVector4List.Create;
    aItemList.Count := iCount;
    Move(values^, aItemList.L^, SizeOf(TVector4) * iCount);
    (aField as TMFRotation).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFRotation: ' + ExceptMessage(E));
  end;
end;

// Set MFString. We expect array of "count" char* pointers to null-terminated UTF-8 strings
procedure CGE_SetNodeFieldValue_MFString(ContextHandle: cInt32; szNodeName, szFieldName: pcchar; iCount: cInt32; values: ppcchar); cdecl;
var
  Ctx: TLibraryContext;
  aField: TX3DField;
  aItemList: TCastleStringList;
  i: cInt32;
begin
  try
    Ctx := CGE_FindContextByHandle(ContextHandle);
    if not CGE_VerifyScene('CGE_SetNodeFieldValue_MFString', Ctx) then exit;
    aField := Ctx.MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    aItemList := TCastleStringList.Create;
    aItemList.Count := iCount;
    for i := 0 to iCount - 1 do
      aItemList[i] := PChar(values[i]);
    (aField as TMFString).Send(aItemList);
    aItemList.Destroy;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue_MFString: ' + ExceptMessage(E));
  end;
end;

constructor TCrosshairManager.Create(const AOwner: TLibraryContext);
begin
  inherited Create;
  FOwnerCtx := AOwner;
  CrosshairCtl := TCastleCrosshair.Create(FOwnerCtx.Window);
  CrosshairCtl.Exists := false;  // start as invisible
  FOwnerCtx.Window.Controls.InsertFront(CrosshairCtl);
end;

destructor TCrosshairManager.Destroy;
begin
  FOwnerCtx.Window.Controls.Remove(CrosshairCtl);
  FreeAndNil(CrosshairCtl);
  inherited;
end;

procedure TCrosshairManager.UpdateCrosshairImage;
begin
  begin
    if not CrosshairCtl.Exists then Exit;

    if CrosshairActive then
      CrosshairCtl.Shape := csCrossRect else
      CrosshairCtl.Shape := csCross;
  end;
end;

procedure TCrosshairManager.OnPointingDeviceSensorsChange(Sender: TObject);
var
  OverSensor: Boolean;
  SensorList: TPointingDeviceSensorList;
begin
  { check if the crosshair (mouse) is over any sensor }
  OverSensor := false;
  SensorList := FOwnerCtx.MainScene.PointingDeviceSensors;
  if (SensorList <> nil) then
    OverSensor := (SensorList.EnabledCount>0);

  if CrosshairActive <> OverSensor then
  begin
    CrosshairActive := OverSensor;
    UpdateCrosshairImage;
  end;
end;

exports
  CGE_Initialize,
  CGE_Finalize,
  CGE_Open,
  CGE_Close,
  CGE_GetOpenGLInformation,
  CGE_GetCastleEngineVersion,
  CGE_Render,
  CGE_Resize,
  CGE_SetLibraryCallbackProc,
  CGE_Update,
  CGE_MouseDown,
  CGE_Motion,
  CGE_MouseUp,
  CGE_MouseWheel,
  CGE_KeyDown,
  CGE_KeyUp,
  CGE_LoadSceneFromFile,
  CGE_SaveSceneToFile,
  CGE_SetNavigationInputShortcut,
  CGE_GetNavigationType,
  CGE_SetNavigationType,
  CGE_GetViewpointsCount,
  CGE_GetViewpointName,
  CGE_MoveToViewpoint,
  CGE_AddViewpointFromCurrentView,
  CGE_GetBoundingBox,
  CGE_GetViewCoords,
  CGE_MoveViewToCoords,
  CGE_SaveScreenshotToFile,
  CGE_SetTouchInterface,
  CGE_SetAutoTouchInterface,
  CGE_SetWalkNavigationMouseDragMode,
  CGE_IncreaseSceneTime,
  CGE_SetVariableInt,
  CGE_GetVariableInt,
  CGE_SetNodeFieldValue_SFFloat,
  CGE_SetNodeFieldValue_SFDouble,
  CGE_SetNodeFieldValue_SFInt32,
  CGE_SetNodeFieldValue_SFBool,
  CGE_SetNodeFieldValue_SFVec2f,
  CGE_SetNodeFieldValue_SFVec3f,
  CGE_SetNodeFieldValue_SFVec4f,
  CGE_SetNodeFieldValue_SFVec2d,
  CGE_SetNodeFieldValue_SFVec3d,
  CGE_SetNodeFieldValue_SFVec4d,
  CGE_SetNodeFieldValue_SFRotation,
  CGE_SetNodeFieldValue_SFString,
  CGE_SetNodeFieldValue_MFFloat,
  CGE_SetNodeFieldValue_MFDouble,
  CGE_SetNodeFieldValue_MFInt32,
  CGE_SetNodeFieldValue_MFBool,
  CGE_SetNodeFieldValue_MFVec2f,
  CGE_SetNodeFieldValue_MFVec3f,
  CGE_SetNodeFieldValue_MFVec4f,
  CGE_SetNodeFieldValue_MFVec2d,
  CGE_SetNodeFieldValue_MFVec3d,
  CGE_SetNodeFieldValue_MFVec4d,
  CGE_SetNodeFieldValue_MFRotation,
  CGE_SetNodeFieldValue_MFString;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end.
