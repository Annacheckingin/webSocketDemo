//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  JFRSecurity.m
//
//  Created by Austin and Dalton Cherry on on 9/3/15.
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

#import "JFRSecurity.h"

@interface JFRSSLCert ()

@property(nonatomic, strong)NSData *certData;
//密钥类型
@property(nonatomic)SecKeyRef key;

@end

@implementation JFRSSLCert

/////////////////////////////////////////////////////////////////////////////
- (instancetype)initWithData:(NSData *)data
{
    if(self = [super init]) {
        //是一个NSData对象
        self.certData = data;
    }
    return self;
}
////////////////////////////////////////////////////////////////////////////
- (instancetype)initWithKey:(SecKeyRef)key
{
    if(self = [super init]) {
        self.key = key;
    }
    return self;
}
////////////////////////////////////////////////////////////////////////////
//dealloc方法当中对这个SecKeyRef进行释放
- (void)dealloc {
    if(self.key) {
        CFRelease(self.key);
    }
}
////////////////////////////////////////////////////////////////////////////

@end

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////

@interface JFRSecurity ()
//需要对密钥进行加密解密
@property(nonatomic)BOOL isReady; //is the key processing done?
//证书数组
@property(nonatomic, strong)NSMutableArray *certificates;
//公钥对数组
@property(nonatomic, strong)NSMutableArray *pubKeys;
//是否利用公钥
@property(nonatomic)BOOL usePublicKeys;

@end

@implementation JFRSecurity

/////////////////////////////////////////////////////////////////////////////
//
- (instancetype)initUsingPublicKeys:(BOOL)publicKeys {
//对bundle进行扫描,bundle指的是当前的代码文件夹，这里在当前的文件夹中搜索cer类型的文件，返回值是一个数组，数组里边的是一些文件路径名
    NSArray *paths = [[NSBundle mainBundle] pathsForResourcesOfType:@"cer" inDirectory:@"."];
    NSMutableArray<JFRSSLCert*> *collect = [NSMutableArray array];
    for(NSString *path in paths)
    {
        //通过这些文件名来加载NSData对象
        NSData *data = [NSData dataWithContentsOfFile:path];
        //如果这个NSData对象存在，那么在这个collect当中根据这个NSData对象来生成JFRSSLert对象并且添加
        if(data)
        {
            [collect addObject:[[JFRSSLCert alloc] initWithData:data]];
        }
    }
    //
    return [self initWithCerts:collect publicKeys:publicKeys];
}
/////////////////////////////////////////////////////////////////////////////
- (instancetype)initWithCerts:(NSArray<JFRSSLCert*>*)certs publicKeys:(BOOL)publicKeys {
    if(self = [super init])
    {
        //这个标志位设置为YES
        /*
          Should the domain name be validated? Default is YES.
          */
        // @property(nonatomic)BOOL validatedDN;
       //证书是否合法
        self.validatedDN = YES;
        //是否用了publicvkeys的标志位设为YES
        self.usePublicKeys = publicKeys;
        //如果确实用了publickeys的情况
        if(self.usePublicKeys)
        {
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
                //解密证书会花些时间，所以使用并发队列+异步
                NSMutableArray *collect = [NSMutableArray array];
                for(JFRSSLCert *cert in certs)
                {
                    //如果certData存在，cer.key不存在的情况下-即（服务器的公钥）密钥不存在的情况下(可能是没有提取出来)
                    if(cert.certData && !cert.key)
                    {
                    /**
                     - (SecKeyRef)extractPublicKey:(NSData*)data {
                         SecCertificateRef possibleKey = SecCertificateCreateWithData(nil,(__bridge CFDataRef)data);
                         SecPolicyRef policy = SecPolicyCreateBasicX509();
                         SecKeyRef key = [self extractPublicKeyFromCert:possibleKey policy:policy];
                         CFRelease(policy);
                         CFRelease(possibleKey);
                         return key;
                     }
                     /////////////////////////////////////////////////////////////////////////////
                     - (SecKeyRef)extractPublicKeyFromCert:(SecCertificateRef)cert policy:(SecPolicyRef)policy {
                         
                         SecTrustRef trust;
                         SecTrustCreateWithCertificates(cert,policy,&trust);
                         SecTrustResultType result = kSecTrustResultInvalid;
                         SecTrustEvaluate(trust,&result);
                         SecKeyRef key = SecTrustCopyPublicKey(trust);
                         CFRelease(trust);
                         return key;
                     }
                     */
                        //得到证书中的key
                        cert.key = [self extractPublicKey:cert.certData];
                    }
                    //如果cert.key存在的话，那么直接添加进入这个collect当中
                    if(cert.key)
                    {
                        //Cf对象的生命周期转交给ARC保管
                        [collect addObject:CFBridgingRelease(cert.key)];
                    }
                }
                //将这个collect赋值为self.certificates
                self.certificates = collect;
                //这个isReady的标志位设置为YES
                //证书的解密已经完成
                self.isReady = YES;
            });
        }
        else
        {
//在没有用公钥匙的情况,certificatesi直接添加的是NSData类型的certData,如果用了公钥的情况下，则添加的是SecKeyRef类型的key，这歌certData和secKeyRef类型都是位于工具类Security中的属性
            NSMutableArray<NSData*> *collect = [NSMutableArray array];
            for(JFRSSLCert *cert in certs)
            {
                if(cert.certData)
                {
                    [collect addObject:cert.certData];
                }
            }
            self.certificates = collect;
            self.isReady = YES;
        }
    }
    return self;
}
/////////////////////////////////////////////////////////////////////////////
- (BOOL)isValid:(SecTrustRef)trust domain:(NSString*)domain {
    int tries = 0;
    //等待解密出公钥-如果5000毫秒都没成功-认为是失败-则不合法
    while (!self.isReady)
    {
        usleep(1000);
        tries++;
        if(tries > 5) {
            return NO; //doesn't appear it is going to ever be ready...
        }
    }
    //保证了公钥合法的情况下
    BOOL status = NO;
    SecPolicyRef policy;
    //
    if(self.validatedDN) {
        policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)domain);
    } else {
        policy = SecPolicyCreateBasicX509();
    }
    SecTrustSetPolicies(trust,policy);
    //使用公钥的情况
    if(self.usePublicKeys) {
        //trust为植入在操作系统内部的信任
        for(id serverKey in [self publicKeyChainForTrust:trust])
        {
            for(id keyObj in self.pubKeys)
            {
                if([serverKey isEqual:keyObj])
                {
                    status = YES;
                    break;
                }
            }
        }
    } else
    {
        //不使用公钥的情况
        
        //得到证书信任链条
        NSArray *serverCerts = [self certificateChainForTrust:trust];
        NSMutableArray *collect = [NSMutableArray arrayWithCapacity:self.certificates.count];
        for(NSData *data in self.certificates)
        {
            [collect addObject:CFBridgingRelease(SecCertificateCreateWithData(nil,(__bridge CFDataRef)data))];
        }
        //
        SecTrustSetAnchorCertificates(trust,(__bridge CFArrayRef)collect);
        SecTrustResultType result = 0;
        //在result上体现出对trust的判断结果
        SecTrustEvaluate(trust,&result);
        if(result == kSecTrustResultUnspecified || result == kSecTrustResultProceed)
        {
            NSInteger trustedCount = 0;
            for(NSData *serverData in serverCerts)
            {
                //
                for(NSData *certData in self.certificates)
                {
                    //判断来自severData中的证书和本地来自操作系统的证书比较
                    if([certData isEqualToData:serverData])
                    {
                        trustedCount++;
                        break;
                    }
                }
            }
            //如果能全部对号入座地相等
            if(trustedCount == serverCerts.count) {
                status = YES;
            }
        }
    }
    
    CFRelease(policy);
    return status;
}
/////////////////////////////////////////////////////////////////////////////
//制造SecKeyRef，通过证书中的NSData对象得到公钥
- (SecKeyRef)extractPublicKey:(NSData*)data
{
    SecCertificateRef possibleKey = SecCertificateCreateWithData(nil,(__bridge CFDataRef)data);
    //得到一个信任的事务对象
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    SecKeyRef key = [self extractPublicKeyFromCert:possibleKey policy:policy];
    CFRelease(policy);
    CFRelease(possibleKey);
    return key;
}
/////////////////////////////////////////////////////////////////////////////
- (SecKeyRef)extractPublicKeyFromCert:(SecCertificateRef)cert policy:(SecPolicyRef)policy {
    
    SecTrustRef trust;
    SecTrustCreateWithCertificates(cert,policy,&trust);
    SecTrustResultType result = kSecTrustResultInvalid;
    SecTrustEvaluate(trust,&result);
    SecKeyRef key = SecTrustCopyPublicKey(trust);
    CFRelease(trust);
    return key;
}
/////////////////////////////////////////////////////////////////////////////
- (NSArray*)certificateChainForTrust:(SecTrustRef)trust
{
    NSMutableArray *collect = [NSMutableArray array];
    for(int i = 0; i < SecTrustGetCertificateCount(trust); i++) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust,i);
        if(cert) {
            [collect addObject:CFBridgingRelease(SecCertificateCopyData(cert))];
        }
    }
    return collect;
}
/////////////////////////////////////////////////////////////////////////////
- (NSArray*)publicKeyChainForTrust:(SecTrustRef)trust {
    NSMutableArray *collect = [NSMutableArray array];
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    for(int i = 0; i < SecTrustGetCertificateCount(trust); i++) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust,i);
        SecKeyRef key = [self extractPublicKeyFromCert:cert policy:policy];
        if(key) {
            [collect addObject:CFBridgingRelease(key)];
        }
    }
    CFRelease(policy);
    return collect;
}
/////////////////////////////////////////////////////////////////////////////

@end
