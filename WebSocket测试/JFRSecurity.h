//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  JFRSecurity.h
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

#import <Foundation/Foundation.h>
#import <Security/Security.h>

@interface JFRSSLCert : NSObject

/**
 //指明init for 证书
 Designated init for certificates
 //用于证书的二进制数据
 :param: data is the binary data of the certificate
 //一个将来会用到的代表安全的对象
 :returns: a representation security object to be used with
 */
- (instancetype)initWithData:(NSData *)data;


/**
 //为公钥指明init的函数
 Designated init for public keys
 //参数是用于公钥
 :param: key is the public key to be used
 //返回会用到的一个用于安全的对象
 :returns: a representation security object to be used with
 */
- (instancetype)initWithKey:(SecKeyRef)key;

@end

@interface JFRSecurity : NSObject

/**
 用到从app bundle来的必然会用到的事物
 Use certs from main app bundle
 //最后一个参数是用于判断是否公钥或者证书是否应该用于SSL的填塞确认
 :param usePublicKeys: is to specific if the publicKeys or certificates should be used for SSL pinning validation
 
 :returns: a representation security object to be used with
 */

- (instancetype)initWithCerts:(NSArray<JFRSSLCert*>*)certs publicKeys:(BOOL)publicKeys;

/**
 Designated init
 
 :param keys: is the certificates or public keys to use
 :param usePublicKeys: is to specific if the publicKeys or certificates should be used for SSL pinning validation
 
 :returns: a representation security object to be used with
 */
//这个方法用于本地含有cer类型的文件的情况下，传入一个BOOL类型的值来生成JFRSecurity
- (instancetype)initUsingPublicKeys:(BOOL)publicKeys;

/**
 //是否这个domian的名字应该被验证，默认的值是YES
 Should the domain name be validated? Default is YES.
 */
@property(nonatomic)BOOL validatedDN;

/**
 合法化-如果正式是合法的或者不合法
 Validate if the cert is legit or not.
 :param:  trust is the trust to validate
 //
 :param: domain to validate along with the trust (can be nil)
 :return: YES or NO if valid.
 */
- (BOOL)isValid:(SecTrustRef)trust domain:(NSString*)domain;

@end
