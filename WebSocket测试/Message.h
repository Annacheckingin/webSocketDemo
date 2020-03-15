//
//  Message.h
//  WebSocket测试
//
//  Created by LiZhengGuo on 2020/3/7.
//  Copyright © 2020 LiZhengGuo. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Message : NSObject
@property(nonatomic,copy)NSString *fromUser;
@property(nonatomic,copy)NSString *toUser;
@property(nonatomic,copy)NSString *msg;
@property(nonatomic,strong)NSNumber *flag;
//若前三个参数都为nil，那么最后一个参数必定为-1，为一个断开链接的信息；
-(instancetype)initWithFromUser:( NSString * _Nullable )fromUser toUser:( NSString *_Nullable)kmsg:( NSString * _Nullable)msg flag:(short) flag;
+(instancetype)disConnectMessage;
-(NSData *)JsonConvert;
@end

NS_ASSUME_NONNULL_END
