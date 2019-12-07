unit WebSocketServer;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,

  IdCustomTCPServer, IdTCPConnection, IdContext, IdIOHandler, IdGlobal, IdCoderMIME, IdHashSHA,
  IdSSL, IdSSLOpenSSL;

type

  TWebSocketServer = class(TIdCustomTCPServer)
  private
    IdServerIOHandlerSSLOpenSSL: TIdServerIOHandlerSSLOpenSSL;
    HashSHA1: TIdHashSHA1;

  protected
    procedure DoConnect(AContext: TIdContext); override;
    function DoExecute(AContext: TIdContext): Boolean; override;

  public
    procedure InitSSL(AIdServerIOHandlerSSLOpenSSL: TIdServerIOHandlerSSLOpenSSL);

    property OnExecute;

    constructor Create;
    destructor Destroy; override;
  end;

  TWebSocketIOHandlerHelper = class(TIdIOHandler)
  public
    function ReadBytes: TArray<byte>;
    function ReadString: string;

    procedure WriteBytes(RawData: TArray<byte>);
    procedure WriteString(const str: string);
  end;

implementation

{ TWebSocketServer }

constructor TWebSocketServer.Create;
begin
  inherited Create;

  HashSHA1 := TIdHashSHA1.Create;
  IdServerIOHandlerSSLOpenSSL := nil;
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

  // Mark connection as invalid during it's not handshaked
  AContext.Connection.IOHandler.Tag := -1;

  inherited;
end;

function TWebSocketServer.DoExecute(AContext: TIdContext): Boolean;
var
  h: TIdIOHandler;
  Bytes: TArray<byte>;
  s: string;
  arr: TArray<string>;
  SecWebSocketKeyLine: integer;
  Hash: string;

  // under ARC, convert a weak reference to a strong reference before working with it
  LConn: TIdTCPConnection;
begin
  h := AContext.Connection.IOHandler;

  // Handshake reading

  if h.Tag = -1 then
  begin
    Bytes := nil;

    h.CheckForDataOnSource(10);
    if not h.InputBufferIsEmpty then
    begin
      h.InputBuffer.ExtractToBytes(TIdBytes(Bytes));
      s := IndyTextEncoding_UTF8.GetString(TIdBytes(Bytes));
      arr := s.Split([#13#10]);

      if TArrayHelper.Contains<string>(arr, 'Upgrade: websocket') then
      begin
        // Handle handshake request
        // https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_servers

        SecWebSocketKeyLine := TArrayHelper.Find<string>(arr,
          function(s: string): boolean
          begin
            result := s.StartsWith('Sec-WebSocket-Key:');
          end);

        if SecWebSocketKeyLine > -1 then
        begin
          // Send handshake response
          Hash := TIdEncoderMIME.EncodeBytes(HashSHA1.HashString(Trim(arr[SecWebSocketKeyLine].Split([': '])[1]) +
            '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'));
          h.Write('HTTP/1.1 101 Switching Protocols'#13#10
            + 'Upgrade: websocket'#13#10
            + 'Connection: Upgrade'#13#10
            + 'Sec-WebSocket-Accept: '+ Hash
            + #13#10#13#10, IndyTextEncoding_UTF8);

          // Mark connection as handshaked WebSocket connection
          h.Tag := 1;
        end;
      end;
    end;

    // Handle some things, that parent DoExecute have to
    result := false;
    if AContext <> nil then
    begin
      LConn := AContext.Connection;
      if LConn <> nil then
        Result := LConn.Connected;
    end;

  end
  else
    // After handshaking we can work in default way
    result := inherited;
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

    // TODO: Bad fix
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

  Write(TIdBytes(Msg), Length(Msg));
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
