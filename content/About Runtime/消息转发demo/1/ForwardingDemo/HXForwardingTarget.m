//
//  HXForwardingTarget.m
//  ForwardingDemo
//
//  Created by commet on 2018/2/7.
//  Copyright © 2018年 commet. All rights reserved.
//

#import "HXForwardingTarget.h"

@implementation HXForwardingTarget

- (void)dynamicMethod:(NSString *)para {
    NSLog(@"交给备援接收者处理~");
}

@end
