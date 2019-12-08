program CirclesDemo;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  System.Threading,
  IdContext,
  JsonDataObjects,
  WebSocketServer in 'WebSocketServer.pas',
  Circle in 'Circle.pas';

type

  TCirclesDemo = class
  private
    FServer: TWebSocketServer;

    FSendCirclesThread: ITask;
    FSendCirclesThreadWorking: boolean;

    procedure Connect(AContext: TIdContext);
    procedure Disconnect(AContext: TIdContext);
    procedure Execute(AContext: TIdContext);

    procedure SendCircles;
  public
    constructor Create;
    destructor Destroy; override;
  end;

{ TCirclesDemo }

constructor TCirclesDemo.Create;
begin
  FServer := TWebSocketServer.Create;
  FServer.DefaultPort := 8080;
  FServer.OnExecute := Execute;
  FServer.OnConnect := Connect;
  FServer.OnDisconnect := Disconnect;
  FServer.Active := true;

  FSendCirclesThreadWorking := true;
  FSendCirclesThread := TTask.Run(SendCircles);
end;

destructor TCirclesDemo.Destroy;
begin
  FSendCirclesThreadWorking := false;
  FSendCirclesThread.Wait;

  FServer.Active := false;
  FServer.DisposeOf;

  inherited;
end;

procedure TCirclesDemo.Connect(AContext: TIdContext);
begin
  Writeln('Client connected');
end;

procedure TCirclesDemo.Disconnect(AContext: TIdContext);
begin
  Writeln('Client disconnected');
end;

procedure TCirclesDemo.Execute(AContext: TIdContext);
var
  io: TWebSocketIOHandlerHelper;
  msg: string;
  JsonMsg: TJsonObject;
  Json: TJsonArray;
begin
  io := TWebSocketIOHandlerHelper(AContext.Connection.IOHandler);
  io.CheckForDataOnSource(10);
  msg := io.ReadString;
  if msg = '' then
    exit;

  try
    JsonMsg := TJsonObject(TJsonObject.Parse(msg));
  except
    JsonMsg := nil;
  end;

  if JsonMsg = nil then
    exit;

  if JsonMsg.S['act'] = 'create' then
  begin
    TCircle.Create(JsonMsg.F['x'], JsonMsg.F['y'], JsonMsg.S['color']);
    Json := TCircle.SerializeAllCircles;
    io.WriteString(Json.ToJSON);
    Json.DisposeOf;
  end;

  if JsonMsg.S['act'] = 'move' then
    TCircle.Move(JsonMsg.S['id'], JsonMsg.F['x'], JsonMsg.F['y']);

  if JsonMsg.S['act'] = 'changecolor' then
    TCircle.ChangeColorForCircle(JsonMsg.S['id']);

  if JsonMsg.S['act'] = 'destroy' then
    TCircle.DestroyCircle(JsonMsg.S['id']);

  JsonMsg.DisposeOf;
end;

procedure TCirclesDemo.SendCircles;
var
  Clients: TList;
  Json: TJsonArray;
  JsonStr: string;
  i: integer;
begin
  while FSendCirclesThreadWorking do
  begin
    if not Assigned(FServer.Contexts) then
      exit;

    Json := TCircle.SerializeAllCircles;
    JsonStr := Json.ToJSON;
    Json.DisposeOf;

    Clients := FServer.Contexts.LockList;
    try
      for i := 0 to Clients.Count - 1 do
        TWebSocketIOHandlerHelper(TIdContext(Clients[i]).Connection.IOHandler).WriteString(JsonStr);
    finally
      FServer.Contexts.UnlockList;
    end;

    sleep(100);
  end;
end;

var
  Demo: TCirclesDemo;

begin
  try
    Demo := TCirclesDemo.Create;
    readln;
    Demo.DisposeOf;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
