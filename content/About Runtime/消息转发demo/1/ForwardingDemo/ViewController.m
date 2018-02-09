//
//  ViewController.m
//  ForwardingDemo
//
//  Created by commet on 2018/2/7.
//  Copyright © 2018年 commet. All rights reserved.
//

#import "ViewController.h"
#import "HXResolveMethod.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    HXResolveMethod *resolve = [[HXResolveMethod alloc] init];
    [resolve dynamicMethod:@"hello"];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
