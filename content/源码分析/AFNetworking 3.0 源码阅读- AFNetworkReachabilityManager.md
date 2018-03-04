`#import <SystemConfiguration/SystemConfiguration.h>`
AFNetworkReachabilityManager是一个即插即用的模块，对 SystemConfiguration模块c函数的封装，隐藏了 C 语言的实现，提供了统一且简洁的 Objective-C 语言接口。苹果的文档中也有一个类似的项目 [Reachability](https://developer.apple.com/library/ios/samplecode/reachability/) 
这里对网络状态的监控跟苹果官方的实现几乎是完全相同的。

下面先从头文件着手，之后再看类实现文件。

头文件这里就简单讲几点

1.`NS_ASSUME_NONNULL_BEGIN`和`NS_ASSUME_NONNULL_END`两个宏

在swift中，可以使用!和?来表示一个对象是optional的还是non-optional，而在Objective-C中则没有这一区分。这样就会造成一个问题：在Swift与Objective-C混编时，Swift编译器并不知道一个OC对象到底是optional还是non-optional，这种情况下编译器会隐式地将OC的对象当成是non-optional。

为了解决这个问题，苹果在Xcode 6.3引入了一个Objective-C的新特性：nullability annotations。这一新特性的核心是两个新的类型注释：`__nullable`和`__nonnull`。`__nullable`表示对象可以是NULL或nil，而`__nonnull`表示对象不应该为空。不遵循这一规则时，编译器就会给出警告。

`__nullable`和`__nonnull`仅限于使用在指针类型上。而在方法的声明中，我们还可以使用不带下划线的nullable和nonnull.

如果需要每个属性或每个方法都去指定nonnull和nullable，是一件非常繁琐的事。苹果为了减轻我们的工作量，专门提供了两个宏：`NS_ASSUME_NONNULL_BEGIN`和`NS_ASSUME_NONNULL_END`。在这两个宏之间的代码，所有简单指针对象都被假定为nonnull，因此我们只需要去指定那些nullable的指针。

2.属性的readonly和readwrite

```objective-c
.h
@property (readonly, nonatomic, assign) AFNetworkReachabilityStatus networkReachabilityStatus;
.m
@property (readwrite, nonatomic, assign) AFNetworkReachabilityStatus networkReachabilityStatus;
```

在.h和.m文件中`networkReachabilityStatus`属性分别声明为readonly、readwrite.在编程中，应该尽量把对外公布出来的属性设置为只读。如果有时候想修改封装在对象内部的数据，但又不想让这些数据被外人改动，这是可以在对象内部把readonly属性重新声明为readwrite。

3.

`FOUNDATION_EXPORT` 和`#define `都能定义常量。前者在检测字符串的值是否相等的时候更快，对于第一种你可以直接使用`stringInstance == MyFirstConstant`来比较，而define则使用的是这种`[stringInstance isEqualToString:MyFirstConstant]`。第一种效率更高，第一种直接比较的是指针地址，而第二个则是一一比较字符串的每一个字符是否相等。

`FOUNDATION_EXPORT`一般是这样使用的：

```objective-c
.h文件
FOUNDATION_EXPORT NSString * const AFNetworkingReachabilityDidChangeNotification;
FOUNDATION_EXPORT NSString * const AFNetworkingReachabilityNotificationStatusItem;
.m文件
//网络状态发生变化时接受的通知
NSString * const AFNetworkingReachabilityDidChangeNotification = @"com.alamofire.networking.reachability.change";
//网络状态发生变化时发送通知，携带的userInfo的key就是这个，value是代表AFNetworkReachabilityStatus的NSNumber
NSString * const AFNetworkingReachabilityNotificationStatusItem = @"AFNetworkingReachabilityNotificationStatusItem";
//回调
```

对这个类的.h文件就说得差不多了。接下来看类实现

AFNetworkReachabilityManager这个类是围绕SCNetworkReachability来实现的，所以先讲一点关于SCNetworkReachability的知识。

# SCNetworkReachability
1. `SCNetworkReachability` 编程接口允许应用确定系统当前网络配置的状态，还有目标主机的可达性。

 当由应用发送到网络堆栈的数据包可以离开本地设备的时候，远程主机就可以被认为可以到达。 **可达性并不保证数据包一定会被主机接收到。**

2. `SCNetworkReachability`编程接口支持同步和异步两种模式。
 
 在同步模式中，可以通过调用`SCNetworkReachabilityGetFlag`函数来获得可达性状态；
 
 在异步模式中，可以调度`SCNetworkReachability`对象到`runloop`，客户端实现一个回调函数来接收通知，当可达性状态改变就响应回调。

3. 创建连接的引用
 
 提供了几个函数创建连接的引用`SCNetworkReachabilityRef`

 ```objective-c
根据传入的域名创建网络连接引用
SCNetworkReachabilityRef __nullable SCNetworkReachabilityCreateWithName		(
	CFAllocatorRef	__nullable	allocator,//NULL或者kCFAllocatorDefault
	const char		*nodename //域名
	)
根据传入的地址创建网络连接引用
SCNetworkReachabilityRef __nullable SCNetworkReachabilityCreateWithAddress(
	CFAllocatorRef			__nullable	allocator,
	const struct sockaddr		*address//期望连接的主机地址，当为0.0.0.0时则可以查询本机的网络连接状态
	)
```

 这些函数名中含有“Create”，因此函数返回的`SCNetworkReachabilityRef`引用必须调用`CFRelease`来释放。

 关于sockaddr：
 
 ```objective-c
struct sockaddr {
	__uint8_t	sa_len;       total length
 sa_family_t	sa_family;  协议族，一般都是“AF_xxx”的形式。通常大多用的是都是AF_INET,代表TCP/IP协议族
 char		sa_data[14];    14字节协议地址
 };
 这个数据结构用做bind、connect、recvfrom、sendto等函数的参数，指明地址信息。但一般编程中并不直接针对此数据结构操作，而是使用sockaddr_in
```

4. 获取当前网络状态

 ```objective-c
Boolean SCNetworkReachabilityGetFlags (   //当前网络配置下，目标是否可达，目标target就是参数1
   SCNetworkReachabilityRef target,            //之前建立的网络连接的引用
   SCNetworkReachabilityFlags *flags           //保存获得网络状态
);
```


# 初始化 AFNetworkReachabilityManager

1. ```+manager```

 ```objective-c
+ (instancetype)manager {
#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 90000) || (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED >= 101100)
		struct sockaddr_in6 address;
		bzero(&address, sizeof(address));
		address.sin6_len = sizeof(address);
		address.sin6_family = AF_INET6;
#else
		struct sockaddr_in address;
		bzero(&address, sizeof(address));//初始化
		address.sin_len = sizeof(address);
		address.sin_family = AF_INET;
#endif
		return [self managerForAddress:&address];
}
```

 使用这个类方法创建一个默认socket地址的`AFNetworkReachabilityManager`对象。
ipv6是iOS9和OSX10.11后推出的，因此这里要进行系统版本的判断。

 相关代码讲解：

 ```objective-c
 struct sockaddr_in {
	 __uint8_t    sin_len;
	 sa_family_t    sin_family; //协议族，在socket编程中只能是AF_INET
	 in_port_t    sin_port;     //端口号（使用网络字节顺序）
	 struct in_addr  sin_addr;  //按照网络字节顺序存储IP地址，使用in_addr这个数据结构
	 char        sin_zero[8];   //让sockaddr与sockaddr_in两个数据结构保持大小相同而保留的空字节。
	//sockaddr_in和sockaddr是并列的结构，指向sockaddr_in的结构体的指针也可以指向sockaddr的结构体，并代替它。
	//也就是说，你可以使用sockaddr_in建立你所需要的信息,然后用进行类型转换就可以了
 };
 
 struct in_addr {
	in_addr_t s_addr;
 };
 结构体in_addr 用来表示一个32位的IPv4地址。in_addr_t 是一个32位的unsigned long，其中每8位代表一个IP地址位中的一个数值。
 　　例如192.168.3.144记为0xc0a80390
```

2. ```+managerForAddress:和+managerForDomain:```

 ```objective-c
+ (instancetype)managerForAddress:(const void *)address {
    //根据传入的地址创建网络连接引用。
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)address);//返回的网络连接引用必须在用完后释放。
    AFNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];
    CFRelease(reachability);//手动管理内存
    return manager;
}

 + (instancetype)managerForDomain:(NSString *)domain {
    //根据传入的域名创建网络连接引用
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [domain UTF8String]);
    AFNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];
    CFRelease(reachability);//手动管理内存
    return manager;
}
```
 
 先使用 `SCNetworkReachabilityCreateWithAddress `或者 `SCNetworkReachabilityCreateWithName` 函数生成一个 `SCNetworkReachabilityRef `的引用。这里没什么要说了，前面已经简单介绍过。
然后调用`initWithReachability: `方法如下：

3. ```-initWithReachability :```

 ```objective-c
- (instancetype)initWithReachability:(SCNetworkReachabilityRef)reachability {
    self = [super init];
    if (!self) {
        return nil;
    }
    _networkReachability = CFRetain(reachability);//为什么要retain？谁创建谁释放，这个参数reachability不是在这个方法中创建的。在+managerForDomain:和+managerForAddress:方法实现中，最后释放掉了网络连接引用reachability，因此要在本方法中先把它retain一次。
    self.networkReachabilityStatus = AFNetworkReachabilityStatusUnknown;
    return self;
}
```

 让_networkReachability持有 `SCNetworkReachabilityRef `的引用，并设置一个默认的网络状态。

 为什么要retain这个`SCNetworkReachabilityRef`引用？个人理解：谁创建谁释放，这个参数reachability在`+managerForDomain:`和`+managerForAddress:`方法中创建也应由它们释放。为了防止`-initWithReachability:`方法还没执行完，这个引用就已经在`+managerForDomain:`或`+managerForAddress:`释放掉了，因此要在本方法中先把它retain一次。

 在```dealloc```中有对应的release。

4. ```-init```
这个方法被直接禁用了。关于`NS_UNAVAILABLE` 可以[看这篇文章](http://www.tuicool.com/articles/YzmQVbM)

# 监控网络状态
```objective-c
- (void)startMonitoring {
    [self stopMonitoring];//先关闭监听

    if (!self.networkReachability) {//如果网络不可达，就返回
        return;
    }
    //避免循环引用要用weakself，避免在block执行过程中，突然出现self被释放的情况，就用strongself
    __weak __typeof(self)weakSelf = self;
    AFNetworkReachabilityStatusBlock callback = ^(AFNetworkReachabilityStatus status) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;

        strongSelf.networkReachabilityStatus = status;
        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }

    };
    SCNetworkReachabilityContext context = {0, (__bridge void *)callback, AFNetworkReachabilityRetainCallback, AFNetworkReachabilityReleaseCallback, NULL};
    //设置回调。SCNetworkReachabilitySetCallback指定一个target(第一个参数)，当设备对于这个target链接状态发生改变时，就进行回调（第二个参数）。它第二个参数：SCNetworkReachabilityCallBack类型的值，是当网络可达性更改时调用的函数，如果为NULL，则目标的当前客户端将被删除。SCNetworkReachabilityCallBack中的info参数就是SCNetworkReachabilityContext中对应的那个info
    SCNetworkReachabilitySetCallback(self.networkReachability, AFNetworkReachabilityCallback, &context);
    //加入runloop
    SCNetworkReachabilityScheduleWithRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    //异步线程发送一次当前网络状态（通知）
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        SCNetworkReachabilityFlags flags;
        //SCNetworkReachabilityGetFlags获得可达性状态
        if (SCNetworkReachabilityGetFlags(self.networkReachability, &flags)) {
            AFPostReachabilityStatusChange(flags, callback);
        }
    });
    /*SCNetworkReachability 编程接口支持同步和异步两种模式。
    在同步模式中，可以通过调用SCNetworkReachabilityGetFlag函数来获得可达性状态；
    在异步模式中，可以调度SCNetworkReachability对象到客户端对象线程的运行循环上，客户端实现一个回调函数来接收通知，当远程主机改变可达性状态，回调则可响应。
    */
}
```

这算是这个类的核心方法。设置网络监控分为以下几个步骤：

1. 创建上下文。关于 `SCNetworkReachabilityContext`结构体

 ```objective-c
typedef struct {
     CFIndex        version;   作为参数传递到SCDynamicStore创建函数的结构类型的版本号，这个结构体对应的是version 0。
     void *        __nullable info; 表示网络状态处理的回调函数。指向用户指定的数据块的C指针，void* 相当于oc的id
     const void    * __nonnull (* __nullable retain)(const void *info); retain info
     void        (* __nullable release)(const void *info); 对应上一个元素 release
     CFStringRef    __nonnull (* __nullable copyDescription)(const void *info); 提供信息字段的描述
     } SCNetworkReachabilityContext;
```

 关于参数的说明：
 
 - ```CFIndex version```：创建一个 `SCNetworkReachabilityContext` 结构体时，需要调用 `SCDynamicStore `的创建函数，`SCNetworkReachabilityContext` 对应的 version 是 0

 - ```void *__nullable info```：表示网络状态处理的回调函数。指向用户指定的数据块的C指针，```void*``` 相当于oc的id。
 
 要携带的这个info就是下面这个block，是一个在每次网络状态改变时的回调。而且block和`void*`的转换不能直接转，要使用`__bridge`。

 ```objective-c
__weak __typeof(self)weakSelf = self;
//1.网络状态变化时回调的是这个block
    AFNetworkReachabilityStatusBlock callback = ^(AFNetworkReachabilityStatus status) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;
        strongSelf.networkReachabilityStatus = status;
//2.其中回调block中会执行_networkReachabilityStatusBlock，这个block才是核心，由-setReachabilityStatusChangeBlock:方法对这个block进行设置
        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }
    };
```

 避免循环引用要用weakself，避免在block执行过程中，突然出现self被释放的情况，就用strong self。[传送门](http://www.jianshu.com/p/36342264d6df)

 - 第三第四个参数：是一个函数，分别对info retain和release

 ```objective-c
 //调用了 Block_copy（用于 retain 一个 block 函数，即在堆空间新建或直接引用一个 block 拷贝）
static const void * AFNetworkReachabilityRetainCallback(const void *info) {
    return Block_copy(info);
}
//调用了 Block_release（用于 release 一个 block 函数，即将 block 从堆空间移除或移除相应引用）
static void AFNetworkReachabilityReleaseCallback(const void *info) {
		if (info) {
		    Block_release(info);
		}
}
```
 
 - 第五个参数：提供对info的一些说明描述

2. 设置回调

 ```objective-c
SCNetworkReachabilitySetCallback(self.networkReachability, AFNetworkReachabilityCallback, &context);
```

 函数的原型是这样的：

 ```objective-c
Boolean SCNetworkReachabilitySetCallback(
	SCNetworkReachabilityRef	target,    //网络连接引用
	SCNetworkReachabilityCallBack	__nullable	callout,//回调
	SCNetworkReachabilityContext	* __nullable	context//上下文
)
```

 它的第二个参数，`SCNetworkReachabilityCallBack`是这样被定义的

 ```objective-c
typedef void (*SCNetworkReachabilityCallBack)(
	SCNetworkReachabilityRef	target,  //网络连接引用
	SCNetworkReachabilityFlags  flags,   //状态flag
	void	*	__nullable	info      //回调，这个info和SCNetworkReachabilityContext中的info是同一个
	);
```

 `SCNetworkReachabilitySetCallback`给当前客户端指定一个目标target(第一个参数，之前创建的网络连接引用)，当设备对于这个target连接状态发生改变时，就进行回调（第二个参数）。它第二个参数：`SCNetworkReachabilityCallBack`类型的值，是当网络可达性更改时调用的函数，如果为NULL，则目标的当前客户端将被删除。**SCNetworkReachabilityCallBack中的info参数就是SCNetworkReachabilityContext中对应的那个info。**

 在AF中，在每次网络状态改变，就会调用 `AFNetworkReachabilityCallback` 函数:

 ```objective-c
static void AFNetworkReachabilityCallback(SCNetworkReachabilityRef __unused target, SCNetworkReachabilityFlags flags, void *info) {
    AFPostReachabilityStatusChange(flags, (__bridge AFNetworkReachabilityStatusBlock)info);//这里void*和id的转换，在ARC下要加__bridge修饰
}
```

 这里会从 info 中取出之前存在 context 中的 `AFNetworkReachabilityStatusBlock` 回调block，并把这个block传递给 `AFPostReachabilityStatusChange` 函数：

 ```objective-c
//根据flag来获得对应的网络状态，在主线程中进行对应的回调（block），发送通知。
//根据同一个status来处理block 和通知，封装到一个函数中保持两者统一
static void AFPostReachabilityStatusChange(SCNetworkReachabilityFlags flags, AFNetworkReachabilityStatusBlock block) {
    AFNetworkReachabilityStatus status = AFNetworkReachabilityStatusForFlags(flags);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (block) {
            block(status);
        }
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        NSDictionary *userInfo = @{ AFNetworkingReachabilityNotificationStatusItem: @(status) };
        [notificationCenter postNotificationName:AFNetworkingReachabilityDidChangeNotification object:nil userInfo:userInfo];
    });
}
```

 - 调用 `AFNetworkReachabilityStatusForFlags` 获取当前的网络可达性状态
 - 在主线程中异步执行上面传入的 callback block（设置 self 的网络状态，调用 `networkReachabilityStatusBlock`）

 ```objective-c
__weak __typeof(self)weakSelf = self;
  AFNetworkReachabilityStatusBlock callback = ^(AFNetworkReachabilityStatus status) {
      __strong __typeof(weakSelf)strongSelf = weakSelf;
      strongSelf.networkReachabilityStatus = status;
      if (strongSelf.networkReachabilityStatusBlock) {
          strongSelf.networkReachabilityStatusBlock(status);
      }
  };
```
 
 - 发送 `AFNetworkingReachabilityDidChangeNotification` 通知.

3. 加入runloop池
 
 在 Main Runloop 中对应的模式开始监控网络状态
 
 ```objective-c   
SCNetworkReachabilityScheduleWithRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
```

4. 获取当前的网络状态，调用 callback

```objective-c
    //子线程中获取网络状态，主线程执行回调并发送通知
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        SCNetworkReachabilityFlags flags;
        //SCNetworkReachabilityGetFlags获得可达性状态
        if (SCNetworkReachabilityGetFlags(self.networkReachability, &flags)) {
            AFPostReachabilityStatusChange(flags, callback);
        }
    });
```

# 停止网络监控
使用 `SCNetworkReachabilityUnscheduleFromRunLoop` 方法取消之前在 Main Runloop 中的监听

```objective-c
- (void)stopMonitoring {
    if (!self.networkReachability) {
        return;
    }
    SCNetworkReachabilityUnscheduleFromRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
}
```

# 其他
## 1.设置networkReachabilityStatusBlock
每次网络状态改变时, 实际上调用的是这个block

```objective-c
- (void)setReachabilityStatusChangeBlock:(void (^)(AFNetworkReachabilityStatus status))block {
    self.networkReachabilityStatusBlock = block;
}
```

在每次网络状态改变时, 调用的是定义在`-startMonitoring`中的`AFNetworkReachabilityStatusBlock callback`这个block，而这个block会执行`_networkReachabilityStatusBlock`。这个block需要人为设置。

## 2.根据SCNetworkReachabilityFlags转换成开发中使用的AFNetworkReachabilityStatus网络状态

```objective-c
static AFNetworkReachabilityStatus AFNetworkReachabilityStatusForFlags(SCNetworkReachabilityFlags flags) {
//&按位与运算 和&&不一样
    // 该网络地址可达
    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    // 该网络地址虽然可达，但是需要先建立一个 connection
    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
    // 该网络虽然也需要先建立一个 connection，但是它是可以自动去 connect 的
    BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
    // 不需要用户交互，就可以 connect 上（用户交互一般指的是提供网络的账户和密码）
    BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
    // 如果 isReachable==YES，那么就需要判断是不是得先建立一个 connection，如果需要，那就认为不可达，或者虽然需要先建立一个 connection，但是不需要用户交互，那么认为也是可达的
    BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));
    
    //  AFNetworkReachabilityStatus 就四种状态 Unknown、NotReachable、ReachableViaWWAN、ReachableViaWiFi，这四种状态字面意思很好理解，这里就不赘述了
    AFNetworkReachabilityStatus status = AFNetworkReachabilityStatusUnknown;
    if (isNetworkReachable == NO) {
        status = AFNetworkReachabilityStatusNotReachable;
    }
#if	TARGET_OS_IPHONE
    else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
        status = AFNetworkReachabilityStatusReachableViaWWAN;
    }
#endif
    else {
        status = AFNetworkReachabilityStatusReachableViaWiFi;
    }

    return status;
}
```

因为 flags 是一个` SCNetworkReachabilityFlags`，它的不同位代表了不同的网络可达性状态，通过 flags 的**位操作**，获取当前的状态信息 `AFNetworkReachabilityStatus`。

## 3.本地化

```objective-c
NSString * AFStringFromNetworkReachabilityStatus(AFNetworkReachabilityStatus status) {
    switch (status) {
        case AFNetworkReachabilityStatusNotReachable:
            return NSLocalizedStringFromTable(@"Not Reachable", @"AFNetworking", nil);
        case AFNetworkReachabilityStatusReachableViaWWAN:
            return NSLocalizedStringFromTable(@"Reachable via WWAN", @"AFNetworking", nil);
        case AFNetworkReachabilityStatusReachableViaWiFi:
            return NSLocalizedStringFromTable(@"Reachable via WiFi", @"AFNetworking", nil);
        case AFNetworkReachabilityStatusUnknown:
        default:
            return NSLocalizedStringFromTable(@"Unknown", @"AFNetworking", nil);
    }
}
```

这是一个函数的实现 根据`AFNetworkReachabilityStatus`获取本地化字符串。`NSLocalizedStringFromTable`用于本地化。

```objective-c
- (NSString *)localizedNetworkReachabilityStatusString {
    return AFStringFromNetworkReachabilityStatus(self.networkReachabilityStatus);
}
```

对上面的函数进行oc方法封装，返回一个网络状态的本地语言字符串。通过这个字符串可以告诉用户当前网络发生什么。或者根据返回的状态自定义提示文字。

## 4.注册键值依赖
```objective-c
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    if ([key isEqualToString:@"reachable"] || [key isEqualToString:@"reachableViaWWAN"] || [key isEqualToString:@"reachableViaWiFi"]) {
        return [NSSet setWithObject:@"networkReachabilityStatus"];
    }
    return [super keyPathsForValuesAffectingValueForKey:key];
}
```

和KVO有关的键值依赖。监听reachable、reachableViaWWAN、reachableViaWiFi属性，当networkReachabilityStatus属性值发生变化就会触发那三个属性的键值监听方法。

## 5.AF中对私有“方法”的写法
AF中把私有方法写成c函数的形式```static void funcName()```，比如：

```objective-c
NSString * AFStringFromNetworkReachabilityStatus(AFNetworkReachabilityStatus status) {...}
static AFNetworkReachabilityStatus AFNetworkReachabilityStatusForFlags(SCNetworkReachabilityFlags flags) {...}
static void AFPostReachabilityStatusChange(SCNetworkReachabilityFlags flags, AFNetworkReachabilityStatusBlock block){...}
```
> 这些私有函数放到类文件头部，你即使不看这些代码，对于整个业务的理解也不会受到影响。所以，这种写法值得推荐。可以适当的使用内联函数，提高效率

# 使用
1. 初始化 AFNetworkReachabilityManage
2. 调用 startMonitoring方法开始对网络状态进行监
3. 设置 networkReachabilityStatusBlock在每次网络状态改变时, 调用这个 block

详细源码注释[请戳github](https://github.com/huixinHu/AFNetworking-)

参考文章

[Block内存管理实例分析](http://www.cocoachina.com/ios/20161025/17198.html)

[IOS SCNetworkReachability和Reachability监测网络连接状态](http://blog.csdn.net/s3590024/article/details/51279863)

[sockaddr和sockaddr_in的区别](http://blog.csdn.net/joeblackzqq/article/details/8258693)

[NS_UNAVAILABLE 与 NS_DESIGNATED_INITIALIZER](http://www.tuicool.com/articles/YzmQVbM)

[AFNetworking 3.0 源码解读（一）之 AFNetworkReachabilityManager](http://www.cnblogs.com/machao/p/5681645.html)