program HttpWebSocketDemo;

{$APPTYPE CONSOLE}

{$R *.res}

// Serves client.html over plain HTTP and handles WebSocket connections,
// both on the same port.
//
// Note that a browser does NOT upgrade the connection it used to fetch the
// page - it opens a second, separate TCP connection for the WebSocket. The
// HTTP connection therefore has to be closed by the server once the page has
// been sent, otherwise its Indy thread stays alive with nothing on the other
// end. That is what 'Connection: close' + Connection.Disconnect below is for.

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  IdContext,
  IdGlobal,
  WebSocketServer;

type

  THttpWebSocketDemo = class
  private
    FServer: TWebSocketServer;
    FHtml: string;

    procedure ServeHttp(AContext: TIdContext);
    procedure Execute(AContext: TIdContext);
  public
    constructor Create;
    destructor Destroy; override;
  end;

{ THttpWebSocketDemo }

constructor THttpWebSocketDemo.Create;
begin
  FHtml := TFile.ReadAllText(
    TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'client.html'));

  FServer := TWebSocketServer.Create;
  FServer.DefaultPort := 8080;
  FServer.OnExecute := Execute;
  FServer.Active := true;
end;

destructor THttpWebSocketDemo.Destroy;
begin
  FServer.Active := false;
  FServer.DisposeOf;

  inherited;
end;

procedure THttpWebSocketDemo.ServeHttp(AContext: TIdContext);
var
  io: TWebSocketIOHandlerHelper;
  Bytes: TArray<byte>;
  Request: string;
begin
  io := TWebSocketIOHandlerHelper(AContext.Connection.IOHandler);

  // A connection that has not been handshaked keeps whatever it received in
  // the input buffer, so it can be handled as an ordinary HTTP request here
  if io.InputBufferIsEmpty then
    exit;

  io.InputBuffer.ExtractToBytes(TIdBytes(Bytes));
  Request := IndyTextEncoding_UTF8.GetString(TIdBytes(Bytes));

  // Wait for the complete request
  if not Request.Contains(#13#10#13#10) then
  begin
    io.InputBuffer.Write(TIdBytes(Bytes));
    exit;
  end;

  Writeln('HTTP request: ' + Request.Split([#13#10])[0]);

  io.Write('HTTP/1.1 200 OK'#13#10
    + 'Content-Type: text/html; charset=utf-8'#13#10
    + 'Content-Length: ' + Length(IndyTextEncoding_UTF8.GetBytes(FHtml)).ToString + #13#10
    + 'Connection: close'#13#10
    + #13#10
    + FHtml, IndyTextEncoding_UTF8);

  // Close the HTTP connection, otherwise its thread stays alive until
  // the browser decides to drop the connection
  AContext.Connection.Disconnect;
end;

procedure THttpWebSocketDemo.Execute(AContext: TIdContext);
var
  io: TWebSocketIOHandlerHelper;
  msg: string;
begin
  io := TWebSocketIOHandlerHelper(AContext.Connection.IOHandler);

  // Not a WebSocket connection (yet) - serve it as HTTP
  if io.Tag <> 1 then
  begin
    ServeHttp(AContext);
    exit;
  end;

  io.CheckForDataOnSource(10);
  msg := io.ReadString;
  if msg = '' then
    exit;

  Writeln('WebSocket message: ' + msg);

  io.WriteString('echo: ' + msg);
end;

var
  Demo: THttpWebSocketDemo;

begin
  try
    Demo := THttpWebSocketDemo.Create;
    Writeln('Open http://localhost:8080/ in a browser. Press Enter to quit.');
    readln;
    Demo.DisposeOf;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
