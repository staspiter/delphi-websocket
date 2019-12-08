unit Circle;

interface

uses
  System.SysUtils, Winapi.Windows, Vcl.Graphics, System.Generics.Collections, System.SyncObjs,

  JsonDataObjects;

type

  TCircle = class
  private class var
    FCircles: TDictionary<string, TCircle>;
    FCirclesMutex: TMutex;
  private
    FPosition: array [0..1] of single;
    FColor: string;
    FId: string;

    function Serialize: TJsonObject;
    procedure ChangeColor;
    destructor Destroy; override;
  public
    class function SerializeAllCircles: TJsonArray;
    class procedure Move(const Id: string; x, y: single);
    class procedure ChangeColorForCircle(const Id: string);
    class procedure DestroyCircle(const Id: string);

    constructor Create(x, y: single; const Color: string);

    class constructor Create;
    class destructor Destroy;
  end;

implementation

{ TCircle }

class constructor TCircle.Create;
begin
  FCircles := TDictionary<string, TCircle>.Create;
  FCirclesMutex := TMutex.Create;
end;

class destructor TCircle.Destroy;
var
  c: TCircle;
begin
  FCirclesMutex.DisposeOf;
  for c in FCircles.Values.ToArray do
    c.DisposeOf;
  FCircles.DisposeOf;
end;

constructor TCircle.Create(x, y: single; const Color: string);
var
  Guid: TGUID;
begin
  FPosition[0] := x;
  FPosition[1] := y;
  FColor := Color;

  // Generate random id as guid
  CreateGUID(Guid);
  FId := GUIDToString(Guid).Replace('{', '').Replace('}', '');

  FCirclesMutex.Acquire;
  FCircles.Add(FId, Self);
  FCirclesMutex.Release;
end;

destructor TCircle.Destroy;
begin
  FCirclesMutex.Acquire;
  FCircles.Remove(FId);
  FCirclesMutex.Release;

  inherited;
end;

function TCircle.Serialize: TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['id'] := FId;
  Result.S['color'] := FColor;
  Result.F['x'] := FPosition[0];
  Result.F['y'] := FPosition[1];
end;

class function TCircle.SerializeAllCircles: TJsonArray;
var
  CirclesArr: TArray<TCircle>;
  i: integer;
begin
  Result := TJsonArray.Create;

  FCirclesMutex.Acquire;
  CirclesArr := FCircles.Values.ToArray;
  for i := 0 to Length(CirclesArr) - 1 do
    Result.Add(CirclesArr[i].Serialize);
  FCirclesMutex.Release;
end;

class procedure TCircle.Move(const Id: string; x, y: single);
var
  c: TCircle;
begin
  FCirclesMutex.Acquire;
  if FCircles.ContainsKey(Id) then
  begin
    c := FCircles[Id];
    c.FPosition[0] := x;
    c.FPosition[1] := y;
  end;
  FCirclesMutex.Release;
end;

procedure TCircle.ChangeColor;

  function ColorToHex(Color: TColor) : string;
  begin
    Result :=
      { red value }
      IntToHex( GetRValue( Color ), 2 ) +
      { green value }
      IntToHex( GetGValue( Color ), 2 ) +
      { blue value }
      IntToHex( GetBValue( Color ), 2 );
  end;

  function GetRandomColor: TColor;
  begin
    Result := RGB(Random(100) + 100, Random(100) + 100, Random(100) + 100);
  end;

begin
  FColor := '#' + ColorToHex(GetRandomColor);
end;

class procedure TCircle.ChangeColorForCircle(const Id: string);
begin
  FCirclesMutex.Acquire;
  if FCircles.ContainsKey(Id) then
    FCircles[Id].ChangeColor;
  FCirclesMutex.Release;
end;

class procedure TCircle.DestroyCircle(const Id: string);
begin
  FCirclesMutex.Acquire;
  if FCircles.ContainsKey(Id) then
    FCircles[Id].Destroy;
  FCirclesMutex.Release;
end;

end.
