阿里云发送短信的Delphi单元  

使用方法  
uses uAliSmsUtils;  

AliSms('AccessKeyId', 'AccessKeySecre').Send('手机号码', '签名', '模板编号', '参数');  

