一般来说，如果需要修改UIAlertController的标题（title）、内容（message）的字体和颜色，可以[利用KVC来实现](http://www.jianshu.com/p/51949eec2e9c)。

但如果需要修改UIAlertAction中的文字字体，利用KVC，获取出的属性只有能修改颜色的_titleTextColor（在iOS8.3之后出现）。

通过[这篇文章](http://www.jianshu.com/p/f6752f7f8709)知道，我们可以给UILabel添加分类，修改所有出现在UIAlertController中字体的样式（这种方法不好的地方就是，所有的字体样式都改变了）。

具体代码：创建一个分类

```objective-c
#import <UIKit/UIKit.h>
@interface UILabel (AlertActionFont)
@property (nonatomic,copy) UIFont *appearanceFont UI_APPEARANCE_SELECTOR;
@end

#import "UILabel+AlertActionFont.h"

@implementation UILabel (AlertActionFont)
- (void)setAppearanceFont:(UIFont *)appearanceFont
{
    if(appearanceFont)
    {
        [self setFont:appearanceFont];
    }
}

- (UIFont *)appearanceFont
{
    return self.font;
}
@end
```

修改样式：

```objective-c
UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:preferredStyle];
UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:cancelHandler];
[cancelAction setValue:[Utils colorWithHexString:@"#00A7FA"] forKey:@"titleTextColor"];//iOS8.3
[alert addAction: cancelAction];

UIAlertAction *otherAction = [UIAlertAction actionWithTitle:otherTitles[i] style:UIAlertActionStyleDefault handler:otherBlocks[i]];
[otherAction setValue:[Utils colorWithHexString:@"#00A7FA"] forKey:@"titleTextColor"];//iOS8.3
[alert addAction: otherAction];

UILabel *appearanceLabel;
#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0
if ([[[UIDevice currentDevice] systemVersion] floatValue] < 9.0) {
    appearanceLabel = [UILabel appearanceWhenContainedIn:UIAlertController.class, nil];
} else
#endif
{
    appearanceLabel = [UILabel appearanceWhenContainedInInstancesOfClasses:@[UIAlertController.class]];
}

UIFont *font = [UIFont systemFontOfSize:13];
[appearanceLabel setAppearanceFont:font];
```

ps:如何通过kvc获取key值

```objective-c
//kvc 获取所有key值
- (NSArray *)getAllIvar:(id)object
{
    NSMutableArray *array = [NSMutableArray array];
    
    unsigned int count;
    Ivar *ivars = class_copyIvarList([object class], &count);
    for (int i = 0; i < count; i++) {
        Ivar ivar = ivars[i];
        const char *keyChar = ivar_getName(ivar);
        NSString *keyStr = [NSString stringWithCString:keyChar encoding:NSUTF8StringEncoding];
        @try {
            id valueStr = [object valueForKey:keyStr];
            NSDictionary *dic = nil;
            if (valueStr) {
                dic = @{keyStr : valueStr};
            } else {
                dic = @{keyStr : @"值为nil"};
            }
            [array addObject:dic];
        }
        @catch (NSException *exception) {}
    }
    return [array copy];
}

//获得所有属性
- (NSArray *)getAllProperty:(id)object
{
    NSMutableArray *array = [NSMutableArray array];
    
    unsigned int count;
    objc_property_t *propertys = class_copyPropertyList([object class], &count);
    for (int i = 0; i < count; i++) {
        objc_property_t property = propertys[i];
        const char *nameChar = property_getName(property);
        NSString *nameStr = [NSString stringWithCString:nameChar encoding:NSUTF8StringEncoding];
        [array addObject:nameStr];
    }
    return [array copy];
}

使用：
UILabel *label = [[UILabel alloc] init];
NSLog(@"********所有变量/值:\n%@", [self getAllIvar:label]);
```