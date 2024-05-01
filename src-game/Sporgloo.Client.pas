unit Sporgloo.Client;

interface

uses
  Olf.Net.Socket.Messaging,
  Sporgloo.API.Messages,
  Sporgloo.Types,
  Sporgloo.Consts;

type
  TSporglooClient = class(TSporglooSocketMessagesClient)
  private
  protected
    procedure onClientRegisterResponse(Const AFromServer
      : TOlfSocketMessagingServerConnectedClient;
      Const msg: TClientRegisterResponseMessage);
    procedure onClientLoginResponse(Const AFromServer
      : TOlfSocketMessagingServerConnectedClient;
      Const msg: TClientLoginResponseMessage);
    procedure onMapCell(Const AFromServer
      : TOlfSocketMessagingServerConnectedClient; Const msg: TMapCellMessage);
    procedure onLogoff(Const AFromServer
      : TOlfSocketMessagingServerConnectedClient; Const msg: TLogoffMessage);

    procedure onErrorMessage(Const AFromServer
      : TOlfSocketMessagingServerConnectedClient; Const msg: TErrorMessage);
  public
    constructor Create(AServerIP: string; AServerPort: word); override;

    procedure SendClientRegister(Const DeviceID: string);
    procedure SendClientLogin(Const DeviceID, PlayerID: string);
    procedure SendMapRefresh(Const X, Y, ColNumber,
      RowNumber: TSporglooAPINumber);
    procedure SendPlayerMove(Const SessionID, PlayerID: string;
      Const X, Y: TSporglooAPINumber);
    procedure SendPlayerPutAStar(Const SessionID, PlayerID: string;
      Const X, Y: TSporglooAPINumber);

    procedure SendErrorMessage(const AErrorCode: TSporglooErrorCode;
      const AErrorText: string; const ARaiseException: boolean = true);
  end;

implementation

Uses
  System.Classes,
  System.SysUtils,
  System.Messaging,
  uGameData,
  uConfig,
  Sporgloo.Messaging,
  Sporgloo.Database;

{ TSporglooClient }

constructor TSporglooClient.Create(AServerIP: string; AServerPort: word);
begin
  inherited;
  onReceiveClientRegisterResponseMessage := onClientRegisterResponse;
  onReceiveClientLoginResponseMessage := onClientLoginResponse;
  onReceiveMapCellMessage := onMapCell;
  OnReceiveErrorMessage := onErrorMessage;
  onReceiveLogoffMessage := onLogoff;
end;

procedure TSporglooClient.onClientLoginResponse(const AFromServer
  : TOlfSocketMessagingServerConnectedClient;
  const msg: TClientLoginResponseMessage);
var
  LGameData: TGameData;
begin
  if (tconfig.Current.DeviceID <> msg.DeviceID) then
    SendErrorMessage(TSporglooErrorCode.WrongDeviceID,
      'Wrong DeviceID sent from the server.');

  if msg.SessionID.IsEmpty then
    SendErrorMessage(TSporglooErrorCode.WrongSessionID,
      'No SessionID returned by the server.');

  LGameData := TGameData.Current;
  LGameData.Session.SessionID := msg.SessionID;
  LGameData.Player.PlayerX := msg.X;
  LGameData.Player.PlayerY := msg.Y;
  LGameData.Player.Score := msg.Score;
  LGameData.Player.StarsCount := msg.Stars;
  LGameData.Player.LifeLevel := msg.Life;

  LGameData.RefreshMap;
end;

procedure TSporglooClient.onClientRegisterResponse(const AFromServer
  : TOlfSocketMessagingServerConnectedClient;
  const msg: TClientRegisterResponseMessage);
begin
  if (tconfig.Current.DeviceID <> msg.DeviceID) then
    SendErrorMessage(TSporglooErrorCode.WrongDeviceID,
      'Wrong DeviceID sent from the server.');

  if msg.PlayerID.IsEmpty then
    SendErrorMessage(TSporglooErrorCode.WrongPlayerID,
      'No PlayerID returned by the server.');

  tconfig.Current.PlayerID := msg.PlayerID;
  TGameData.Current.Player.PlayerID := msg.PlayerID;
  TGameData.Current.Session.Player := TGameData.Current.Player;

  SendClientLogin(msg.DeviceID, msg.PlayerID);
end;

procedure TSporglooClient.onErrorMessage(const AFromServer
  : TOlfSocketMessagingServerConnectedClient; const msg: TErrorMessage);
begin
  // TODO : manage the received error
end;

procedure TSporglooClient.onLogoff(const AFromServer
  : TOlfSocketMessagingServerConnectedClient; const msg: TLogoffMessage);
begin
  TThread.ForceQueue(nil,
    procedure
    begin
      TMessageManager.DefaultManager.SendMessage(self,
        TDisconnectMessage.Create);
    end);
end;

procedure TSporglooClient.onMapCell(const AFromServer
  : TOlfSocketMessagingServerConnectedClient; const msg: TMapCellMessage);
var
  MapCell: TSporglooMapCell;
begin
  MapCell := TGameData.Current.Map.GetCellAt(msg.X, msg.Y);
  MapCell.TileID := msg.TileID;
  MapCell.PlayerID := msg.PlayerID;

  TThread.queue(nil,
    procedure
    begin
      TMessageManager.DefaultManager.SendMessage(self,
        TMapCellUpdateMessage.Create(MapCell));
    end);
end;

procedure TSporglooClient.SendClientLogin(const DeviceID, PlayerID: string);
var
  msg: TClientLoginMessage;
begin
  msg := TClientLoginMessage.Create;
  try
    msg.DeviceID := DeviceID;
    msg.PlayerID := PlayerID;
    msg.VersionAPI := CAPIVersion;
    SendMessage(msg);
  finally
    msg.Free;
  end;
end;

procedure TSporglooClient.SendClientRegister(const DeviceID: string);
var
  msg: TClientRegisterMessage;
begin
  msg := TClientRegisterMessage.Create;
  try
    msg.DeviceID := DeviceID;
    msg.VersionAPI := CAPIVersion;
    SendMessage(msg);
  finally
    msg.Free;
  end;
end;

procedure TSporglooClient.SendErrorMessage(const AErrorCode: TSporglooErrorCode;
const AErrorText: string; const ARaiseException: boolean);
var
  msg: TErrorMessage;
begin
  // TODO : add a client log or an error reporting (in case of attack or other problem)

  msg := TErrorMessage.Create;
  try
    msg.ErrorCode := ord(AErrorCode);
    SendMessage(msg);
  finally
    msg.Free;
  end;

  if ARaiseException then
    raise TSporglooException.Create(AErrorCode, AErrorText);
end;

procedure TSporglooClient.SendMapRefresh(const X, Y, ColNumber,
  RowNumber: TSporglooAPINumber);
var
  msg: TMapRefreshDemandMessage;
begin
  msg := TMapRefreshDemandMessage.Create;
  try
    msg.X := X;
    msg.Y := Y;
    msg.ColNumber := ColNumber;
    msg.RowNumber := RowNumber;
    SendMessage(msg);
  finally
    msg.Free;
  end;
end;

procedure TSporglooClient.SendPlayerMove(const SessionID, PlayerID: string;
const X, Y: TSporglooAPINumber);
var
  msg: TPlayerMoveMessage;
begin
  msg := TPlayerMoveMessage.Create;
  try
    msg.SessionID := SessionID;
    msg.PlayerID := PlayerID;
    msg.X := X;
    msg.Y := Y;
    SendMessage(msg);
  finally
    msg.Free;
  end;
end;

procedure TSporglooClient.SendPlayerPutAStar(const SessionID, PlayerID: string;
const X, Y: TSporglooAPINumber);
var
  msg: TPlayerAddAStarOnTheMapMessage;
begin
  msg := TPlayerAddAStarOnTheMapMessage.Create;
  try
    msg.SessionID := SessionID;
    msg.PlayerID := PlayerID;
    msg.X := X;
    msg.Y := Y;
    SendMessage(msg);
  finally
    msg.Free;
  end;
end;


end.
