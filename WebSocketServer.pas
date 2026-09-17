unit WebSocketServer;

interface

uses
  System.SysUtils, System.Generics.Collections,

  IdCustomTCPServer, IdTCPConnection, IdContext, IdIOHandler, IdGlobal, IdCoderMIME, IdHashSHA,
  IdSSL, IdSSLOpenSSL;

const
  DefaultHandshakeTimeout = 10000;

type

  // Context that remembers when the connection was accepted, so that clients
  // which never perform the handshake can be dropped instead of occupying
  // a thread forever
  TWebSocketContext = class(TIdServerContext)
  private
    FConnectedAt: TIdTicks;
  public
    property ConnectedAt: TIdTicks read FConnectedAt;
  end;

  TWebSocketServer = class(TIdCustomTCPServer)
  private
    IdServerIOHandlerSSLOpenSSL: TIdServerIOHandlerSSLOpenSSL;
    HashSHA1: TIdHashSHA1;
    FHandshakeTimeout: integer;

  protected
    procedure DoConnect(AContext: TIdContext); override;
    function DoExecute(AContext: TIdContext): Boolean; override;

  public
    procedure InitSSL(AIdServerIOHandlerSSLOpenSSL: TIdServerIOHandlerSSLOpenSSL);

    property OnExecute;

    // How long (in milliseconds) a connection may stay open without completing
    // the WebSocket handshake before it is disconnected. Data received from such
    // a connection is left in the IOHandler's InputBuffer, so that OnExecute can
    // handle it (a plain HTTP request, for example) - remember to disconnect the
    // connection yourself once you are done with it, otherwise its thread lives
    // until this timeout expires. Set to 0 to disable the timeout.
    property HandshakeTimeout: integer read FHandshakeTimeout write FHandshakeTimeout
      default DefaultHandshakeTimeout;

    constructor Create;
    destructor Destroy; override;
  end;

  TWebSocketIOHandlerHelper = class(TIdIOHandler)
  public
    function ReadBytes: TArray<byte>; reintroduce;
    function ReadString: string;

    procedure WriteBytes(RawData: TArray<byte>);
    procedure WriteString(const str: string);
  end;

implementation

function HeadersParse(const msg: string): TDictionary<string, string>;
var
  lines: TArray<string>;
  line: string;
  SplittedLine: TArray<string>;
begin
  result := TDictionary<string, string>.Create;
  lines := msg.Split([#13#10]);
  for line in lines do
  begin
    SplittedLine := line.Split([': ']);
    if Length(SplittedLine) > 1 then
      result.AddOrSetValue(Trim(SplittedLine[0]), Trim(SplittedLine[1]));
  end;
end;

{ TWebSocketServer }

constructor TWebSocketServer.Create;
begin
  inherited Create;

  HashSHA1 := TIdHashSHA1.Create;
  IdServerIOHandlerSSLOpenSSL := nil;
  FHandshakeTimeout := DefaultHandshakeTimeout;
  ContextClass := TWebSocketContext;
end;

destructor TWebSocketServer.Destroy;
begin
  HashSHA1.DisposeOf;

  inherited;
end;

procedure TWebSocketServer.InitSSL(AIdServerIOHandlerSSLOpenSSL: TIdServerIOHandlerSSLOpenSSL);
var
  CurrentActive: boolean;
begin
  CurrentActive := Active;
  if CurrentActive then
    Active := false;

  IdServerIOHandlerSSLOpenSSL := AIdServerIOHandlerSSLOpenSSL;
  IOHandler := AIdServerIOHandlerSSLOpenSSL;

  if CurrentActive then
    Active := true;
end;

procedure TWebSocketServer.DoConnect(AContext: TIdContext);
begin
  if AContext.Connection.IOHandler is TIdSSLIOHandlerSocketBase then
    TIdSSLIOHandlerSocketBase(AContext.Connection.IOHandler).PassThrough := false;

  // Mark connection as "not handshaked"
  AContext.Connection.IOHandler.Tag := -1;

  if AContext is TWebSocketContext then
    TWebSocketContext(AContext).FConnectedAt := Ticks64;

  inherited;
end;

function TWebSocketServer.DoExecute(AContext: TIdContext): Boolean;
var
  c: TIdIOHandler;
  Bytes: TArray<byte>;
  msg, SecWebSocketKey, Hash: string;
  ParsedHeaders: TDictionary<string, string>;
  Handshaked: boolean;
begin
  c := AContext.Connection.IOHandler;

  // Handshake

  if c.Tag = -1 then
  begin
    Handshaked := false;

    c.CheckForDataOnSource(10);

    if not c.InputBufferIsEmpty then
    begin
      // Read string and parse HTTP headers
      Bytes := nil;
      msg := '';
      try
        c.InputBuffer.ExtractToBytes(TIdBytes(Bytes));
        msg := IndyTextEncoding_UTF8.GetString(TIdBytes(Bytes));
      except
      end;

      ParsedHeaders := HeadersParse(msg);
      try
        if ParsedHeaders.ContainsKey('Upgrade') and SameText(ParsedHeaders['Upgrade'], 'websocket') and
          ParsedHeaders.ContainsKey('Sec-WebSocket-Key') then
        begin
          // Handle handshake request
          // https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_servers

          SecWebSocketKey := ParsedHeaders['Sec-WebSocket-Key'];

          // Send handshake response
          Hash := TIdEncoderMIME.EncodeBytes(
            HashSHA1.HashString(SecWebSocketKey + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'));

          try
            c.Write('HTTP/1.1 101 Switching Protocols'#13#10
              + 'Upgrade: websocket'#13#10
              + 'Connection: Upgrade'#13#10
              + 'Sec-WebSocket-Accept: ' + Hash
              + #13#10#13#10, IndyTextEncoding_UTF8);
          except
          end;

          // Mark IOHandler as handshaked
          c.Tag := 1;
          Handshaked := true;
        end;
      finally
        ParsedHeaders.DisposeOf;
      end;

      // This is not a handshake request (a plain HTTP request, or an incomplete
      // one). Put the data back so that OnExecute can handle it, or so that the
      // rest of the handshake request can be appended to it on the next run.
      if not Handshaked then
        c.InputBuffer.Write(TIdBytes(Bytes));
    end;

    // Drop connections that never complete the handshake, otherwise they keep
    // an Indy thread busy until the peer disconnects - which it may never do
    if (not Handshaked) and (FHandshakeTimeout > 0) and (AContext is TWebSocketContext) and
      (GetTickDiff64(TWebSocketContext(AContext).ConnectedAt, Ticks64) > TIdTicks(FHandshakeTimeout)) then
    begin
      AContext.Connection.Disconnect;
      Result := false;
      exit;
    end;
  end;

  Result := inherited;
end;

{ TWebSocketIOHandlerHelper }

function TWebSocketIOHandlerHelper.ReadBytes: TArray<byte>;
var
  l: byte;
  b: array [0..7] of byte;
  i, DecodedSize: int64;
  Mask: array [0..3] of byte;
begin
  // https://stackoverflow.com/questions/8125507/how-can-i-send-and-receive-websocket-messages-on-the-server-side

  try
    if ReadByte = $81 then
    begin
      l := ReadByte;
      case l of
        $FE:
          begin
            b[1] := ReadByte; b[0] := ReadByte;
            b[2] := 0; b[3] := 0; b[4] := 0; b[5] := 0; b[6] := 0; b[7] := 0;
            DecodedSize := Int64(b);
          end;
        $FF:
          begin
            b[7] := ReadByte; b[6] := ReadByte; b[5] := ReadByte; b[4] := ReadByte;
            b[3] := ReadByte; b[2] := ReadByte; b[1] := ReadByte; b[0] := ReadByte;
            DecodedSize := Int64(b);
          end;
        else
          DecodedSize := l - 128;
      end;
      Mask[0] := ReadByte; Mask[1] := ReadByte; Mask[2] := ReadByte; Mask[3] := ReadByte;

      if DecodedSize < 1 then
      begin
        result := [];
        exit;
      end;

      SetLength(result, DecodedSize);
      inherited ReadBytes(TIdBytes(result), DecodedSize, False);
      for i := 0 to DecodedSize - 1 do
        result[i] := result[i] xor Mask[i mod 4];
    end;
  except
  end;
end;

procedure TWebSocketIOHandlerHelper.WriteBytes(RawData: TArray<byte>);
var
  Msg: TArray<byte>;
begin
  // https://stackoverflow.com/questions/8125507/how-can-i-send-and-receive-websocket-messages-on-the-server-side
  
  Msg := [$81];

  if Length(RawData) <= 125 then
    Msg := Msg + [Length(RawData)]
  else if (Length(RawData) >= 126) and (Length(RawData) <= 65535) then
    Msg := Msg + [126, (Length(RawData) shr 8) and 255, Length(RawData) and 255]
  else
    Msg := Msg + [127, (int64(Length(RawData)) shr 56) and 255, (int64(Length(RawData)) shr 48) and 255,
      (int64(Length(RawData)) shr 40) and 255, (int64(Length(RawData)) shr 32) and 255,
      (Length(RawData) shr 24) and 255, (Length(RawData) shr 16) and 255, (Length(RawData) shr 8) and 255, Length(RawData) and 255];

  Msg := Msg + RawData;

  try
    Write(TIdBytes(Msg), Length(Msg));
  except
  end;
end;

function TWebSocketIOHandlerHelper.ReadString: string;
begin
  result := IndyTextEncoding_UTF8.GetString(TIdBytes(ReadBytes));
end;

procedure TWebSocketIOHandlerHelper.WriteString(const str: string);
begin
  WriteBytes(TArray<byte>(IndyTextEncoding_UTF8.GetBytes(str)));
end;

end.
