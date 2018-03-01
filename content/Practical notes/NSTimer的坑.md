之前要做一个发送短信验证码的倒计时功能，打算用NSTimer来实现，做的过程中发现坑还是有不少的。

- 基本使用
- NSTimer的强引用问题
- 不准时
- iOS10中的改动

其中会涉及到一些runloop的知识，这里不会另外去讲，在[我之前写的一篇runloop的文章](http://www.jianshu.com/p/911549ae4bf8)中已经提及过，有需要的可以看看。

## 1、基本使用
创建timer的方法：

```objectivec
//把创建timer并把它添加到当前线程runloop中，模式是默认的default mode
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(nullable id)userInfo repeats:(BOOL)yesOrNo;
//和上面的方法作用差不多，但不会把timer自动添加到runloop中，需要人手动加
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(nullable id)userInfo repeats:(BOOL)yesOrNo;
```

参数说明：

- ti：定时器触发间隔时间，单位为秒，可以是小数。
- aTarget：发送消息的目标，timer会强引用aTarget，直到调用invalidate方法。
- aSelector：将要发送给aTarget的消息,可以不带参，如果带有参数则应把timer作为参数传递过去`：- (void)timerFireMethod:(NSTimer *)timer`
- userInfo：传递的用户信息，timer对此进行强引用。
- yesOrNo：是否重复。如果是YES则重复触发，直到调用invalidate方法；如果是NO，则只触发一次就自动调用invalidate方法。

比如：

```objectivec
- (void)viewDidLoad {
    [super viewDidLoad];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timerMethod) userInfo:nil repeats:YES];
}

- (void)timerMethod{
    NSLog(@"timer2 run");
}
```

timer要添加到runloop才有效，因此运行要满足几个条件：1.当前线程的runloop存在，2.timer添加到runloop，3.runloop mode要适配。

比如在子线程中使用NSTimer：

```objectivec
- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *btn = [[UIButton alloc]initWithFrame:CGRectMake(0, 80, 50, 50)];
    btn.backgroundColor = [UIColor redColor];
    [self.view addSubview:btn];
    [btn addTarget:self action:@selector(clicked) forControlEvents:UIControlEventTouchUpInside];
    
    [NSThread detachNewThreadSelector:@selector(threadMethod) toTarget:self withObject:nil];
}

- (void)threadMethod{
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timerMethod) userInfo:nil repeats:YES];
    CFRunLoopRun();
}

- (void)clicked{
    [self.timer invalidate];
    [self.navigationController popViewControllerAnimated:YES];
}
```

如果要runloop修改模式，调用一次`addTimer:forMode:`方法就可以了:

```objectivec
[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
```
其余的NSTimer初始化方法大同小异就不展开了。

## 2、NSTimer 不准确
在[这篇文章](http://www.jianshu.com/p/7045813769fd)中有这么一个观点：
> 很多讲述定时器的技术文中都有这么一个观点，如果一个定时器错过了本次可以触发的时间点，那么定时器将跳过这个时间点，等待下一个时间点的到来。但这个观点跟定时器在RunLoop中的工作原理并不符。定时消息从内核发出，消息在消息中心等待被处理，RunLoop每次Loop都会去消息中心查找相应的端口消息，若找到相应的端口消息就会进行处理，所以，即使当前RunLoop正在执行一个耗时很长的任务，当任务执行完进入下一次Loop时，那些未被处理的消息仍然会被处理。经过大量测试表明，定时消息并不会因延迟而掉失。

验证代码：

```objectivec
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    // 创建observer
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(CFAllocatorGetDefault(), kCFRunLoopAllActivities, YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        NSLog(@"----监听到RunLoop状态发生改变---%zd", activity);
    });
    // 添加观察者：监听RunLoop的状态
    CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer, kCFRunLoopDefaultMode);

    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timerMethod) userInfo:nil repeats:YES];
    self.timer.fireDate = [NSDate dateWithTimeIntervalSinceNow:3];
    [self performSelector:@selector(busyOperation) withObject:nil afterDelay:0.5];
    
    // 释放Observer
    CFRelease(observer);
}

- (void)timerMethod{
    NSLog(@"timer2 run");
}

- (void)busyOperation{
    NSLog(@"线程繁忙开始");
    long count = 0xffffffff;
    CGFloat calculateValue = 0;
    for (long i = 0; i < count; i++) {
        calculateValue = i/2;
    }
    NSLog(@"线程繁忙结束");
}
```

![32：runloop即将进入休眠；64：runloop唤醒](http://upload-images.jianshu.io/upload_images/1727123-a7e6a186bccd667b.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

对照runloop状态代码，32表示runloop即将休眠，64表示runloop唤醒，128表示runloop退出

```objectivec
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry = (1UL << 0),
    kCFRunLoopBeforeTimers = (1UL << 1),
    kCFRunLoopBeforeSources = (1UL << 2),
    kCFRunLoopBeforeWaiting = (1UL << 5),
    kCFRunLoopAfterWaiting = (1UL << 6),
    kCFRunLoopExit = (1UL << 7),
    kCFRunLoopAllActivities = 0x0FFFFFFFU
};
```

定时消息不会因为延时而消失。如果这段代码有写得不合理的地方请告诉我。但不管怎样有一点是可以肯定的，NSTimer定时器不是十分精确。

## 3、NSTimer强引用引起的内存问题。

```objectivec
@property (nonatomic ,strong)NSTimer *timer;
- (void)viewDidLoad {
    [super viewDidLoad];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timerMethod) userInfo:nil repeats:YES];
}

- (void)timerMethod{
    NSLog(@"timer2 run");
}
```

运行上面这段代码，如果从这一级VC pop回上一级VC，timer still running!!

![强引用示意图](http://upload-images.jianshu.io/upload_images/1727123-c5d3227f81a7691c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

runloop强引用timer，timer强引用target对象。要解除这两种强引用就必须要调用`invalidate`方法。

**关于`invalidate`方法**

`invalidate`方法有2个功能：

1. 将timer从runloop中移除
2. timer本身也会释放它持有资源，比如target、userinfo、block。

之后的timer也就永远无效了，要再次使用timer就要重新创建。

timer只有这一个方法可以完成此操作，所以我们取消一个timer必须要调用此方法。（在添加到runloop前，可以使用它的getter方法isValid来判断，一个是防止为nil，另一个是防止为无效）

NSTimer 在哪个线程创建就要在哪个线程停止，否则会导致资源不能被正确的释放。因此`invalidate`方法必须在timer添加到的runloop所在的线程中调用。

ps:在网上看很多技术文，`[timer invalidate]`和`timer = nil;`放在一起使用，我觉得仅仅调用`invalidate`方法就足够解决问题了。

在vc 的`dealloc`方法中调用`invalidate`？

```objectivec
- (void)dealloc{
    NSLog(@"销毁了");
    [self.timer invalidate];
}
```

结果还是一样的！无法走到`dealloc`方法。
因为timer对view controller的强引用，导致vc无法释放，也就无法走到dealloc方法了。（即使timer属性是weak，结果是走不到dealloc，只不过vc(self)和timer之间不再有保留环）

那么加个按钮方法：

```objectivec
- (IBAction)invalidateButtonPressed:(id)sender {
    [self.timer invalidate];
}
```

恩！先点击按钮，然后再pop回上一级VC，这时就可以走到`dealloc`方法了。但是这样并不雅观。

问题的关键是self（vc）被timer强引用，那么target不是self(vc)不就可以了吗？

```objectivec
#import "NSTimer+Addition.h"
@implementation NSTimer (Addition)
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval block:(void(^)())block repeats:(BOOL)repeats{
    return [self scheduledTimerWithTimeInterval:interval
                                         target:self
                                       selector:@selector(blockInvoke:)
                                       userInfo:[block copy]
                                        repeats:repeats];
}

+ (void)blockInvoke:(NSTimer *)timer {
    void (^block)() = timer.userInfo;
    if(block) {
        block();
    }
}
@end

vc：
- (void)viewDidLoad {
    [super viewDidLoad];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 block:^{
        NSLog(@"timer2 run");
    } repeats:YES];
}

- (void)dealloc{
    NSLog(@"销毁了");
    [self.timer invalidate];
}
```

返回上级VC，可以走到`dealloc`。

![](http://upload-images.jianshu.io/upload_images/1727123-ebfb1f710729493f.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

这里利用的是`NSTimer`分类作为`target`，还使用了block（也要注意block造成的循环引用问题，如果block捕获了self，而timer又通过userInfo持有block，最后self本身又持有timer就会形成保留环）。这里真正创建timer实例的地方是在`NSTimer`的`Category`中，而且`target`也是`NSTimer`，`NSTimer`持有`timer`实例，`timer`实例持有`NSTimer`，还是有循环引用的。要想打破上述循环引用，需要在创建`timer`的类(非NSTimer)中对`timer`进行`invalidate`。

[另一种制造假target的写法，本质上还是相同的](http://www.cocoachina.com/ios/20150710/12444.html)

## 4、子线程中使用NSTimer的坑
#### 情形一：
A界面 push进入B界面，在B中创建子线程，子线程中创建timer、开启runloop；B上的按钮用来释放timer，点击B导航栏返回按钮返回A。

```objectivec
@property (nonatomic ,weak)NSTimer *timer;
@property (nonatomic )CFRunLoopRef runloop;
@property (nonatomic ,weak)NSThread *thread;
@property (nonatomic )CFRunLoopObserverRef observer;

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    UIButton *btn = [[UIButton alloc]initWithFrame:CGRectMake(0, 80, 50, 50)];
    btn.backgroundColor = [UIColor redColor];
    [self.view addSubview:btn];
    [btn addTarget:self action:@selector(clicked) forControlEvents:UIControlEventTouchUpInside];
    
    NSThread *thread = [[NSThread alloc]initWithTarget:self selector:@selector(threadMethod) object:nil];
    self.thread = thread;
    [self.thread start];
}

- (void)timerMethod{
    NSLog(@"timer2 run");
}
- (void)dealloc{
    NSLog(@"销毁了");
// CFRelease(self.observer);
}

- (void)clicked{
  [self.timer invalidate];
}

- (void)threadMethod{
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timerMethod) userInfo:nil repeats:YES];
    self.runloop = CFRunLoopGetCurrent();
 
    self.observer = CFRunLoopObserverCreateWithHandler(CFAllocatorGetDefault(), kCFRunLoopAllActivities, YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        NSLog(@"----监听到RunLoop状态发生改变---%zd", activity);
    });
    CFRunLoopAddObserver(self.runloop, self.observer, kCFRunLoopDefaultMode);
    
    CFRunLoopRun();
    CFRelease(self.observer);
}
```

这段代码在iOS10、iOS9环境下运行结果不太一样。

iOS9

![iOS9](http://upload-images.jianshu.io/upload_images/1727123-f391ae5aa1ae8692.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

iOS10

![iOS10](http://upload-images.jianshu.io/upload_images/1727123-0350c135315d7541.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

iOS10环境下，从B返回A，B不会被释放（无法走到dealloc）。从运行结果看来，iOS10中子线程runloop最后一直处于休眠状态。

分析：

在B中创建了一个子线程，通过`NSThread *thread = [[NSThread alloc]initWithTarget:self selector:@selector(threadMethod) object:nil];`，子线程会对target也就是self（B控制器）进行强引用，这是B无法释放的原因。要释放B就要退出子线程，也就是要退出子线程的runloop。所以问题可能就是iOS9、iOS10在处理子线程runloop上有不同。

参考文章第一篇讲到：

>  若目标RunLoop当前没有定时源需要处理（像上面的例子那样，子线程RunLoop只有一个定时器，该定时器移除后，则子线程RunLoop没有定时源需要处理），则通知内核不需要再向当前Timer Port发送定时消息并移除该Timer Port。在iOS10环境下，当移除Timer Port后，内核会把消息列表中与该Timer Port相应的定时消息移除，而iOS10以前的环境下，当移除Timer Port后，内核不会把消息列表中与该Timer Port相应的定时消息移除。iOS10的处理是更为合理的，iOS10以前的处理可能是历史遗留问题吧。
>
例子中涉及到线程异步的问题，定时器是在子线程RunLoop中注册的，但定时器的移除操作却是在主线程，由于子线程RunLoop处理完一次定时信号后，就会进入休眠状态。在iOS10以前的环境下，定时器被移除后，内核仍然会向对应的Timer Port发送一次信号，所以子线程RunLoop接收到信号后会被唤醒，由于没有定时源需要处理，所以RunLoop会直接跳转到判断阶段，判断阶段会检测当前RunLoopMode是否有事件源需要处理，若没有事件源需要处理，则会退出RunLoop。**由于例子中子线程RunLoop的当前RunLoopMode只有一个定时器，而定时器被移除后，RunLoopMode就没有了需要处理的事件源，所以会退出RunLoop，子线程的主函数也因此返回，页面B对象被释放。**
> 

但在iOS10环境下，当定时器被移除后，内核不再向对应的Timer Port发送任何信号，所以子线程RunLoop一直处于休眠状态并没有退出，而我们只需要手动唤醒RunLoop即可。

从上面iOS9运行结果图来看，红框的两处时间差正好在一秒左右。（我点击按钮的时间在最后一次休眠和最后一次唤醒之间，在这期间timer被移除）

![iOS9](http://upload-images.jianshu.io/upload_images/1727123-76f4763543867d86.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

对比iOS10运行结果（点击按钮的事件也是在最后一次休眠之后），确实可以得出结论：iOS9环境下，timer移除后，内核确实向timer port再次发送了信号使得子线程runloop唤醒，最后runloop由于没有mode item而退出。

所以也即：

```objectivec
- (void)clicked{
    [self.timer invalidate];
    CFRunLoopWakeUp(self.runloop);
}
```
手动唤醒runloop，这样改动以后的运行结果：

![iOS10](http://upload-images.jianshu.io/upload_images/1727123-ae8a78b06d8414d9.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

又或者是，不使用`CFRunLoopWakeUp`而直接用`CFRunLoopStop( )`来退出runloop。因为使用`CFRunLoopWakeUp`，相当于是让runloop依赖当前runloop mode有没有事件源来决定是否退出。而这种方法本身就不是十分靠谱，因为系统也有可能给runloop添加一些事件源，导致runloop不一定会退出。

ps:一些题外话。是一些自我思路纠正，写出来是为了给自己日后看的。各位看官可以跳过这部分~

在最开始写完这笔记之后的几天又翻出这段代码来看。大概是头脑短路吧..曾经认为上面代码中的按钮点击是一个子线程runloop source0。。。还做了下面一张图分析。。。（大概犯蠢没看清按钮事件的时机）

![](http://upload-images.jianshu.io/upload_images/1727123-2a1324396ab4534e.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

不过很快就意识到这哪里是什么子线程source0....子线程runloop没有source0只有timer和observer（明明之前自己还nslog出来过）！这个按钮事件是主线程的嘛！

然后在误打误撞的情况下...我在主线程runloop又添加了一个observer对主线程runloop状态进行监听，代码很简单我就不贴了。从A进入到B，什么都不要做，等待main runloop稳定下来（一开始main runloop很活跃，最后稳定下来就是休眠了，只剩下子线程runloop状态在控制台有输出，如下图）。在我点击按钮之后，main runloop唤醒，iOS10中子线程同上最后一直处于休眠状态。

![iOS10测试](http://upload-images.jianshu.io/upload_images/1727123-cab68f1d33877f29.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

要唤醒runloop休眠有这么几种情况：基于端口的输入源到达（source1）、timer唤醒、runloop超时时间到、人为手动唤醒runloop。

因为一直认为点击按钮时这一行为是一个source0，所以对主线程runloop唤醒感到意外。然后重新看回[深入理解runloop](http://blog.ibireme.com/2015/05/18/runloop/)这篇文章，发现有这么一个Q&A：

> Q:还有一个问题哈，就是UIButton点击事件打印堆栈看的话是从source0调出的，文中说的是source1事件，不知道哪个是正确的呢？
A:首先是由那个Source1 接收IOHIDEvent，之后在回调 `__IOHIDEventSystemClientQueueCallback()` 内触发的 Source0，Source0 再触发的` _UIApplicationHandleEventQueue()`。所以UIButton事件看到是在 Source0 内的。你可以在 `__IOHIDEventSystemClientQueueCallback` 处下一个 Symbolic Breakpoint 看一下。

按照作者的回答，做了测试，发现的确是那样的。所以主线程的唤醒是由于source1事件。

#### 情形二
但上面这种写法是在子线程创建timer，在主线程中销毁timer。根据`invalidate`方法api文档中提到的，NSTimer 在哪个线程创建就要在哪个线程停止，否则会导致资源不能被正确的释放。所以如果要修改一下：

```objectivec
- (void)clicked{
    if (self.timer && self.thread) {
        [self performSelector:@selector(cancel) onThread:self.thread withObject:nil waitUntilDone:YES];
    }
}

- (void)cancel{
    if (self.thread) {
        [self.timer invalidate];
//        CFRunLoopWakeUp(self.runloop);//不能dealloc
        CFRunLoopStop(self.runloop);//可以dealloc
    }
}
```

这里调用perform..，是会给runloop添加源的，所以要退出runloop就不能使用`CFRunLoopWakeUp`了。

ps:本来想着要让子线程退出，那就使用`[NSThread exit]`，但貌似是行不通。。

#### 情形三 
让子线程timer计数几次就停止

```objectivec
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    count = 0;

    NSThread *thread = [[NSThread alloc]initWithTarget:self selector:@selector(threadMethod) object:nil];
    self.thread = thread;
    [self.thread start];
}
- (void)threadMethod{
    @autoreleasepool {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timerMethod:) userInfo:nil repeats:YES];
//            self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 block:^{
//                NSLog(@"timer2 run");
//            } repeats:YES];
        self.runloop = CFRunLoopGetCurrent();
        self.observer = CFRunLoopObserverCreateWithHandler(CFAllocatorGetDefault(), kCFRunLoopAllActivities, YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
            NSLog(@"----监听到RunLoop状态发生改变---%zd", activity);
        });
        CFRunLoopAddObserver(self.runloop, self.observer, kCFRunLoopDefaultMode);
        CFRunLoopRun();
        CFRelease(self.observer);
        NSLog(@"thread end");
    }
}

- (void)timerMethod:(NSTimer *)timer{
    count++;
    NSLog(@"timer2 run");
    if (count == 2) {
        [timer invalidate];
        NSLog(@"timer invalidate");
    }
}
- (void)dealloc{
    NSLog(@"销毁了");
}
```

![iOS10](http://upload-images.jianshu.io/upload_images/1727123-a602d67ae5505daa.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

和情形一不同，这里移除timer的操作是放在子线程中做的（在timer call out中）。从控制台输出中可以看到，这是在子线程runloop唤醒之后才移除timer，接着就进行是否退出runloop的判断。由于子线程runloop中已经没有事件源了，因此runloop就退出了。

在情形一，子线程创建timer，主线程移除timer，点击按钮的时机是由人来把控的，因此会发生在子线程runloop休眠后移除timer导致runloop无法唤醒的问题。而情形三则没有这样的问题，资源可以得到安全释放。vc返回上一级也能得到销毁。

## 5、其他
- NSTimer不支持暂停和继续
- NSTimer不支持后台运行（真机），但是模拟器上App进入后台的时候，NSTimer还会持续触发。真机进入后台timer会停。

参考文章：
http://www.jianshu.com/p/7045813769fd
