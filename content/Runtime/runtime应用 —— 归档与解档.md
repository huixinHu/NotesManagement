# 归档与解档

用runtime实现的思路就比较简单，我们循环依次找到每个属性的名称（当然也可以换成实例变量），然后利用KVC读取和赋值就可以完成encodeWithCoder和initWithCoder了。

```objective-c
#import <Foundation/Foundation.h>

@interface Stundent : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *age;
@end




#import "Stundent.h"
#import <objc/runtime.h>

@interface Stundent()<NSCoding>

@end

@implementation Stundent

- (void)encodeWithCoder:(NSCoder *)aCoder {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList([self class], &count);
    for (int i = 0; i < count; ++i) {
        const char *name = property_getName(properties[i]);
        NSString *p = [NSString stringWithUTF8String:name];
        id value = [self valueForKey:p];
        [aCoder encodeObject:value forKey:p];
    }
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        unsigned int count = 0;
        objc_property_t *properties = class_copyPropertyList([self class], &count);
        for (int i= 0; i < count; i++) {
            const char *name = property_getName(properties[i]);
            NSString *p = [NSString stringWithUTF8String:name];
            id value = [aDecoder decodeObjectForKey:p];
            [self setValue:value forKey:p];
        }
    }
    return self;
}
@end
```

归档与解档

```objective-c
Stundent *s = [[Stundent alloc] init];
s.name = @"hhx";
s.age = @"22";
NSString * path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
NSString * fileName = [path stringByAppendingPathComponent:@"contact"];
NSLog(@"%@", fileName);
//    归档
[NSKeyedArchiver archiveRootObject:s toFile:fileName];
//    反归档
Stundent *person = [NSKeyedUnarchiver unarchiveObjectWithFile:fileName];
    
NSLog(@"%@", person.name);
NSLog(@"%@", person.age);
```