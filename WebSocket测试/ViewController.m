//
//  ViewController.m
//  WebSocket测试
//
//  Created by LiZhengGuo on 2020/3/7.
//  Copyright © 2020 LiZhengGuo. All rights reserved.
//

#import "ViewController.h"
#import "JFRWebSocket.h"
#import "Message.h"
typedef NS_ENUM(NSInteger,LzgisConnect)
{
    LzgisConnectNot,
    LzgisConnectYes
};
@interface ViewController ()<JFRWebSocketDelegate,UITextFieldDelegate>
@property(nonatomic,strong)JFRWebSocket *socket;
@property(nonatomic,assign)LzgisConnect kisconnect;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.connect addTarget:self action:@selector(connectAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.sendMessage addTarget:self action:@selector(sendMessageAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.disconnected addTarget:self action:@selector(disConnectAction:) forControlEvents:UIControlEventTouchUpInside];
    self.receivedInfor.font=[UIFont systemFontOfSize:11];
    self.userId.delegate=self;
    self.theurl.delegate=self;
    self.theurl.text=@"http://192.168.101.101:8080/websocket/";
    self.receivedInfor.numberOfLines=2;
    self.kisconnect=LzgisConnectNot;
    // Do any additional setup after loading the view.
}
-(BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [[UIApplication sharedApplication].keyWindow endEditing:YES];
    return YES;
}
-(void)connectAction:(UIButton *)sender
{
    if (self.theurl.text!=nil&&![self.theurl.text isEqualToString:@""]&&self.kisconnect==LzgisConnectNot)
    {
        NSString *theurlStr=self.theurl.text;
        theurlStr=[theurlStr stringByAppendingString:self.userId.text];
        self.socket=[[JFRWebSocket alloc]initWithURL:[NSURL URLWithString:theurlStr] protocols:@[@"chat"]];
        self.socket.delegate=self;
        [self.socket  connect];
    }
   
}
-(void)sendMessageAction:(UIButton *)sender
{
    if (self.socket&&self.userId.text&&![self.userId.text isEqualToString:@""]&&self.toUser.text&&![self.toUser.text isEqualToString:@""]&&self.kisconnect==LzgisConnectYes)
    {
        
        Message *aMessage=[[Message alloc]initWithFromUser:self.userId.text toUser:self.toUser.text :self.inputInfor.text flag:0];
        NSString *atr=[[NSString alloc]initWithData:[aMessage JsonConvert] encoding:NSUTF8StringEncoding];
        [self.socket writeString:atr];
    }
}
-(void)disConnectAction:(UIButton *)sender
{
    NSLog(@"disConnection!");
       if (self.socket)
       {
           Message *aDisconnectMessage=[Message disConnectMessage];
           NSData *fruit=[aDisconnectMessage JsonConvert];
           NSLog(@"data is Ready!");
           NSString *str=[[NSString alloc]initWithData:fruit encoding:NSUTF8StringEncoding];
           NSLog(@"%@",str);
           [self.socket writeString:str];
          
//           [self.socket disconnect];
       }
}
//
- (IBAction)clearMessage:(id)sender
{
    self.receivedInfor.text=@"";
}

-(void)websocketDidConnect:(nonnull JFRWebSocket*)socket
{
    NSLog(@"链接成功");
    self.kisconnect=LzgisConnectYes;
}

/**
 The websocket was disconnected from its host.
 @param socket is the current socket object.
 @param error  is return an error occured to trigger the disconnect.
 */
-(void)websocketDidDisconnect:(nonnull JFRWebSocket*)socket error:(nullable NSError*)error
{
    NSLog(@"断开成功");
    self.kisconnect=LzgisConnectNot;
    self.receivedInfor.text=@"已断开";
    
}

/**
 The websocket got a text based message.
 @param socket is the current socket object.
 @param string is the text based data that has been returned.
 */
-(void)websocket:(nonnull JFRWebSocket*)socket didReceiveMessage:(nonnull NSString*)string
{
//    NSRange msgRange=[string rangeOfString:@"msg :"];
//    NSInteger beginIndex=msgRange.location;
////    NSRange flagRange=[string rangeOfString:@"flag"];
////    NSInteger endIndex=flagRange.location;
////    if (beginIndex<endIndex)
////    {
//    NSString *needstr=[string substringFromIndex:beginIndex];
//    NSRange flagRange=[needstr rangeOfString:@"flag :"];
//    NSString *realstr=[needstr substringToIndex:flagRange.location];
//    NSString *atr=[realstr substringFromIndex:4];
//    self.receivedInfor.text=atr;
//    }
    NSData *data=[string dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dic=[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
    self.receivedInfor.text=dic[@"msg"];
}

/**
 The websocket got a binary based message.
 @param socket is the current socket object.
 @param data   is the binary based data that has been returned.
 */
-(void)websocket:(nonnull JFRWebSocket*)socket didReceiveData:(nullable NSData*)data
{
    
}
@end
