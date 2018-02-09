//
//  HXResolveMethod.m
//  ForwardDemo
//
//  Created by commet on 2018/2/7.
//  Copyright © 2018年 commet. All rights reserved.
//

#import "HXResolveMethod.h"
#import "HXForwardingTarget.h"
//#import <objc/runtime.h>

@implementation HXResolveMethod

- (id)forwardingTargetForSelector:(SEL)aSelector {
    NSString *selectorString = NSStringFromSelector(aSelector);
    if ([selectorString isEqualToString:@"dynamicMethod:"]) {
        HXForwardingTarget *newTarget = [[HXForwardingTarget alloc] init];
        return newTarget;
    }
    return [super forwardingTargetForSelector:aSelector];
}

@end

