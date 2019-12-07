program WebSocketDemo;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  WebSocketServer in 'WebSocketServer.pas';

begin
  try
    { TODO -oUser -cConsole Main : Insert code here }
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
