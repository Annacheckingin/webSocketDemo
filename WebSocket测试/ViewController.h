//
//  ViewController.h
//  WebSocket测试
//
//  Created by LiZhengGuo on 2020/3/7.
//  Copyright © 2020 LiZhengGuo. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController
@property(nonatomic,weak)IBOutlet UITextField *inputInfor;

@property(nonatomic,weak)IBOutlet UILabel *receivedInfor;
@property(nonatomic,weak)IBOutlet UIButton *connect;
@property(nonatomic,weak)IBOutlet UIButton *sendMessage;
@property(nonatomic,weak)IBOutlet UIButton *disconnected;
@property(nonatomic,weak)IBOutlet UITextField *theurl;
@property (weak, nonatomic) IBOutlet UITextField *toUser;
@property(nonatomic,weak)IBOutlet UITextField *userId;
@end

