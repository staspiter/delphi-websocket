program WebSocketDemo;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,

  IdContext,

  WebSocketServer in 'WebSocketServer.pas';

type

  TWebSocketDemo = class
  private
    FServer: TWebSocketServer;

    procedure Connect(AContext: TIdContext);
    procedure Disconnect(AContext: TIdContext);
    procedure Execute(AContext: TIdContext);
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  srv: TWebSocketServer;

{ TWebSocketDemo }

constructor TWebSocketDemo.Create;
begin
  FServer := TWebSocketServer.Create;
  FServer.DefaultPort := 8080;
  FServer.OnExecute := Execute;
  FServer.OnConnect := Connect;
  FServer.OnDisconnect := Disconnect;
  FServer.Active := true;
end;

destructor TWebSocketDemo.Destroy;
begin
  FServer.Active := false;
  FServer.DisposeOf;

  inherited;
end;

procedure TWebSocketDemo.Connect(AContext: TIdContext);
begin
  Writeln('Client connected');
end;

procedure TWebSocketDemo.Disconnect(AContext: TIdContext);
begin
  Writeln('Client disconnected');
end;

procedure TWebSocketDemo.Execute(AContext: TIdContext);
var
  io: TWebSocketIOHandlerHelper;
  msg: string;
begin
  io := TWebSocketIOHandlerHelper(AContext.Connection.IOHandler);
  io.CheckForDataOnSource(10);
  msg := io.ReadString;
  if msg = '' then
    exit;

  writeln(msg);

  io.WriteString(msg);
end;

var
  Demo: TWebSocketDemo;

begin
  try
    Demo := TWebSocketDemo.Create;
    readln;
    Demo.DisposeOf;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
