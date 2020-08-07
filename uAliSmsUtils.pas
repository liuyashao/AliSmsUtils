unit uAliSmsUtils;

{
阿里云短信单元
作者:liuyashao
}

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.Generics.Defaults;

type
  TSendResult = record
    BizId: string;
    Code:	string;
    Message: string;
    RequestId: string;
    constructor Create(const BizId, Code, Message, RequestId: string);
    function ToString: string;
    function IsSuccess: Boolean; inline;
    procedure RaiseExceptionIfNotSuccess;
  end;

  TSendBatchItem = record
    PhoneNumber: string;
    SignName:	string;
    constructor Create(const PhoneNumber, SignName: string);
  end;

  TSmsSendDetailDTO = record
    Content: string;
    ErrCode: string;
    OutId: string;
    PhoneNum: string;
    ReceiveDate: string;
    SendDate: string;
    SendStatus: string;
    IsSendSuccess: Boolean;
    TemplateCode: string;
    function ToString: string;
  end;

  TQuerySendDetailsResult = record
    RequestId: string;
    Code:	string;
    Message: string;
    TotalCount: Integer;
    Details: TArray<TSmsSendDetailDTO>;
    function ToString: string;
    function IsSuccess: Boolean; inline;
    procedure RaiseExceptionIfNotSuccess;
  end;

  THttpMethod = (tmPOST, tmGET);

  IAliSms = interface
    function Send(PhoneNumbers: TArray<string>; const SignName, TemplateCode,
      TemplateParam: string; const OutId: string = ''): TSendResult; overload;
    function Send(PhoneNumbers: TArray<string>; const SignName, TemplateCode: string;
      TemplateParam: TJSONObject; const OutId: string = ''): TSendResult; overload;

    function Send(const PhoneNumbers: string; const SignName, TemplateCode: string;
      TemplateParam: string; const OutId: string = ''): TSendResult; overload;
    function Send(const PhoneNumbers: string; const SignName, TemplateCode: string;
      TemplateParam: TJSONObject; const OutId: string = ''): TSendResult; overload;

    function SendBatch(Items: TArray<TSendBatchItem>;
      const TemplateCode: string; const TemplateParam: string = ''): TSendResult;

    function QuerySendDetails(const PhoneNumber: string; SendDate: TDate;
      CurrentPage: Integer = 1; PageSize: Integer = 50;
      const BizId: string = ''): TQuerySendDetailsResult;
  end;

function AliSms(const AccessKeyId, AccessKeySecre: string): IAliSms;
procedure SetDefaultHttpMethod(Value: THttpMethod);

var
  AfterSend: procedure(SendResult: TSendResult; PhoneNumbers: TArray<string>;
    const SignName, TemplateCode, TemplateParam, OutId: string);
  AfterSendBatch: procedure(SendResult: TSendResult;
    Items: TArray<TSendBatchItem>; const TemplateCode, TemplateParam: string);

implementation

uses
  System.DateUtils, System.NetEncoding, System.Net.HttpClient, System.Hash;

var
  __ErrCodeMsg: TDictionary<string, string>;
  __HttpMethod: THttpMethod;

const
  ALI_SMS_URL = 'https://dysmsapi.aliyuncs.com/';

type
  IRequest = interface
    procedure AddParam(const Name, Value: string);
    function GetParams: TStrings;
    function GetQueryStr: string;
    property Params: TStrings read GetParams;
  end;

  TAliSms = class(TInterfacedObject, IAliSms)
  private
    FAccessKeyId: string;
    FAccessKeySecre: string;
    function DoHttp(Request: IRequest): string;
  private
    {begin IAliSms}
    function Send(PhoneNumbers: TArray<string>; const SignName, TemplateCode,
      TemplateParam: string; const OutId: string = ''): TSendResult; overload;
    function Send(PhoneNumbers: TArray<string>; const SignName, TemplateCode: string;
      TemplateParam: TJSONObject; const OutId: string = ''): TSendResult; overload; inline;

    function Send(const PhoneNumbers: string; const SignName, TemplateCode: string;
      TemplateParam: string; const OutId: string = ''): TSendResult; overload; inline;
    function Send(const PhoneNumbers: string; const SignName, TemplateCode: string;
      TemplateParam: TJSONObject; const OutId: string = ''): TSendResult; overload; inline;

    function SendBatch(Items: TArray<TSendBatchItem>;
      const TemplateCode: string; const TemplateParam: string = ''): TSendResult; overload;
    function SendBatch(Items: TArray<TSendBatchItem>;
      const TemplateCode: string; TemplateParam: TJSONObject): TSendResult; overload;

    function QuerySendDetails(const PhoneNumber: string; SendDate: TDate;
      CurrentPage: Integer = 1; PageSize: Integer = 50;
      const BizId: string = ''): TQuerySendDetailsResult;
    {end IAliSms}
  public
    constructor Create(const AccessKeyId, AccessKeySecre: string);
  end;

  TRequest = class(TInterfacedObject, IRequest)
  private
    FAccessKeyId: string;
    FAccessKeySecre: string;
    FParams: TStringList;
    function GetSign(const StrToSign, AccessKeySecre: string): string;
    procedure Init(const HTTPMethod: THttpMethod);
  private
    {begin IRequest}
    procedure AddParam(const Name, Value: string); inline;
    function GetQueryStr: string;
    function GetParams: TStrings;
    property Params: TStrings read GetParams;
    {end IRequest}
  public
    constructor Create(const AccessKeyId, AccessKeySecre: string);
    destructor Destroy; override;
  end;

procedure SetDefaultHttpMethod(Value: THttpMethod);
begin
  __HttpMethod := Value;
end;

function AliSms(const AccessKeyId, AccessKeySecre: string): IAliSms;
begin
  Result := TAliSms.Create(AccessKeyId, AccessKeySecre);
end;

function GetSignatureNonce: string; inline;
begin
  Result := TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '');
end;

function SpecialUrlEncode(const Value: string): string; inline;
begin
  Result := TNetEncoding.URL.Encode(Value).Replace('+', '%20').Replace('*', '%2A').Replace('%7E', '~');
end;

function StringListNameCompareStrings(List: TStringList; Index1, Index2: Integer): Integer; inline;
begin
  Result := CompareStr(List.Names[Index1], List.Names[Index2])
end;

{ TSendResult }

constructor TSendResult.Create(const BizId, Code, Message, RequestId: string);
begin
  Self.BizId := BizId;
  Self.Code :=	Code;
  Self.Message := Message;
  Self.RequestId := RequestId;
end;

function TSendResult.IsSuccess: Boolean;
begin
  Result := SameText(Code, 'OK');
end;

procedure TSendResult.RaiseExceptionIfNotSuccess;
var
  ErrMsg: string;
begin
  if not IsSuccess then begin
    if __ErrCodeMsg.ContainsKey(Code) then
      ErrMsg := Format('%s: %s', [Code, __ErrCodeMsg[Code]])
    else
      ErrMsg := Format('%s: %s', [Code, Message]);
    raise Exception.Create(ErrMsg);
  end;
end;

function TSendResult.ToString: string;
begin
  Result := Format('{"BizId"="%s", "Code"="%s", "Message"="%s", "RequestId"="%s"}',
    [BizId, Code, Message, RequestId])
end;

{ TSendBatchItem }

constructor TSendBatchItem.Create(const PhoneNumber, SignName: string);
begin
  Self.PhoneNumber := PhoneNumber;
  Self.SignName :=	SignName;
end;

{ TSmsSendDetailDTO }

function TSmsSendDetailDTO.ToString: string;
begin
  Result := Format('{"Content"="%s", "ErrCode"="%s", "OutId"="%s", "PhoneNum"="%s", '+
    '"ReceiveDate"="%s", "SendDate"="%s", "SendStatus"="%s", "TemplateCode"="%s"}',
    [Content, ErrCode, OutId, PhoneNum, ReceiveDate, SendDate, SendStatus, TemplateCode]);
end;

{ TQuerySendDetailsResult }

function TQuerySendDetailsResult.IsSuccess: Boolean;
begin
  Result := SameText(Code, 'OK');
end;

procedure TQuerySendDetailsResult.RaiseExceptionIfNotSuccess;
var
  ErrMsg: string;
begin
  if not IsSuccess then begin
    if __ErrCodeMsg.ContainsKey(Code) then
      ErrMsg := Format('%s: %s', [Code, __ErrCodeMsg[Code]])
    else
      ErrMsg := Format('%s: %s', [Code, Message]);
    raise Exception.Create(ErrMsg);
  end;
end;

function TQuerySendDetailsResult.ToString: string;
var
  DetailsStr: string;
  Detail: TSmsSendDetailDTO;
begin
  DetailsStr := '';
  for Detail in Details do
    DetailsStr := DetailsStr + ',' + Detail.ToString;
  DetailsStr := DetailsStr.Substring(1);
  Result := Format('{"Code"="%s", "Message"="%s", "TotalCount"=%d, "SmsSendDetailDTOs"={"SmsSendDetailDTO":[%s]}, "RequestId"="%s"}',
    [Code, Message, TotalCount, DetailsStr, RequestId]);
end;

{ TAliSms }

constructor TAliSms.Create(const AccessKeyId, AccessKeySecre: string);
begin
  FAccessKeyId := AccessKeyId;
  FAccessKeySecre := AccessKeySecre;
end;

function TAliSms.DoHttp(Request: IRequest): string;
var
  HTTPClient: THTTPClient;
begin
  HTTPClient := THTTPClient.Create;
  try
    case __HttpMethod of
      tmPOST: Result := HTTPClient.Post(ALI_SMS_URL, Request.Params).ContentAsString(TEncoding.UTF8);
      tmGET:  Result := HTTPClient.Get(ALI_SMS_URL+'?'+Request.GetQueryStr).ContentAsString(TEncoding.UTF8);
    end;
  finally
    HTTPClient.Free;
  end;
end;

function TAliSms.Send(const PhoneNumbers, SignName, TemplateCode: string;
  TemplateParam: TJSONObject; const OutId: string): TSendResult;
begin
  Result := Send(PhoneNumbers.Split([',']), SignName, TemplateCode, TemplateParam.ToString, OutId)
end;

function TAliSms.Send(const PhoneNumbers: string; const SignName,
  TemplateCode: string; TemplateParam: string;
  const OutId: string): TSendResult;
begin
  Result := Send(PhoneNumbers.Split([',']), SignName, TemplateCode, TemplateParam, OutId)
end;

function TAliSms.Send(PhoneNumbers: TArray<string>; const SignName,
  TemplateCode: string; TemplateParam: TJSONObject;
  const OutId: string): TSendResult;
begin
  Result := Send(PhoneNumbers, SignName, TemplateCode, TemplateParam.ToString, OutId)
end;

function TAliSms.Send(PhoneNumbers: TArray<string>; const SignName, TemplateCode,
  TemplateParam, OutId: string): TSendResult;
var
  Request: IRequest;
  ContentStr: string;
  jo: TJSONObject;
begin
  Request := TRequest.Create(FAccessKeyId, FAccessKeySecre);
  Request.AddParam('PhoneNumbers', string.Join(',', PhoneNumbers));
  Request.AddParam('SignName', SignName);
  Request.AddParam('TemplateCode', TemplateCode);
  Request.AddParam('TemplateParam', TemplateParam);
  Request.AddParam('Action', 'SendSms');
  if not OutId.IsEmpty then
    Request.AddParam('OutId', OutId);
  jo := nil;
  try
    ContentStr := DoHttp(Request);
    jo := TJSONObject.ParseJSONValue(ContentStr) as TJSONObject;
    with jo do begin
      if Values['BizId'] <> nil then
        Result := TSendResult.Create(GetValue<string>('BizId'), GetValue<string>('Code'),
          GetValue<string>('Message'), GetValue<string>('RequestId'))
      else
        raise Exception.Create(ContentStr);
    end;
    if Assigned(AfterSend) then
      AfterSend(Result, PhoneNumbers, SignName, TemplateCode,
        TemplateParam, OutId);
  finally
    jo.Free;
  end;
end;

function TAliSms.SendBatch(Items: TArray<TSendBatchItem>;
  const TemplateCode: string; TemplateParam: TJSONObject): TSendResult;
begin
  Result := SendBatch(Items, TemplateCode, TemplateParam.ToString);
end;

function TAliSms.SendBatch(Items: TArray<TSendBatchItem>;
  const TemplateCode, TemplateParam: string): TSendResult;
var
  Request: IRequest;
  ContentStr: string;
  PhoneNumberJson: TJSONArray;
  SignNameJson: TJSONArray;
  jo: TJSONObject;
  Item: TSendBatchItem;
begin
  PhoneNumberJson := TJSONArray.Create;
  SignNameJson := TJSONArray.Create;
  jo := nil;
  try
    for Item in Items do begin
      PhoneNumberJson.Add(Item.PhoneNumber);
      SignNameJson.Add(Item.SignName);
    end;
    Request := TRequest.Create(FAccessKeyId, FAccessKeySecre);
    Request.AddParam('PhoneNumberJson', PhoneNumberJson.ToString);
    Request.AddParam('SignNameJson', SignNameJson.ToString);
    Request.AddParam('TemplateCode', TemplateCode);
    Request.AddParam('TemplateParamJson', TemplateParam);
    Request.AddParam('Action', 'SendBatchSms');
    ContentStr := DoHttp(Request);
    jo := TJSONObject.ParseJSONValue(ContentStr) as TJSONObject;
    with jo do begin
      if Values['BizId'] <> nil then
        Result := TSendResult.Create(GetValue<string>('BizId'), GetValue<string>('Code'),
          GetValue<string>('Message'), GetValue<string>('RequestId'))
      else
        raise Exception.Create(ContentStr);
    end;
    if Assigned(AfterSendBatch) then
      AfterSendBatch(Result, Items, TemplateCode, TemplateParam);
  finally
    jo.Free;
    PhoneNumberJson.Free;
    SignNameJson.Free;
  end;
end;

function TAliSms.QuerySendDetails(const PhoneNumber: string; SendDate: TDate;
  CurrentPage, PageSize: Integer; const BizId: string): TQuerySendDetailsResult;
var
  Request: IRequest;
  ContentStr: string;
  jo: TJSONObject;
  I: Integer;
  ja: TJSONArray;
begin
  Request := TRequest.Create(FAccessKeyId, FAccessKeySecre);
  Request.AddParam('PhoneNumber', PhoneNumber);
  Request.AddParam('CurrentPage', CurrentPage.ToString);
  Request.AddParam('PageSize', PageSize.ToString);
  Request.AddParam('SendDate', FormatDateTime('yyyymmdd', SendDate));
  Request.AddParam('Action', 'QuerySendDetails');
  if not BizId.IsEmpty then
    Request.AddParam('BizId', BizId);
  jo := nil;
  try
    ContentStr := DoHttp(Request);
    jo := TJSONObject.ParseJSONValue(ContentStr) as TJSONObject;
    if jo.Values['TotalCount'] <> nil then begin
      Result.Code := jo.GetValue<string>('Code');
      Result.Message := jo.GetValue<string>('Message');
      Result.RequestId := jo.GetValue<string>('RequestId');
      Result.TotalCount := jo.GetValue<Integer>('TotalCount');
      ja := jo.GetValue<TJSONArray>('SmsSendDetailDTOs.SmsSendDetailDTO');
      SetLength(Result.Details, ja.Count);
      for I := 0 to ja.Count - 1 do begin
        ja.Items[I].TryGetValue<string>('Content', Result.Details[I].Content);
        ja.Items[I].TryGetValue<string>('ErrCode', Result.Details[I].ErrCode);
        ja.Items[I].TryGetValue<string>('OutId', Result.Details[I].OutId);
        ja.Items[I].TryGetValue<string>('PhoneNum', Result.Details[I].PhoneNum);
        ja.Items[I].TryGetValue<string>('ReceiveDate', Result.Details[I].ReceiveDate);
        ja.Items[I].TryGetValue<string>('TemplateCode', Result.Details[I].TemplateCode);
        ja.Items[I].TryGetValue<string>('SendDate', Result.Details[I].SendDate);
        ja.Items[I].TryGetValue<string>('SendStatus', Result.Details[I].SendStatus);
        Result.Details[I].IsSendSuccess := Result.Details[I].SendStatus = '3';
      end;
    end
    else
      raise Exception.Create(ContentStr);
  finally
    jo.Free;
  end;
end;

{ TRequest }

constructor TRequest.Create(const AccessKeyId, AccessKeySecre: string);
begin
  FAccessKeyId := AccessKeyId;
  FAccessKeySecre := AccessKeySecre;
  FParams := TStringList.Create;
  //必填
  AddParam('SignatureVersion', '1.0');
  AddParam('Version', '2017-05-25');
  AddParam('SignatureMethod', 'HMAC-SHA1');
  //选填
  AddParam('Format', 'json');
end;

destructor TRequest.Destroy;
begin
  FParams.Free;
  inherited;
end;

procedure TRequest.AddParam(const Name, Value: string);
begin
  FParams.Values[Name] := Value;
end;

procedure TRequest.Init(const HTTPMethod: THttpMethod);
var
  Name: string;
  Value: string;
  I: Integer;
  SortedQueryStr: string;
  StrToSign: string;
  Signature: string;
begin
  AddParam('Timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(Now)));
  AddParam('SignatureNonce', GetSignatureNonce);
  AddParam('AccessKeyId', FAccessKeyId);
  AddParam('Signature', '');//remove signature key with empty string value
  FParams.CustomSort(StringListNameCompareStrings);//sort by Key only
  SortedQueryStr := '';
  for I := 0 to FParams.Count - 1 do begin
    Name := FParams.Names[I];
    Value := FParams.Values[Name];
    SortedQueryStr := SortedQueryStr + '&' + SpecialUrlEncode(Name) + '=' + SpecialUrlEncode(Value);
  end;
  SortedQueryStr := SortedQueryStr.Substring(1);
  case HTTPMethod of
    tmPOST: StrToSign := 'POST';
    tmGET:  StrToSign := 'GET';
  end;
  StrToSign := StrToSign + '&' + SpecialUrlEncode('/') + '&' + SpecialUrlEncode(SortedQueryStr);
  Signature := GetSign(StrToSign, FAccessKeySecre);
  AddParam('Signature', Signature);
end;

function TRequest.GetSign(const StrToSign, AccessKeySecre: string): string;
var
  Bytes: TBytes;
begin
  Bytes := THashSHA1.GetHMACAsBytes(TEncoding.UTF8.GetBytes(StrToSign),
    TEncoding.UTF8.GetBytes(AccessKeySecre+'&'));
  Result := TNetEncoding.Base64.EncodeBytesToString(Bytes);
end;

function TRequest.GetParams: TStrings;
begin
  Init(tmPOST);
  Result := FParams;
end;

function TRequest.GetQueryStr: string;
var
  I: Integer;
  Name: string;
  Value: string;
begin
  Init(tmGET);
  Result := '';
  for I := 0 to FParams.Count - 1 do begin
    Name := FParams.Names[I];
    Value := FParams.Values[Name];
    Result := Result + '&' + Name + '=' + SpecialUrlEncode(Value);
  end;
  Result := Result.Substring(1);
end;

procedure InitErrCodeMsg;
begin
  with __ErrCodeMsg do begin
    Add('isv.SMS_SIGNATURE_SCENE_ILLEGAL',   '短信所使用签名场景非法');
    Add('isv.EXTEND_CODE_ERROR',             '扩展码使用错误，相同的扩展码不可用于多个签名');
    Add('isv.DOMESTIC_NUMBER_NOT_SUPPORTED', '国际/港澳台消息模板不支持发送境内号码');
    Add('isv.DENY_IP_RANGE',                 '源IP地址所在的地区被禁用');
    Add('isv.DAY_LIMIT_CONTROL',             '触发日发送限额');
    Add('isv.SMS_CONTENT_ILLEGAL',           '短信内容包含禁止发送内容');
    Add('isv.SMS_SIGN_ILLEGAL',              '签名禁止使用');
    Add('isv.RAM_PERMISSION_DENY',           'RAM权限DENY');
    Add('isv.OUT_OF_SERVICE',                '业务停机');
    Add('isv.PRODUCT_UN_SUBSCRIPT',          '未开通云通信产品的阿里云客户');
    Add('isv.PRODUCT_UNSUBSCRIBE',           '产品未开通');
    Add('isv.ACCOUNT_NOT_EXISTS',            '账户不存在');
    Add('isv.ACCOUNT_ABNORMAL',              '账户异常');
    Add('isv.SMS_TEMPLATE_ILLEGAL',          '短信模版不合法');
    Add('isv.SMS_SIGNATURE_ILLEGAL',         '短信签名不合法');
    Add('isv.INVALID_PARAMETERS',            '参数异常');
    Add('isp.SYSTEM_ERROR',                  '系统错误');
    Add('isv.MOBILE_NUMBER_ILLEGAL',         '非法手机号');
    Add('isv.MOBILE_COUNT_OVER_LIMIT',       '手机号码数量超过限制');
    Add('isv.TEMPLATE_MISSING_PARAMETERS',   '模版缺少变量');
    Add('isv.BUSINESS_LIMIT_CONTROL',        '业务限流，短信发送频率超限');
    Add('isv.INVALID_JSON_PARAM',            'JSON参数不合法，只接受字符串值');
    Add('isv.BLACK_KEY_CONTROL_LIMIT',       '黑名单管控');
    Add('isv.PARAM_LENGTH_LIMIT',            '参数超出长度限制');
    Add('isv.PARAM_NOT_SUPPORT_URL',         '不支持URL');
    Add('isv.AMOUNT_NOT_ENOUGH',             '账户余额不足');
    Add('isv.TEMPLATE_PARAMS_ILLEGAL',       '模版变量里包含非法关键字');
    Add('SignatureDoesNotMatch',             '签名（Signature）加密错误');
    Add('InvalidTimeStamp.Expired',          'Specified time stamp or date value is expired');
    Add('SignatureNonceUsed',                'Specified signature nonce was used already');
    Add('InvalidVersion',                    '版本号（Version）错误');
    Add('InvalidAction.NotFound',            '参数Action中指定的接口名错误');
    Add('isv.SIGN_COUNT_OVER_LIMIT',         '一个自然日中申请签名数量超过限制');
    Add('isv.TEMPLATE_COUNT_OVER_LIMIT',     '一个自然日中申请模板数量超过限制');
    Add('isv.SIGN_NAME_ILLEGAL',             '签名名称不符合规范');
    Add('isv.SIGN_FILE_LIMIT',               '签名认证材料附件大小超过限制');
    Add('isv.SIGN_OVER_LIMIT',               '签名字符数量超过限制');
    Add('isv.TEMPLATE_OVER_LIMIT',           '签名字符数量超过限制');
  end;
end;

initialization
  SetDefaultHttpMethod(tmPOST);
  __ErrCodeMsg := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  InitErrCodeMsg;

finalization
  __ErrCodeMsg.Free;

end.
