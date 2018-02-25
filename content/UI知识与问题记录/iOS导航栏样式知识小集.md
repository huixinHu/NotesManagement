如`self.navigationController.navigationBar`开头或者使用`appearance`的好像都是对所有导航栏有效的。

####设置背景颜色、文字颜色
```objective-c
[self.navigationController.navigationBar setBarTintColor:[UIColor colorWithRed:114.0/255 green:64.0/255 blue:11.0/255 alpha:1.0]];
[self.navigationController.navigationBar setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor whiteColor],NSForegroundColorAttributeName, nil]];
```

或者

```objective-c
[[UINavigationBar appearance]setBarTintColor:[UIColor redColor]];
[[UINavigationBar appearance]setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor whiteColor],NSForegroundColorAttributeName, nil]];
```

或者在导航栏使用背景图片

```objective-c
 [self.navigationController.navigationBar setBackgroundImage:[UIImage imageNamed:@"NavBg"] forBarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
//当然，使用[UINavigationBar appearance]来设置背景图也是可以的
```

####去掉导航栏下面那条黑线
```objective-c
[self.navigationController.navigationBar setBackgroundImage:[UIImage imageNamed:@"NavBg"] forBarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
[self.navigationController.navigationBar setShadowImage:[UIImage new]];
```
或者

```objective-c
[self.navigationController.navigationBar.layer setMasksToBounds:YES];
```

####设置导航栏返回按钮图片并不显示文字
选择我们要使用的图片替换返回按钮的图片，然后使返回按钮的标题不显示

```objective-c
UIImage *backButton = [UIImage imageNamed:@"back.png"];
    方法一：使用自己的图片替换原来的返回图片
self.navigationController.navigationBar.backIndicatorImage = [backButton imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
self.navigationController.navigationBar.backIndicatorTransitionMaskImage = [backButton imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    方法二：
UIImage *backButtonImage = [backButton resizableImageWithCapInsets:UIEdgeInsetsMake(0, 20, 0, 0)];//可拉伸区域
[[UIBarButtonItem appearance] setBackButtonBackgroundImage:backButtonImage
                                                      forState:UIControlStateNormal
                                                    barMetrics:UIBarMetricsDefault];
    // 将返回按钮的文字position设置不在屏幕上显示
[[UIBarButtonItem appearance] setBackButtonTitlePositionAdjustment:UIOffsetMake(NSIntegerMin, NSIntegerMin) forBarMetrics:UIBarMetricsDefault];

写一个UINavigationController的**类别**处理返回按钮的标题：
- (BOOL)navigationBar:(UINavigationBar *)navigationBar shouldPushItem:(UINavigationItem *)item{
	UIBarButtonItem *back = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
	item.backBarButtonItem = back;
	return YES;
}
```