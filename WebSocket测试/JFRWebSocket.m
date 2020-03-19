//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  JFRWebSocket.m
//
//  Created by Austin and Dalton Cherry on on 5/13/14.
//  Copyright (c) 2014-2017 Austin Cherry.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

#import "JFRWebSocket.h"

//get the opCode from the packet
typedef NS_ENUM(NSUInteger, JFROpCode) {
    JFROpCodeContinueFrame = 0x0,
    JFROpCodeTextFrame = 0x1,
    JFROpCodeBinaryFrame = 0x2,
    //3-7 are reserved.
    JFROpCodeConnectionClose = 0x8,
    JFROpCodePing = 0x9,
    JFROpCodePong = 0xA,
    //B-F reserved.
};

typedef NS_ENUM(NSUInteger, JFRCloseCode) {
    JFRCloseCodeNormal                 = 1000,
    JFRCloseCodeGoingAway              = 1001,
    JFRCloseCodeProtocolError          = 1002,
    JFRCloseCodeProtocolUnhandledType  = 1003,
    // 1004 reserved.
    JFRCloseCodeNoStatusReceived       = 1005,
    //1006 reserved.
    JFRCloseCodeEncoding               = 1007,
    JFRCloseCodePolicyViolated         = 1008,
    JFRCloseCodeMessageTooBig          = 1009
};

typedef NS_ENUM(NSUInteger, JFRInternalErrorCode) {
    // 0-999 WebSocket status codes not used
    JFROutputStreamWriteError  = 1
};

#define kJFRInternalHTTPStatusWebSocket 101

//holds the responses in our read stack to properly process messages
@interface JFRResponse : NSObject

@property(nonatomic, assign)BOOL isFin;
//一个枚举值
@property(nonatomic, assign)JFROpCode code;
@property(nonatomic, assign)NSInteger bytesLeft;
@property(nonatomic, assign)NSInteger frameCount;
@property(nonatomic, strong)NSMutableData *buffer;

@end

@interface JFRWebSocket ()<NSStreamDelegate>

@property(nonatomic, strong, nonnull)NSURL *url;
@property(nonatomic, strong, null_unspecified)NSInputStream *inputStream;
@property(nonatomic, strong, null_unspecified)NSOutputStream *outputStream;
@property(nonatomic, strong, null_unspecified)NSOperationQueue *writeQueue;
@property(nonatomic, assign)BOOL isRunLoop;
@property(nonatomic, strong, nonnull)NSMutableArray *readStack;
@property(nonatomic, strong, nonnull)NSMutableArray *inputQueue;
@property(nonatomic, strong, nullable)NSData *fragBuffer;
@property(nonatomic, strong, nullable)NSMutableDictionary *headers;
@property(nonatomic, strong, nullable)NSArray *optProtocols;
@property(nonatomic, assign)BOOL isCreated;
@property(nonatomic, assign)BOOL didDisconnect;
@property(nonatomic, assign)BOOL certValidated;

@end

//Constant Header Values.
NS_ASSUME_NONNULL_BEGIN
static NSString *const headerWSUpgradeName     = @"Upgrade";
static NSString *const headerWSUpgradeValue    = @"websocket";
static NSString *const headerWSHostName        = @"Host";
static NSString *const headerWSConnectionName  = @"Connection";
static NSString *const headerWSConnectionValue = @"Upgrade";
static NSString *const headerWSProtocolName    = @"Sec-WebSocket-Protocol";
static NSString *const headerWSVersionName     = @"Sec-Websocket-Version";
static NSString *const headerWSVersionValue    = @"13";
static NSString *const headerWSKeyName         = @"Sec-WebSocket-Key";
static NSString *const headerOriginName        = @"Origin";
static NSString *const headerWSAcceptName      = @"Sec-WebSocket-Accept";
NS_ASSUME_NONNULL_END

//Class Constants
static char CRLFBytes[] = {'\r', '\n', '\r', '\n'};
static int BUFFER_MAX = 4096;

// This get the correct bits out by masking the bytes of the buffer.
static const uint8_t JFRFinMask             = 0x80;
static const uint8_t JFROpCodeMask          = 0x0F;
static const uint8_t JFRRSVMask             = 0x70;
static const uint8_t JFRMaskMask            = 0x80;
static const uint8_t JFRPayloadLenMask      = 0x7F;
static const size_t  JFRMaxFrameSize        = 32;

@implementation JFRWebSocket

/////////////////////////////////////////////////////////////////////////////
//Default initializer
- (instancetype)initWithURL:(NSURL *)url protocols:(NSArray*)protocols
{
    if(self = [super init])
    {
        //证书合法化的标志位-No
        self.certValidated = NO;
        //是否支持语音传输-No
        self.voipEnabled = NO;
        //允许不信任的链接或者自我签名
        self.selfSignedSSL = NO;
        //这个公开的OperationQueuez设置为主队列
        self.queue = dispatch_get_main_queue();
        self.url = url;
        self.readStack = [NSMutableArray new];
        self.inputQueue = [NSMutableArray new];
        //这是一个数组类型的的属性
        self.optProtocols = protocols;
    }
    
    return self;
}
/////////////////////////////////////////////////////////////////////////////
//Exposed method for connecting to URL provided in init method.
- (void)connect {
    //如果本对象已经s初始化好了，那么直接返回
    if(self.isCreated)
    {
        
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    //防止死锁
    dispatch_async(self.queue, ^
    {
        weakSelf.didDisconnect = NO;
    });

    //everything is on a background thread.
    //下面是一个并发队列，来进行异步调用
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
    {
        weakSelf.isCreated = YES;
        //进行连接前的http请求并且之后升级为websocket链接
      [weakSelf createHTTPRequest];
        //下方是对上面异步调用的一种保险的做法
        weakSelf.isCreated = NO;
    });
}
/////////////////////////////////////////////////////////////////////////////
- (void)disconnect {
    [self writeError:JFRCloseCodeNormal];
}
/////////////////////////////////////////////////////////////////////////////
- (void)writeString:(NSString*)string {
    //对string进行容错判断
    if(string) {
        //标记为你文本信息，并且发送出去
        [self dequeueWrite:[string dataUsingEncoding:NSUTF8StringEncoding]
                  withCode:JFROpCodeTextFrame];
    }
}
/////////////////////////////////////////////////////////////////////////////
- (void)writePing:(NSData*)data {
    [self dequeueWrite:data withCode:JFROpCodePing];
}
/////////////////////////////////////////////////////////////////////////////
- (void)writeData:(NSData*)data {
    [self dequeueWrite:data withCode:JFROpCodeBinaryFrame];
}
/////////////////////////////////////////////////////////////////////////////
- (void)addHeader:(NSString*)value forKey:(NSString*)key {
    if(!self.headers) {
        self.headers = [[NSMutableDictionary alloc] init];
    }
    [self.headers setObject:value forKey:key];
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - connect's internal supporting methods

/////////////////////////////////////////////////////////////////////////////

- (NSString *)origin;
{
    NSString *scheme = [_url.scheme lowercaseString];
    
    if ([scheme isEqualToString:@"wss"])
    {
        scheme = @"https";
    } else if ([scheme isEqualToString:@"ws"])
    {
        scheme = @"http";
    }
    
    if (_url.port) {
        return [NSString stringWithFormat:@"%@://%@:%@/", scheme, _url.host, _url.port];
    } else {
        return [NSString stringWithFormat:@"%@://%@/", scheme, _url.host];
    }
}


//Uses CoreFoundation to build a HTTP request to send over TCP stream.
- (void)createHTTPRequest
{
    //下方是基于CFNetwork的API,同NSURLconnection的API相比更加复杂，需要手工添加http头和cookies等信息
    //CFNetwork是建立在coreFoundation的CFSocket和CFStream的基础上的
    
    //利用self.url属性来进行创造CFURLRef对象
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)self.url.absoluteString, NULL);
    //设定HTTP的请求方式
    CFStringRef requestMethod = CFSTR("GET");
    //创造一个基于某种请求方式+url的Http的方法
    //请求的消息体
    //设置请求行
    CFHTTPMessageRef urlRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault,
                                                             requestMethod,
                                                             url,
                                                        kCFHTTPVersion1_1);
    //释放url,因为用不到url了，url已经保存到了消息体中
    CFRelease(url);
    //取得端口号
    NSNumber *port = _url.port;
//如果端口不存在,那么做容错处理----如果协议的名字为wss或者是https，那么端口号为443，反之则为http，端口为80
    if (!port)
    {
        if([self.url.scheme isEqualToString:@"wss"] || [self.url.scheme isEqualToString:@"https"]){
            port = @(443);
        } else
        {
            port = @(80);
        }
    }
    NSString *protocols = nil;
    //如果协议的数组中存在元素，那么得到这个数组用","来拼接每一个元素之后得到的字符串
    if([self.optProtocols count] > 0)
    {
        protocols = [self.optProtocols componentsJoinedByString:@","];
    }
    //下面的一系列的C函数都是在创建Http请求的参数,比如第一个就是设置host对应的值
    //headerWSHostName=@"host"
    //headerWSVersionName=Sec-Websocket-Version
    //headerWSVersionValue=@"13"
    //headerWSKeyName= @"Sec-WebSocket-Key"
    //generateWebSocketKey
    //设置host以及端口号;
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSHostName,
                                     (__bridge CFStringRef)[NSString stringWithFormat:@"%@:%@",self.url.host,port]);
    //设置websocket的版本号
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSVersionName,
                                     (__bridge CFStringRef)headerWSVersionValue);
    //设置websocket的一个key值
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSKeyName,
                                     (__bridge CFStringRef)[self generateWebSocketKey]);
    //headerWSUpgradeName=@"Upgrade"
    //headerWSUpgradeValue= @"websocket"
    //headerWSConnectionName=@"Connection"
    //headerWSConnectionValue=@"Upgrade"
    //设置http之后进行wesocket的协议升级动作
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSUpgradeName,
                                     (__bridge CFStringRef)headerWSUpgradeValue);
    //connection也进行升级
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSConnectionName,
                                     (__bridge CFStringRef)headerWSConnectionValue);
    if (protocols.length > 0)
    {
        //加入指定来交流的协议，那么http的请求头也必须进行设置相应的协议版本号
        CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                         (__bridge CFStringRef)headerWSProtocolName,
                                         (__bridge CFStringRef)protocols);
    }
   //origin属性也进行设置
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerOriginName,
                                     (__bridge CFStringRef)[self origin]);
    //self.headers是一个字典类型的属性
    for(NSString *key in self.headers)
    {
        //针对key也进行设置信息
        CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                         (__bridge CFStringRef)key,
                                         (__bridge CFStringRef)self.headers[key]);
    }
    
#if defined(DEBUG)
    NSLog(@"urlRequest = \"%@\"", urlRequest);
#endif
    //转化CF对象为OC对象--一个NSData对象
    NSData *serializedRequest = (__bridge_transfer NSData *)(CFHTTPMessageCopySerializedMessage(urlRequest));
    //将这个建立websocket的http的请求放入NSStream，并且初始化两个读写流
    [self initStreamsWithData:serializedRequest port:port];
    CFRelease(urlRequest);
}
/////////////////////////////////////////////////////////////////////////////
//Random String of 16 lowercase chars, SHA1 and base64 encoded.
- (NSString*)generateWebSocketKey
{
    //种子
    NSInteger seed = 16;
    NSMutableString *string = [NSMutableString stringWithCapacity:seed];
    for (int i = 0; i < seed; i++)
    {
        [string appendFormat:@"%C", (unichar)('a' + arc4random_uniform(25))];
    }
    return [[string dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}
/////////////////////////////////////////////////////////////////////////////
//Sets up our reader/writer for the TCP stream.
- (void)initStreamsWithData:(NSData*)data port:(NSNumber*)port {
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    //绑定url的主机和端口以及读写流
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.url.host, [port intValue], &readStream, &writeStream);
    //下方都是将普通的CF对象转化为OC对象
    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.inputStream.delegate = self;
    self.outputStream = (__bridge_transfer NSOutputStream *)writeStream;
    self.outputStream.delegate = self;
    //如果读写流都涉及安全相关的，那么对读写流进行设置
    if([self.url.scheme isEqualToString:@"wss"] || [self.url.scheme isEqualToString:@"https"])
    {
        [self.inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
        [self.outputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    } else
    {
        self.certValidated = YES; //not a https session, so no need to check SSL pinning
    }
    if(self.voipEnabled)
    {
        //假如支持语音的情况，则一样设置相关的属性
        [self.inputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
        [self.outputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
    }
    if(self.selfSignedSSL)
    {
        //如果支持不安全的websocket链接
        NSString *chain = (__bridge_transfer NSString *)kCFStreamSSLValidatesCertificateChain;
        NSString *peerName = (__bridge_transfer NSString *)kCFStreamSSLValidatesCertificateChain;
        NSString *key = (__bridge_transfer NSString *)kCFStreamPropertySSLSettings;
        NSDictionary *settings = @{chain: [[NSNumber alloc] initWithBool:NO],
                                   peerName: [NSNull null]};
        [self.inputStream setProperty:settings forKey:key];
        [self.outputStream setProperty:settings forKey:key];
    }
    self.isRunLoop = YES;
    //
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.inputStream open];
    [self.outputStream open];
    size_t dataLen = [data length];
    //将data字节流写入输入流向
    [self.outputStream write:[data bytes] maxLength:dataLen];
    while (self.isRunLoop)
    {
        //使其Runloop运转起来
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - NSStreamDelegate

/////////////////////////////////////////////////////////////////////////////
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    /*
        NSStreamEventNone = 0,
        NSStreamEventOpenCompleted = 1UL << 0,
        NSStreamEventHasBytesAvailable = 1UL << 1,
        NSStreamEventHasSpaceAvailable = 1UL << 2,
        NSStreamEventErrorOccurred = 1UL << 3,
        NSStreamEventEndEncountered = 1UL << 4
     **/
    if(self.security && !self.certValidated && (eventCode == NSStreamEventHasBytesAvailable || eventCode == NSStreamEventHasSpaceAvailable))
    {
        //引出SSL的peerTrust与主机名
        SecTrustRef trust = (__bridge SecTrustRef)([aStream propertyForKey:(__bridge_transfer NSString *)kCFStreamPropertySSLPeerTrust]);
        NSString *domain = [aStream propertyForKey:(__bridge_transfer NSString *)kCFStreamSSLPeerName];
        if([self.security isValid:trust domain:domain])
        {
            self.certValidated = YES;
        } else
        {
            [self disconnectStream:[self errorWithDetail:@"Invalid SSL certificate" code:1]];
            return;
        }
    }
    switch (eventCode) {
        case NSStreamEventNone:
            break;
            
        case NSStreamEventOpenCompleted:
            break;
            
        case NSStreamEventHasBytesAvailable:
            if(aStream == self.inputStream)
            {
                [self processInputStream];
            }
            break;
            
        case NSStreamEventHasSpaceAvailable:
            break;
            
        case NSStreamEventErrorOccurred:
            [self disconnectStream:[aStream streamError]];
            break;
            
        case NSStreamEventEndEncountered:
            [self disconnectStream:nil];
            break;
            
        default:
            break;
    }
}
/////////////////////////////////////////////////////////////////////////////
- (void)disconnectStream:(NSError*)error {
    [self.writeQueue waitUntilAllOperationsAreFinished];
    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream close];
    [self.inputStream close];
    self.outputStream = nil;
    self.inputStream = nil;
    self.isRunLoop = NO;
    _isConnected = NO;
    self.certValidated = NO;
    [self doDisconnect:error];
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - Stream Processing Methods

/////////////////////////////////////////////////////////////////////////////
- (void)processInputStream {
    @autoreleasepool {
        //BuFFer_mAX=4096，为2的12次方->4k的大小
        uint8_t buffer[BUFFER_MAX];
        //返回的值为字节数
        NSInteger length = [self.inputStream read:buffer maxLength:BUFFER_MAX];
        if(length > 0) {
            //处理websocket握手的阶段
            if(!self.isConnected)
            {
                CFIndex responseStatusCode;
                BOOL status = [self processHTTP:buffer length:length responseStatusCode:&responseStatusCode];
#if defined(DEBUG)
                if (length < BUFFER_MAX) {
                    buffer[length] = 0x00;
                } else {
                    buffer[BUFFER_MAX - 1] = 0x00;
                }
                NSLog(@"response (%ld) = \"%s\"", responseStatusCode, buffer);
#endif
                if(status == NO) {
                    [self doDisconnect:[self errorWithDetail:@"Invalid HTTP upgrade" code:1 userInfo:@{@"HTTPResponseStatusCode" : @(responseStatusCode)}]];
                }
            } else
            {
                BOOL process = NO;
                if(self.inputQueue.count == 0) {
                    process = YES;
                }
                [self.inputQueue addObject:[NSData dataWithBytes:buffer length:length]];
                if(process) {
                    [self dequeueInput];
                }
            }
        }
    }
}
/////////////////////////////////////////////////////////////////////////////
- (void)dequeueInput {
    if(self.inputQueue.count > 0) {
        NSData *data = [self.inputQueue objectAtIndex:0];
        NSData *work = data;
        if(self.fragBuffer) {
            NSMutableData *combine = [NSMutableData dataWithData:self.fragBuffer];
            [combine appendData:data];
            work = combine;
            self.fragBuffer = nil;
        }
        [self processRawMessage:(uint8_t*)work.bytes length:work.length];
        [self.inputQueue removeObject:data];
        [self dequeueInput];
    }
}
/////////////////////////////////////////////////////////////////////////////
//Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
- (BOOL)processHTTP:(uint8_t*)buffer length:(NSInteger)bufferLen responseStatusCode:(CFIndex*)responseStatusCode {
    int k = 0;
    //下方为找到body的主体
    NSInteger totalSize = 0;
    for(int i = 0; i < bufferLen; i++) {
        if(buffer[i] == CRLFBytes[k]) {
            k++;
            if(k == 3) {
                totalSize = i + 1;
                break;
            }
        } else {
            k = 0;
        }
    }
    //
    if(totalSize > 0) {
        BOOL status = [self validateResponse:buffer length:totalSize responseStatusCode:responseStatusCode];
        if (status == YES) {
            _isConnected = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_async(self.queue,^{
                if([self.delegate respondsToSelector:@selector(websocketDidConnect:)]) {
                    [weakSelf.delegate websocketDidConnect:self];
                }
                if(weakSelf.onConnect) {
                    weakSelf.onConnect();
                }
            });
            totalSize += 1; //skip the last \n
            NSInteger  restSize = bufferLen-totalSize;
            if(restSize > 0) {
                [self processRawMessage:(buffer+totalSize) length:restSize];
            }
        }
        return status;
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////
//Validate the HTTP is a 101, as per the RFC spec.
- (BOOL)validateResponse:(uint8_t *)buffer length:(NSInteger)bufferLen responseStatusCode:(CFIndex*)responseStatusCode {
    CFHTTPMessageRef response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);
    CFHTTPMessageAppendBytes(response, buffer, bufferLen);
    *responseStatusCode = CFHTTPMessageGetResponseStatusCode(response);
    BOOL status = ((*responseStatusCode) == kJFRInternalHTTPStatusWebSocket)?(YES):(NO);
    if(status == NO) {
        CFRelease(response);
        return NO;
    }
    NSDictionary *headers = (__bridge_transfer NSDictionary *)(CFHTTPMessageCopyAllHeaderFields(response));
    NSString *acceptKey = headers[headerWSAcceptName];
    CFRelease(response);
    if(acceptKey.length > 0) {
        return YES;
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////
-(void)processRawMessage:(uint8_t*)buffer length:(NSInteger)bufferLen {
    JFRResponse *response = [self.readStack lastObject];
    if(response && bufferLen < 2) {
        self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
        return;
    }
    if(response.bytesLeft > 0) {
        NSInteger len = response.bytesLeft;
        NSInteger extra =  bufferLen - response.bytesLeft;
        if(response.bytesLeft > bufferLen) {
            len = bufferLen;
            extra = 0;
        }
        response.bytesLeft -= len;
        [response.buffer appendData:[NSData dataWithBytes:buffer length:len]];
        [self processResponse:response];
        NSInteger offset = bufferLen - extra;
        if(extra > 0) {
            [self processExtra:(buffer+offset) length:extra];
        }
        return;
    } else {
        if(bufferLen < 2) { // we need at least 2 bytes for the header
            self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
            return;
        }
        BOOL isFin = (JFRFinMask & buffer[0]);
        uint8_t receivedOpcode = (JFROpCodeMask & buffer[0]);
        BOOL isMasked = (JFRMaskMask & buffer[1]);
        uint8_t payloadLen = (JFRPayloadLenMask & buffer[1]);
        NSInteger offset = 2; //how many bytes do we need to skip for the header
        if((isMasked  || (JFRRSVMask & buffer[0])) && receivedOpcode != JFROpCodePong) {
            [self doDisconnect:[self errorWithDetail:@"masked and rsv data is not currently supported" code:JFRCloseCodeProtocolError]];
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        BOOL isControlFrame = (receivedOpcode == JFROpCodeConnectionClose || receivedOpcode == JFROpCodePing);
        if(!isControlFrame && (receivedOpcode != JFROpCodeBinaryFrame && receivedOpcode != JFROpCodeContinueFrame && receivedOpcode != JFROpCodeTextFrame && receivedOpcode != JFROpCodePong)) {
            [self doDisconnect:[self errorWithDetail:[NSString stringWithFormat:@"unknown opcode: 0x%x",receivedOpcode] code:JFRCloseCodeProtocolError]];
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        if(isControlFrame && !isFin) {
            [self doDisconnect:[self errorWithDetail:@"control frames can't be fragmented" code:JFRCloseCodeProtocolError]];
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        if(receivedOpcode == JFROpCodeConnectionClose) {
            //the server disconnected us
            uint16_t code = JFRCloseCodeNormal;
            if(payloadLen == 1) {
                code = JFRCloseCodeProtocolError;
            }
            else if(payloadLen > 1) {
                code = CFSwapInt16BigToHost(*(uint16_t *)(buffer+offset) );
                if(code < 1000 || (code > 1003 && code < 1007) || (code > 1011 && code < 3000)) {
                    code = JFRCloseCodeProtocolError;
                }
                offset += 2;
            }
            
            if(payloadLen > 2) {
                NSInteger len = payloadLen-2;
                if(len > 0) {
                    NSData *data = [NSData dataWithBytes:(buffer+offset) length:len];
                    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if(!str) {
                        code = JFRCloseCodeProtocolError;
                    }
                }
            }
            [self writeError:code];
            [self doDisconnect:[self errorWithDetail:@"continue frame before a binary or text frame" code:code]];
            return;
        }
        if(isControlFrame && payloadLen > 125) {
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        NSInteger dataLength = payloadLen;
        if(payloadLen == 127) {
            dataLength = (NSInteger)CFSwapInt64BigToHost(*(uint64_t *)(buffer+offset));
            offset += sizeof(uint64_t);
        } else if(payloadLen == 126) {
            dataLength = CFSwapInt16BigToHost(*(uint16_t *)(buffer+offset) );
            offset += sizeof(uint16_t);
        }
        if(bufferLen < offset) { // we cannot process this yet, nead more header data
            self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
            return;
        }
        NSInteger len = dataLength;
        if(dataLength > (bufferLen-offset) || (bufferLen - offset) < dataLength) {
            len = bufferLen-offset;
        }
        NSData *data = nil;
        if(len < 0) {
            len = 0;
            data = [NSData data];
        } else {
            data = [NSData dataWithBytes:(buffer+offset) length:len];
        }
        if(receivedOpcode == JFROpCodePong) {
            NSInteger step = (offset+len);
            NSInteger extra = bufferLen-step;
            if(extra > 0) {
                [self processRawMessage:(buffer+step) length:extra];
            }
            return;
        }
        JFRResponse *response = [self.readStack lastObject];
        if(isControlFrame) {
            response = nil; //don't append pings
        }
        if(!isFin && receivedOpcode == JFROpCodeContinueFrame && !response) {
            [self doDisconnect:[self errorWithDetail:@"continue frame before a binary or text frame" code:JFRCloseCodeProtocolError]];
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        BOOL isNew = NO;
        if(!response) {
            if(receivedOpcode == JFROpCodeContinueFrame) {
                [self doDisconnect:[self errorWithDetail:@"first frame can't be a continue frame" code:JFRCloseCodeProtocolError]];
                [self writeError:JFRCloseCodeProtocolError];
                return;
            }
            isNew = YES;
            response = [JFRResponse new];
            response.code = receivedOpcode;
            response.bytesLeft = dataLength;
            response.buffer = [NSMutableData dataWithData:data];
        } else {
            if(receivedOpcode == JFROpCodeContinueFrame) {
                response.bytesLeft = dataLength;
            } else {
                [self doDisconnect:[self errorWithDetail:@"second and beyond of fragment message must be a continue frame" code:JFRCloseCodeProtocolError]];
                [self writeError:JFRCloseCodeProtocolError];
                return;
            }
            [response.buffer appendData:data];
        }
        response.bytesLeft -= len;
        response.frameCount++;
        response.isFin = isFin;
        if(isNew) {
            [self.readStack addObject:response];
        }
        [self processResponse:response];
        
        NSInteger step = (offset+len);
        NSInteger extra = bufferLen-step;
        if(extra > 0) {
            [self processExtra:(buffer+step) length:extra];
        }
    }
    
}
/////////////////////////////////////////////////////////////////////////////
- (void)processExtra:(uint8_t*)buffer length:(NSInteger)bufferLen {
    if(bufferLen < 2) {
        self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
    } else {
        [self processRawMessage:buffer length:bufferLen];
    }
}
/////////////////////////////////////////////////////////////////////////////
- (BOOL)processResponse:(JFRResponse*)response {
    if(response.isFin && response.bytesLeft <= 0) {
        NSData *data = response.buffer;
        if(response.code == JFROpCodePing) {
            [self dequeueWrite:response.buffer withCode:JFROpCodePong];
        } else if(response.code == JFROpCodeTextFrame) {
            NSString *str = [[NSString alloc] initWithData:response.buffer encoding:NSUTF8StringEncoding];
            if(!str) {
                [self writeError:JFRCloseCodeEncoding];
                return NO;
            }
            __weak typeof(self) weakSelf = self;
            dispatch_async(self.queue,^{
                if([weakSelf.delegate respondsToSelector:@selector(websocket:didReceiveMessage:)]) {
                    [weakSelf.delegate websocket:weakSelf didReceiveMessage:str];
                }
                if(weakSelf.onText) {
                    weakSelf.onText(str);
                }
            });
        } else if(response.code == JFROpCodeBinaryFrame) {
            __weak typeof(self) weakSelf = self;
            dispatch_async(self.queue,^{
                if([weakSelf.delegate respondsToSelector:@selector(websocket:didReceiveData:)]) {
                    [weakSelf.delegate websocket:weakSelf didReceiveData:data];
                }
                if(weakSelf.onData) {
                    weakSelf.onData(data);
                }
            });
        }
        [self.readStack removeLastObject];
        return YES;
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////
-(void)dequeueWrite:(NSData*)data withCode:(JFROpCode)code
{
    //判断是否处于链接阶段
    if(!self.isConnected)
    {
        return;
    }
    //"懒加载"初始化NSOperationQueue对象,并且设置相应的属性,这是一个操作队列对象
    if(!self.writeQueue)
    {
        self.writeQueue = [[NSOperationQueue alloc] init];
        self.writeQueue.maxConcurrentOperationCount = 1;
    }
    
    __weak typeof(self) weakSelf = self;
    //输入操作对象
    [self.writeQueue addOperationWithBlock:^{
        if(!weakSelf || !weakSelf.isConnected)
        {
            return;
        }
        typeof(weakSelf) strongSelf = weakSelf;
        //注意是int64_t类型的offset，
        uint64_t offset = 2; //how many bytes do we need to skip for the header
        //下方返回的是通用指针，故需要转型,uint8_t指的是八个字节的数据类型
        uint8_t *bytes = (uint8_t*)[data bytes];
        //lenghth方法返回的就是NSInteger，这个数据类型在64位上就是64位的数据类型,所以需要用uint64_t来接受
        uint64_t dataLength = data.length;
        //(32+x)*8*bit=>32+x个byte的容量
        NSMutableData *frame = [[NSMutableData alloc] initWithLength:(NSInteger)(dataLength + JFRMaxFrameSize)];
        uint8_t *buffer = (uint8_t*)[frame mutableBytes];
        //code是JFROpCode类型的
        /*
         JFROpCodeContinueFrame = 0x0,
         JFROpCodeTextFrame = 0x1,
         JFROpCodeBinaryFrame = 0x2,
         //3-7 are reserved.
         JFROpCodeConnectionClose = 0x8,
         JFROpCodePing = 0x9,
         JFROpCodePong = 0xA,
         **/
        /*
         static const uint8_t JFRFinMask             = 0x80;
         static const uint8_t JFROpCodeMask          = 0x0F;
         static const uint8_t JFRRSVMask             = 0x70;
         static const uint8_t JFRMaskMask            = 0x80;
         static const uint8_t JFRPayloadLenMask      = 0x7F;
         static const size_t  JFRMaxFrameSize        = 32;
         **/
        //按位或操作，倒数位7（即第八位）与code进行按位与操作,一般情况下这个为1，否则表示为最后一个分片
        //具体来说是：Fin为置为1，剩下的三个RSV设置为0，然后，opcode领域都设置为0，并且有一个JFROpCode类型的枚举用来
        //将opcode域的不同位设置成相应的1数字->以此来表明数据的类型,通过与不同枚举之间进行按位与的操作，来进行设置
        buffer[0] = JFRFinMask | code;
        //下方是与websocket的格式有关系,datalength为125、126、127的效果均不同
        //如果数据长度小于126，那么接下来的8位则表示为数据的长度-因为8位最大可表示的十进制数字可以包含125
        if(dataLength < 126)
        {
            
            //0与任何数据进行按位与都得到那个数据
            //注意buffer是一个uint8_t *类型的数据buffer[1]不是位于第2位，而是位于第9位开始后的八位的范围,
            buffer[1] |= dataLength;
            // 65535 =UINT16_MAX位于stdint.h中
        }
        //如果16位的二进制可以表示现有的长度，那么则接下来的八位写成126
        else if(dataLength <= UINT16_MAX)
        {
            buffer[1] |= 126;
            //现在设置为126，那么接下来的两个byte都是表示的长度，并且是大端序的，一共16个bit
            *((uint16_t *)(buffer + offset)) = CFSwapInt16BigToHost((uint16_t)dataLength);
            //相当于offset+2=4
            offset += sizeof(uint16_t);
        } else
        {
            buffer[1] |= 127;
            //首先buffer起点之后的8个字节
            //大小端的转化
            //现在设置为127，那么接下来的8个byte设置为长度的数据,并且偏移值涨到第十个byte
            *((uint64_t *)(buffer + offset)) = CFSwapInt64BigToHost((uint64_t)dataLength);
            //offset+8=10
            //sizeof算得结果的单位是字节
            offset += sizeof(uint64_t);
            //最大的长度情况已经表示，现在跳到maskingKey开始处
        }
        BOOL isMask = YES;
        if(isMask)
        {
            //这里是设置mask位为1，按位与操作-和上方设置Fin位是一样的情况
            buffer[1] |= JFRMaskMask;
            //设置指针值指向maskKey的开始
            uint8_t *mask_key = (buffer + offset);
            //这个是不需要种子的随机数生成器，不同于arcRandom()等伪随机函数--需要提供种子,第二个参数是指明产生随机数的大小-单位是byte,而第三个参数是一个指针，传入这个指针用来只想这个随机数,这个mask_key在websocket的消息当中占用32位-即4个byte
            (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(uint32_t), (uint8_t *)mask_key);
            //此处也要跳过mask_key区域
            offset += sizeof(uint32_t);
            //
            for (size_t i = 0; i < dataLength; i++)
            {
                //size_t在这里是算出来是8个byte的大小->为64位
                //这里的bytes是uint_8类型的的数据-经过转化过后的输入的数据
                //这里是貌似是编码的过程,sizeof(uint32_t)的结果是4,四个byte中顺序进行按位与的操作（注意一下；32/4=8<=>uint8_t<=>(uint8_t *)mask_key）,一共进行datalength次，声明一下
                /*
                 uint8_t *bytes = (uint8_t*)[data bytes];
                 //lenghth方法返回的就是NSInteger，这个数据类型在64位上就是64位的数据类型,所以需要用uint64_t来接受
                 uint64_t dataLength = data.length;
                 **/
                //uint8_t *buffer
                //这里datalenghth是按照64位来划分的
                //在设置好mask_key之后,接下来的payload当中，每8位的实际负载数据当中，得到的是实际的数据和得到的4个的byte大小的mask-key的数据中的
                //0～3的位置顺序进行按位异或的操作
                //传入进来的数据被分开位好几部分，每个部分之间的开头都相差64位的距离
                buffer[offset] = bytes[i] ^ mask_key[i % sizeof(uint32_t)];
                //uint64_t offset
                offset += 1;
            }
        }
        //如果没有用mask
        else
        {
            for(size_t i = 0; i < dataLength; i++)
            {
                //不需要进行按位异或的操作
                buffer[offset] = bytes[i];
                offset += 1;
            }
        }
        //这里total的意思是写入了多少，就会将total递增上写入的字节数，也会调整能够写入的剩下的最大的字节数
        uint64_t total = 0;
        while (true) {
            if(!strongSelf.isConnected || !strongSelf.outputStream)
            {
                //如果没有链接或者没有存在输出stream的情况下
                break;
            }
            NSInteger len = [strongSelf.outputStream write:([frame bytes]+total) maxLength:(NSInteger)(offset-total)];
            if(len < 0 || len == NSNotFound)
            {
                NSError *error = strongSelf.outputStream.streamError;
                if(!error)
                {
                    error = [strongSelf errorWithDetail:@"output stream error during write" code:JFROutputStreamWriteError];
                }
                [strongSelf doDisconnect:error];
                break;
            } else
            {
                //如果输入成功，那么length递增
                total += len;
            }
            if(total >= offset)
            {
                //如果总数大于来偏移值，那么跳出循环，这里表示已经将得到的数据输入完毕
                break;
            }
        }
    }];
}
/////////////////////////////////////////////////////////////////////////////
- (void)doDisconnect:(NSError*)error {
    if(!self.didDisconnect) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(self.queue, ^{
            weakSelf.didDisconnect = YES;
            [weakSelf disconnect];
            if([weakSelf.delegate respondsToSelector:@selector(websocketDidDisconnect:error:)]) {
                [weakSelf.delegate websocketDidDisconnect:weakSelf error:error];
            }
            if(weakSelf.onDisconnect) {
                weakSelf.onDisconnect(error);
            }
        });
    }
}
/////////////////////////////////////////////////////////////////////////////
- (NSError*)errorWithDetail:(NSString*)detail code:(NSInteger)code
{
    return [self errorWithDetail:detail code:code userInfo:nil];
}
- (NSError*)errorWithDetail:(NSString*)detail code:(NSInteger)code userInfo:(NSDictionary *)userInfo
{
    NSMutableDictionary* details = [NSMutableDictionary dictionary];
    details[detail] = NSLocalizedDescriptionKey;
    if (userInfo) {
        [details addEntriesFromDictionary:userInfo];
    }
    return [[NSError alloc] initWithDomain:@"JFRWebSocket" code:code userInfo:details];
}
/////////////////////////////////////////////////////////////////////////////
- (void)writeError:(uint16_t)code {
    uint16_t buffer[1];
    buffer[0] = CFSwapInt16BigToHost(code);
    [self dequeueWrite:[NSData dataWithBytes:buffer length:sizeof(uint16_t)] withCode:JFROpCodeConnectionClose];
}
/////////////////////////////////////////////////////////////////////////////
- (void)dealloc {
    if(self.isConnected) {
        [self disconnect];
    }
}
/////////////////////////////////////////////////////////////////////////////
@end

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
@implementation JFRResponse

@end
/////////////////////////////////////////////////////////////////////////////
