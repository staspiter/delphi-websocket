program WebSocketDemo;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  IdContext,
  IdSSLOpenSSL,
  WebSocketServer;

type

  TWebSocketDemo = class
  private
    FServer: TWebSocketServer;
    FSSLIOHanlder: TIdServerIOHandlerSSLOpenSSL;

    procedure Connect(AContext: TIdContext);
    procedure Disconnect(AContext: TIdContext);
    procedure Execute(AContext: TIdContext);
  public
    constructor Create;
    destructor Destroy; override;
  end;

{ TWebSocketDemo }

constructor TWebSocketDemo.Create;
begin
  FSSLIOHanlder := TIdServerIOHandlerSSLOpenSSL.Create;
  FSSLIOHanlder.SSLOptions.SSLVersions := [sslvTLSv1_2];
  FSSLIOHanlder.SSLOptions.CertFile := 'cert.crt';
  FSSLIOHanlder.SSLOptions.KeyFile := 'private.key';

  FServer := TWebSocketServer.Create;
  FServer.InitSSL(FSSLIOHanlder);
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
