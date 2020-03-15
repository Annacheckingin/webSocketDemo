//
//  Message.m
//  WebSocket测试
//
//  Created by LiZhengGuo on 2020/3/7.
//  Copyright © 2020 LiZhengGuo. All rights reserved.
//

#import "Message.h"

@implementation Message
-(instancetype)initWithFromUser:(NSString *)fromUser toUser:(NSString *)toUser :(NSString *)kmsg flag:(short)flag
{
    if (!fromUser&&!toUser&&!kmsg)
    {
        self.fromUser=@"";
        self.toUser=@"";
        self.msg=@"";
        self.flag=@-1;
        return self;
    }
    if (self=[super init])
    {
        self.fromUser=fromUser;
        self.toUser=toUser;
        self.flag=@0;
        self.msg=kmsg;
    }
    return self;
}
+(instancetype)disConnectMessage
{
    Message *disconnect=[[Message alloc] initWithFromUser:nil toUser:nil :nil flag:-1];
    return disconnect;
}
-(NSData *)JsonConvert
{
//    NSJSONSerialization *jsonhelper=[[NSJSONSerialization alloc]init];
    
    
    NSDictionary *dic=@{@"fromUser":self.fromUser,@"toUser":self.toUser,@"msg":self.msg,@"flag":self.flag};
    NSData *getSomething=[NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:NULL];
    return getSomething;
}
@end
