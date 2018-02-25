[参考链接](http://blog.sina.com.cn/s/blog_945590aa0102vxhb.html)

```
Singleton.h
 
@interface Singleton : NSObject
 
+(instancetype) shareInstance ;
 
@end
 
 
 
#import "Singleton.h"
 
@implementation Singleton
 
static Singleton* _instance = nil;
 
+ (instancetype)shareInstance
{
    static dispatch_once_t onceToken ;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init] ;
    }) ;
     
    return _instance ;
}
 
@end
```
可以看到，当我们调用shareInstance方法时获取到的对象是相同的，但是当我们通过alloc和init以及copy来构造对象的时候，依然会创建新的实例。
要确保对象的唯一性，所以我们就需要封锁用户通过alloc和init以及copy来构造对象这条道路。

我们知道，创建对象的步骤分为申请内存(alloc)、初始化(init)这两个步骤，我们要确保对象的唯一性，因此在第一步这个阶段我们就要拦截它。当我们调用alloc方法时，oc内部会调用allocWithZone这个方法来申请内存，我们覆写这个方法，然后在这个方法中调用shareInstance方法返回单例对象，这样就可以达到我们的目的。拷贝对象也是同样的原理，覆写copyWithZone方法，然后在这个方法中调用shareInstance方法返回单例对象。

```
#import "Singleton.h"
@interface Singleton()<NSCopying,NSMutableCopying>
@end
 
@implementation Singleton
 
static Singleton* _instance = nil;
 
+ (instancetype)shareInstance
{
    static dispatch_once_t onceToken ;
    dispatch_once(&onceToken, ^{
        _instance = [[super allocWithZone:NULL] init] ;
        //不是使用alloc方法，而是调用[[super allocWithZone:NULL] init] 
        //已经重载allocWithZone基本的对象分配方法，所以要借用父类（NSObject）的功能来帮助出处理底层内存分配的杂物
    }) ;
     
    return _instance ;
}
 
+ (id)allocWithZone:(struct _NSZone *)zone
{
    return [Singleton shareInstance] ;
}
 
- (id)copyWithZone:(NSZone *)zone
{
    return [Singleton shareInstance] ;//return _instance;
}
 
- (id)mutablecopyWithZone:(NSZone *)zone
{
    return [Singleton shareInstance] ;
}
@end
```