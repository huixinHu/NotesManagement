# 多线程基本概念

单核CPU，同一时间cpu只能处理1个线程,只有1个线程在执行 。多线程同时执行:是CPU快速的在多个线程之间的切换。如果线程数非常多,线程切换会消耗大量的cpu资源。相同时间内，每个线程被调度的次数会降低,线程的执行效率降低 。

优点：
能适当提高程序的执行效率
能适当提高资源的利用率（CPU&内存）
线程上得任务执行完后自动销毁

缺点：
开启线程需要占用一定的内存空间(默认情况下,每一个线程都占512KB)
如果开启大量的线程,会占用大量的内存空间,降低程序的性能
线程越多,cpu在调用线程上的开销就越大
程序设计更加复杂,比如线程间的通信、多线程的数据共享

主线程：
一个程序运行后,默认会开启1个线程,称为“主线程”或“UI线程”
主线程一般用来 刷新UI界面 ,处理UI事件(比如:点击、滚动、拖拽等事件)
主线程使用注意 别将耗时的操作放到主线程中耗时操作会卡住主线程,严重影响UI的流畅度,给用户一种卡的坏体验

iOS中目前有四种实现多线程的方案：

```
1.pthread
2.NSThread
3.GCD
4.NSOperation
```

# pthread
一套在多操作系统上通用的多线程API，跨平台、可移植性强，基于C语言。线程的生命周期需要程序员自己管理，基本不怎么使用。

#### 简单使用：
创建一个子线程并在子线程中执行一个函数。

```objective-c
#import <pthread.h>

#pragma mark --pthread
- (void)pthreadDemo1{
    pthread_t PID;
    //参数1：pthread_t 线程的标示
    //参数2：pthread_attr_t 线程的属性
    //参数3：void*  (*)  (void *)  函数签名， void *大约可以理解为oc中的id
    //      返回值  函数名 参数
    //参数4：给函数（参数3）的参数
    //返回值：0 成功，非0 失败
    int result = pthread_create(&PID, NULL, task, NULL);
    if (result == 0) {
        NSLog(@"ok");
    }else{
        NSLog(@"fail");
    }
}
void * task(void *param){
    NSLog(@"task is running %@",[NSThread currentThread]);
    return NULL;
}
- (IBAction)clicked:(id)sender {
    NSLog(@"main thread:%@",[NSThread currentThread]);
    [self pthreadDemo1];
}
```

![pthreadDemo1.png](http://upload-images.jianshu.io/upload_images/1727123-7f863c060c377a99.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

```objective-c
- (void)pthreadDemo2{
    pthread_t PID;

    NSString *str = @"str";
//    char * str2 = "str2";   
//    int result = pthread_create(&PID, NULL, task, str2);
    int result = pthread_create(&PID, NULL, task, (__bridge void *)(str));
    if (result == 0) {
        NSLog(@"ok");
    }else{
        NSLog(@"fail");
    }
}
void * task(void *param){
//    printf("%s\n",param);
    
    NSString *str = (__bridge NSString *)(param);
    NSLog(@"正在运行的线程： %@,  ->%@",[NSThread currentThread],param);
    NSLog(@"正在运行的线程：%@,  ->%@",[NSThread currentThread],str);
    return NULL;
}
```

 注意：ARC默认下对OC对象进行内存管理，不对C变量管理，桥接的作用是让C变量在合适的时候进行释放。在ARC中使用到和C语言对应的数据类型，就应该使用__bridge进行桥接，在MRC中则不需要。
    
![pthreadDemo2.png](http://upload-images.jianshu.io/upload_images/1727123-f966a1ebaff33524.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

使用pthread需要自己管理线程的生命周期，上面的代码中创建了线程但是没有销毁。

# NSThread
面向对象，可以直接操作线程对象，基于OC语言。线程的生命周期仍然需要程序员自己进行管理，使用频率不高。可以通过[NSThread currentThread]获取当前线程，以此获取线程的各种属性，便于调试。

#### 创建和启动线程
- 需要手动启动
 
```objective-c
    //参数1：对象
    //参数2：方法
    //参数3：参数2方法需要的参数
    NSThread *thread = [[NSThread alloc]initWithTarget:self selector:@selector(task2) object:nil];
    [thread start];//线程启动后在thread中执行task2方法
```

- 自动启动

```objective-c
[NSThread detachNewThreadSelector:@selector(task2) toTarget:self withObject:nil];
```

或者:

```objective-c
//隐式创建并自动启动线程
[self performSelectorInBackground:@selector(task2) withObject:nil];
```

后面这两种创建线程并自动启动线程的方法有一个缺点：没有办法对线程的一些属性进行设置。

#### 线程的状态

![](http://upload-images.jianshu.io/upload_images/1727123-431102dbfb6bf0b7.JPG?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

1. `NSThread *thread = [[NSThread alloc]initWithTarget:self selector:@selector(task3) object:nil];`线程新建状态。在内存中创建出一个线程对象。

 ![](http://upload-images.jianshu.io/upload_images/1727123-3f8cd7915aed6fed.JPG?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

2. `[thread start];`线程就绪状态。线程对象被放入可调度线程池，池中还有别的其他线程对象。等待CPU调度。

 ![](http://upload-images.jianshu.io/upload_images/1727123-4ca61d762bc7cbe5.JPG?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

3. CPU调度当前线程，线程进入运行状态。当CPU调度其他线程，线程回到就绪状态。

4. `[NSThread sleepForTimeInterval:1];`线程阻塞状态。当调用了sleep方法，或者在等待同步锁。线程对象移出可调度线程池

 ![](http://upload-images.jianshu.io/upload_images/1727123-28baf900ca449d76.JPG?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

5. 当sleep时间到时或得到了同步锁，回到就绪状态。

6. 线程死亡。线程任务执行完毕，自然死亡；强制退出，手动杀死。线程一旦死亡了，就不能再次开启任务。

![](http://upload-images.jianshu.io/upload_images/1727123-516bcc849863c537.JPG?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

```objective-c
- (void)stateDemo{
    //新建状态
    NSThread *thread = [[NSThread alloc]initWithTarget:self selector:@selector(task3) object:nil];
    //就绪状态
    [thread start];
}
- (void)task3{
    //运行
    NSLog(@"正在运行的线程：%@",[NSThread currentThread]);
    //阻塞
    NSLog(@"线程即将进入阻塞状态");
    [NSThread sleepForTimeInterval:1];
//    [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];//线程休眠时间
    //从阻塞->就绪->运行。被cpu调用，进入运行状态
    NSLog(@"线程唤醒");
    //线程死亡。可以自然死亡也可以被手动杀死，当线程任务执行完毕，自动进入死亡状态
    //手动杀死
    [NSThread exit];
    NSLog(@"dead");//这句话将不会被打印出来
 
    //一旦线程死亡，就不能再次开启任务
}
```

![stateDemo.png](http://upload-images.jianshu.io/upload_images/1727123-17c3663f1edfdc83.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

#### 常用属性、方法
更多的属性、方法请参阅文档

```objective-c
名字属性。
@property (nullable, copy) NSString *name；
设置线程名:
NSThread *thread = [[NSThread alloc]initWithTarget:self selector:@selector(task4) object:nil];
thread.name = @"thread";

获得当前线程
+ (NSThread *)currentThread;
获得主线程
+ (NSThread *)mainThread;
是否为主线程
- (BOOL)isMainThread; 
线程优先级
+ (double)threadPriority；
设置优先级：
- (void)attrDemo2{
    NSThread *thread = [[NSThread alloc]initWithTarget:self selector:@selector(task4) object:nil];
    thread.name = @"thread";
    thread.threadPriority = 0;
    [thread start];    
    NSThread *thread2 = [[NSThread alloc]initWithTarget:self selector:@selector(task4) object:nil];
    thread2.name = @"thread2";
    [thread2 start];
}
- (void)task4{
    for (int i = 0; i<20; i++) {
        NSLog(@"当前线程：%@,%d",[NSThread currentThread],i);
    }
}
```

线程优先级取值范围0.0-1.0，默认为0.5，值越大优先级越高。设置优先级并不意味着优先级高的线程要比优先级低的线程先运行（运行反映的结果就是，打印结果里面显示的第一条是哪个thread）,只是更可能被CPU执行到。先执行哪个线程是由cpu调度决定的。

![](http://upload-images.jianshu.io/upload_images/1727123-ab10e13c8fb57f30.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

#### 线程间通信
```
常用方法：NSThread类
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(nullable id)arg waitUntilDone:(BOOL)wait;
- (void)performSelector:(SEL)aSelector onThread:(NSThread *)thr withObject:(nullable id)arg waitUntilDone:(BOOL)wait；
```

# GCD
旨在替代NSThread等的线程技术，充分利用多核，基于C语言。线程的生命周期是自动管理的，不需要程序员手动管理线程的创建/销毁/复用过程。经常使用。

#### 任务、队列

任务和队列是GCD中的两个核心概念。
**任务**就是要执行什么操作，在GCD中通过block来指定要执行的代码。**队列**用来存放任务。

**GCD使用的两个步骤：**

1.定制任务：确定想做的事情
2.将任务添加到队列中，指定运行方式。

GCD会自动将队列中的任务取出，放到对应的线程中执行。任务的取出遵循队列的FIFO原则，先进先出。

```objective-c
    //创建任务
    //dispatch_block_t的定义typedef void (^dispatch_block_t)(void);任务实际上是一个Block
    dispatch_block_t task = ^{
        NSLog(@"task %@",[NSThread currentThread]);
    };
    //获取队列
    dispatch_queue_t queue = dispatch_get_global_queue(0, 0);  
    //把任务放到队列中
    //参数1：队列  参数2：任务
    dispatch_async(queue, task);    
    //简化
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSLog(@"task %@",[NSThread currentThread]);
    });
```

不需要管理线程的生命周期；线程能够复用

```objective-c
    for (int i = 0; i < 20; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSLog(@"task %@ %d",[NSThread currentThread] , i);
        });
    }
```

![GCD复用线程.png](http://upload-images.jianshu.io/upload_images/1727123-37dcada4ea580787.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

- 队列

队列的类型：并发队列、串行队列。

并发队列：可以让多个任务**并发（同时）**执行（自动开启多个线程“同时”执行任务）。并发功能只有在**异步**时才有效。

串行队列：无论是同步异步，任务都是一个接一个地执行。

无论是串行队列还是并发队列，队列里面的任务取出都遵循FIFO原则。并发队列取出任务就分发到可用的线程里，取出的动作很快，就相当于是所有任务都是一起执行的。

全局并发队列：供整个应用使用，GCD有函数可以获得，不需要手动创建

主队列：它是特殊的**串行**队列，又叫全局串行队列，代表着主线程。

 队列的创建：
 
`dispatch_queue_create(const char *label, dispatch_queue_attr_t attr);`第一个参数是唯一标识符，也可以当做是队列的名称，用于debug。第二个参数是队列的属性，表示创建的是并发队列还是串行队列，`DISPATCH_QUEUE_SERIAL`或者NULL为串行，`DISPATCH_QUEUE_CONCURRENT`为并发。

`dispatch_get_main_queue()`获得主队列。

`dispatch_get_global_queue(long identifier, unsigned long flags);`获得全局并发队列.参数1为队列的优先级。参数2暂时没有用，填0即可。

**全局队列、并发队列的区别:**
 
全局队列没有名称,无论 MRC & ARC 都不需要考虑释放。

并发队列有名字，和 NSThread 的 name 属性作用类似；如果在 MRC 开发时，需要使用 dispatch_release(q); 释放相应的对象；dispatch_barrier 必须使用自定义的并发队列；开发第三方框架时，建议使用并发队列

- 任务

任务的执行方式：同步、异步。同步异步的区别是，是否会阻塞**当前线程**。

同步执行会阻塞当前线程，等到block任务执行完毕，然后当前线程再继续往下运行。异步执行不会阻塞当前线程。通常的表现是：同步是在当前线程中执行，异步是在另一条线程中执行，但也有例外。

通过打断点来看同步异步的运行过程来理解会更直观。

看下面的例子：

**串行队列，同步执行**

```objective-c
- (void)demo1{
    //创建串行队列
    //参数1:队列的名字  参数2：队列的属性
    dispatch_queue_t serialQueue =  dispatch_queue_create("serial", DISPATCH_QUEUE_SERIAL);
    for (int i = 0; i < 10 ;i++ ){
        dispatch_sync(serialQueue, ^{
            NSLog(@"serialQueue %@ %d",[NSThread currentThread],i);
        });
    }
    //用途：在多个线程时，要确保在一个线程执行完任务再去执行另一个线程上的任务    
}
```

![串行队列，同步执行-多任务.png](http://upload-images.jianshu.io/upload_images/1727123-f64b8ab000e628be.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

运行结果显示：不开线程，在当前线程下执行（阻塞当前线程）；任务是有序执行的。

**串行队列，异步执行**

```objective-c
- (void)demo2{
    dispatch_queue_t serialQueue =  dispatch_queue_create("serial", DISPATCH_QUEUE_SERIAL);
    for (int i = 0; i < 10 ;i++ ){
        dispatch_async(serialQueue, ^{
            NSLog(@"serialQueue %@ %d",[NSThread currentThread],i);
        });
    }    
}
```

![串行队列，异步执行-多任务.png](http://upload-images.jianshu.io/upload_images/1727123-a737339e07ce916a.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

运行结果显示：另外开一个线程（不会阻塞当前线程）；任务是有序执行的。
修改demo1 demo2不进行循环创建，通过打断点来看同步异步的区别：异步，当代码块执行时demo2:方法已经退出了；同步，demo1:一直等到代码块执行完才退出

**并发队列，异步执行**

```objective-c
- (void)demo3{
    //创建并发队列
    dispatch_queue_t concurrentQueue = dispatch_queue_create("concurrent", DISPATCH_QUEUE_CONCURRENT);
    for (int i =0; i<10; i++) {
        dispatch_async(concurrentQueue, ^{
            NSLog(@"concurrent %@ %d",[NSThread currentThread],i);
        });
    }
}
```

![](http://upload-images.jianshu.io/upload_images/1727123-491d1c9d25c61d99.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

运行结果显示：开多个线程（不会阻塞当前线程），任务无序执行。效率最大。每次开启多少个线程是不固定的（线程数由GCD来决定）

**并发队列，同步执行**

```objective-c
- (void)demo4{
    dispatch_queue_t concurrentQueue = dispatch_queue_create("concurrent", DISPATCH_QUEUE_CONCURRENT);
    for (int i =0; i<10; i++) {
        dispatch_sync(concurrentQueue, ^{
            NSLog(@"concurrent %@ %d",[NSThread currentThread],i);
        });
    }
}
```

![](http://upload-images.jianshu.io/upload_images/1727123-812b9b5d64c15e0f.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

运行结果显示：不开线程，在当前线程下执行（当前线程不一定是主线程）；任务是有序执行的。这种情况等同于，串行队列同步执行

**主队列，异步执行**

```objective-c
- (void)demo5{
    //得到主队列
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    for (int i =0; i<10; i++) {
        dispatch_async(mainQueue, ^{
            NSLog(@"mainQueue %@",[NSThread currentThread]);
        });
    }
}
```

![主队列，异步执行.png](http://upload-images.jianshu.io/upload_images/1727123-17acee3c473d3140.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

主队列是特殊的串行队列，永远在主线程执行。运行结果显示：任务顺序执行，由于是异步，因此并不会阻塞当前线程（主线程）。

**主队列，同步执行**

```objective-c
- (void)demo6{
     NSLog(@"开始");
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    dispatch_sync(mainQueue, ^{
        NSLog(@"mainQueue %@",[NSThread currentThread]);//这个任务要等待-demo6执行完成才能继续执行
    });
    NSLog(@"结束");
}
```

运行的结果显示，只会打印出“开始”这一句，然后后面主线程就卡死了。程序死锁。

原因：同步执行会阻塞当前线程。当前-demo6方法在**主线程**中执行，它把block任务放到**主队列**中执行，即执行到dispatch_sync()的时候，主线程就被阻塞了。主线程要等到任务执行完成之后才会继续往下执行，而block任务要等到主线程中的-demo6方法执行完之后才能执行。由此造成死锁，主线程卡死。

总结：

![](http://upload-images.jianshu.io/upload_images/1727123-10e3543460c3fc9c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

#### 线程间通信

```objective-c
dispatch_async(dispatch_get_global_queue(0, 0), ^{  //也叫后台执行
    // 执行耗时的异步操作...
      dispatch_async(dispatch_get_main_queue(), ^{
        // 回到主线程，执行UI刷新操作
        });
});
```

#### 队列组
队列组可以将很多队列添加到一个组里，当这个组里所有的任务都执行完了，队列组会通过一个方法通知我们。

假设现在有这样一个需求：分别异步执行两个耗时操作；等两个异步操作都执行完毕，再回到主线程执行操作。这时可以使用队列组来高效实现。

```objective-c
-(void)demo{
    NSLog(@"begin");
    //创建组
    dispatch_group_t group = dispatch_group_create();
    //开启异步任务,参数1:队列组；参数2:队列；参数3:任务
    dispatch_group_async(group, dispatch_get_global_queue(0, 0), ^{
        [NSThread sleepForTimeInterval:arc4random_uniform(5)];
        NSLog(@"下载 文件1.zip %@",[NSThread currentThread]);
    }); 
    dispatch_group_async(group, dispatch_get_global_queue(0, 0), ^{
        [NSThread sleepForTimeInterval:arc4random_uniform(5)];
        NSLog(@"下载 文件2.zip %@",[NSThread currentThread]);
    });
    //完成队列组的任务后进行通知，参数1:队列组；参数2:队列；参数3:任务
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSLog(@"下载完成 %@",[NSThread currentThread]);
    });
}
```

#### 一次性执行
被调用多次，但只会执行一次。它是线程安全的

```objective-c
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
//    for (int i = 0; i < 20; i++) {
//        [self demo];
//    }    
    //多线程测试
        for (int i = 0; i < 20; i++) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                [self demo];
            });
        }  
}
-(void)demo{
    NSLog(@"这句话执行多次");
    static dispatch_once_t onceToken;
    NSLog(@"%ld",onceToken);
    dispatch_once(&onceToken, ^{
        NSLog(@"once");
    });
}
```

dispatch_once_t 实际上被定义为long类型，demo方法中打印出onceToken的值中可以看出，在代码第一次被调用的时候，onceToken的值为0（即使在多线程下可能会有多个0值打印出来），此时block里面的代码会被执行而且只会执行一次。当代码再次被调用，onceToken的值为非0，block代码不会被执行。onceToken值相当于是一个flag，用来标记block里面的代码是否已经被执行过。

#### 单例模式
OC里面实现单例在此不进行详述，用到了 GCD 的 dispatch_once方法。
实现单例还可以用互斥锁，但相比GCD性能要差得多（没有得到锁的线程一直在等待。）

```objective-c
@implementation Singleton
+(instancetype)configSync{
    static Singleton *instance;    
    @synchronized(self) {
        if(instance == nil){
            instance = [[Singleton alloc] init];
        }
    }    
    return instance;    
}
@end
```

# NSOperation
面向对象，基于GCD封装，比GCD多一些简单的功能，基于OC语言。线程的生命周期是自动管理的，经常使用。

`NSOperation` 和`NSOperationQueue`就相当于是GCD 的任务和队列。

**NSOperation实现多线程的具体步骤**

 1. 将需要执行的任务封装到一个NSOperation对象中
 2. 将NSOperation对象添加到NSOperationQueue中
 3. 系统会自动将NSOperationQueue中的NSOperation取出来
 4. NSOperation封装的任务被放到一条新线程中执行

#### 任务NSOperation
NSOperation是一个抽象类，不具备封装任务的能力，不可以直接使用，它只是约束子类都具有共同的属性和方法。因此必须使用它的子类：

1. `NSInvocationOperation`
2. `NSBlockOperation`
3. 自定义子类，继承`NSOperation`，实现内部相应的方法

子类创建`operation`使用的方法虽不尽相同，但最后都需要调用start方法来启动执行任务。默认情况下，调用`start`方法后**不会新开一个线程执行任务**，而是在**当前线程同步执行**，只有将`NSOperation`放入一个`NSOperationQueue`中，才会**异步**执行操作。

-  NSInvocationOperation比较少用

```objective-c
 - (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
 //创建operation
 NSInvocationOperation *op = [[NSInvocationOperation alloc]initWithTarget:self selector:@selector(demo1) object:nil];//任务在主线程(当前线程)运行
  //启动任务
  [op start];
}

 - (void)demo1{
    NSLog(@"任务1当前线程----%@",[NSThread currentThread]);//在主线程运行
}
```

-  NSBlockOperation

```objective-c
 - (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
//创建operation
    NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"当前线程----%@",[NSThread currentThread]);
    }];//还是主线程
    //额外的任务在子线程执行
    [op addExecutionBlock:^{
        NSLog(@"当前线程----%@",[NSThread currentThread]);
    }];
    [op start];
}
```

![红框 并发执行](http://upload-images.jianshu.io/upload_images/1727123-b2b80ce4d1d96489.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

`addExecutionBlock`方法给operation添加额外的任务，这时operation中的所有任务**并发执行（当前线程和其他子线程）**

（只要NSBlockOperation封装的任务数大于1，就会异步执行？

- 自定义子类

 当以上两个子类无法满足需求时，又或者需要封装任务等等，就需要自定义operation。
自定义operation需要继承`NSOperation`类，并实现`main` 方法，因为在调用`start`方法的时候，内部会调用`main`方法完成相关逻辑。重写main方法的注意点：

1. 自己创建自动释放池（因为如果是异步操作，无法访问主线程的自动释放池）
2. 经常通过```-(BOOL)isCancelled```方法检测操作是否被取消，对取消作出响应
具体举例下面用到再细说。

#### 队列NSOperationQueue
NSOperation可以调用start方法来执行任务，但因为是同步执行，会占用当前线程。但如果把NSOperation添加到NSOperationQueue中，就可以异步执行任务。

- **NSOperationQueue队列类型**：

1. 主队列`[NSOperationQueue mainQueue]`添加到主队列中的任务都会放到主线程中执行
2. 其他队列（包括串行、并发），使用`alloc init`方式创建。**任务只要添加到队列，系统就会自动异步执行任务（自动调用start方法）**。

用maxConcurrentOperationCount（最大并发数）属性控制是串行还是并发队列

- **添加任务的方法：**

```objective-c
 - (void)addOperation:(NSOperation *)op;
 - (void)addOperations:(NSArray<NSOperation *> *)ops waitUntilFinished:(BOOL)wait;
```

```objective-c
 - (void)operationQueueDemo1{
    //将NSOperation添加到NSOperationQueue中，系统会自动**异步执行**任务
    //创建队列
    NSOperationQueue *opqueue = [[NSOperationQueue alloc]init];
    //创建operation
    NSInvocationOperation *op = [[NSInvocationOperation alloc]initWithTarget:self selector:@selector(demo1) object:nil];
    
    NSBlockOperation *op2 = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"任务2当前线程----%@",[NSThread currentThread]);
    }];
    
    [op2 addExecutionBlock:^{
        NSLog(@"任务3当前线程----%@",[NSThread currentThread]);
    }];
    
    NSBlockOperation *op3 = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"任务4当前线程----%@", [NSThread currentThread]);
    }];
    
    CustomOperation *op4 = [[CustomOperation alloc] init];//自定义operation
    
    // 添加任务到队列中
    [opqueue addOperation:op];//一旦添加，就会执行（自动start），并发，且每添加一个operation开一条子线程
    [opqueue addOperation:op2];
    [opqueue addOperation:op3];
    [opqueue addOperation:op4];//添加自定义operation，自动调用start,start调用main
    //添加任务的另一种更简洁的方式，和上面是等价的
    [opqueue addOperationWithBlock:^{
        NSLog(@"block添加任务,block当前线程----%@",[NSThread currentThread]);
    }];
}
```

![](http://upload-images.jianshu.io/upload_images/1727123-51e949fcd060e709.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

ps:在这里使用了自定义operation

```
 #import "CustomOperation.h"
@implementation CustomOperation
//封装自定义任务，自动调用这个方法
 - (void)main
{
    NSLog(@"自定义operation");
}
@end
```

- **队列最大并发数**

`@property NSInteger maxConcurrentOperationCount;`这个属性用来设置最多可以让多少个任务同时执行。所以，把`maxConcurrentOperationCount`的值设为1，那么队列就是**串行**的了！

```objective-c
 - (void)operationQueueDemo2{
    NSOperationQueue *opqueue = [[NSOperationQueue alloc]init];    
//    opqueue.maxConcurrentOperationCount = 2;
    //串行队列
    opqueue.maxConcurrentOperationCount = 1;
    
    [opqueue addOperationWithBlock:^{
        NSLog(@"block添加任务,任务1当前线程----%@",[NSThread currentThread]);
        [NSThread sleepForTimeInterval:1.0];
    }];
    [opqueue addOperationWithBlock:^{
        NSLog(@"block添加任务,任务2当前线程----%@",[NSThread currentThread]);
        [NSThread sleepForTimeInterval:1.0];
    }];
    [opqueue addOperationWithBlock:^{
        NSLog(@"block添加任务,任务3当前线程----%@",[NSThread currentThread]);
        [NSThread sleepForTimeInterval:1.0];
    }];
    [opqueue addOperationWithBlock:^{
        NSLog(@"block添加任务,任务4当前线程----%@",[NSThread currentThread]);
        [NSThread sleepForTimeInterval:1.0];
    }];
    [opqueue addOperationWithBlock:^{
        NSLog(@"block添加任务,任务5当前线程----%@",[NSThread currentThread]);
        [NSThread sleepForTimeInterval:1.0];
    }];
}
```

maxConcurrentOperationCount=2时运行结果：

![](http://upload-images.jianshu.io/upload_images/1727123-9246b4bb855f4758.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

maxConcurrentOperationCount=1时运行结果：

![](http://upload-images.jianshu.io/upload_images/1727123-f03a383f008b5e51.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

任务执行在哪个线程不是固定的。比如当前最大并发数为2，在同一时间并发执行任务的线程的确有2个，但并不是固定一直都是这两个线程去处理任务。当一个线程执行完任务后，由系统来决定销毁它另开线程还是继续使用这个线程来执行任务

- **队列的暂停、恢复、取消**

暂停、恢复：`suspended`属性

要执行suspended=yes时候，队列挂起，但如果有任务还没执行完，那么这个任务将会继续执行到完成。而队列中余下的任务就会被挂起不执行。
当suspended属性设为No的时候，再继续执行余下的任务。

队列取消：`- (void)cancelAllOperations;`  
   
`cancelAllOperations`取消队列所有的任务，取消了就不会再恢复。`This method calls the cancel method on all operations currently in the queue.`同样，如果有任务还没执行完，那么这个任务将会继续执行到完成。

如果自定义operation中有多个耗时的操作，建议在main方法中在每个耗时操作后判断任务是否已经被取消了，如果取消了，余下的耗时操作将不再执行。

```objective-c
#import "CustomOperation.h"
@implementation CustomOperation
 - (void)main
{
    for (NSInteger i = 0; i<1000; i++) {
        NSLog(@"download1 -%zd-- %@", i, [NSThread currentThread]);
    }
    if (self.isCancelled) return;
    
    for (NSInteger i = 0; i<1000; i++) {
        NSLog(@"download2 -%zd-- %@", i, [NSThread currentThread]);
    }
    if (self.isCancelled) return;
    
    for (NSInteger i = 0; i<1000; i++) {
        NSLog(@"download3 -%zd-- %@", i, [NSThread currentThread]);
    }
    if (self.isCancelled) return;
}
@end
```

- 依赖

NSOperation之间可以设置依赖来保证执行顺序。`[op1 addDependency:op2]`可以让任务op1在任务op2之后执行。

这种任务依赖是可以跨队列的。不能添加相互依赖，会死锁，比如 A依赖B，B依赖A。

```objective-c
 - (void)operationQueueDemo4{
    NSOperationQueue *opqueue = [[NSOperationQueue alloc] init];
    
    NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"任务1----%@", [NSThread  currentThread]);
    }];
    NSBlockOperation *op2 = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"任务2----%@", [NSThread  currentThread]);
    }];
    NSBlockOperation *op3 = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"任务3----%@", [NSThread  currentThread]);
    }];
    NSBlockOperation *op4 = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"任务4----%@", [NSThread  currentThread]);
    }];
    //监听任务是否执行完毕，这个block在任务完成之后执行，而且它不在主线程上，也与它监听的任务不一定在同一个线程上
    op4.completionBlock = ^{
        NSLog(@"op4执行完毕---%@", [NSThread currentThread]);
    };
    
    // 设置依赖，而且这种依赖是可以跨队列的
    [op2 addDependency:op3];
    
    //添加完依赖再把任务加到队列上
    [opqueue addOperation:op];
    [opqueue addOperation:op2];
    [opqueue addOperation:op3];
    [opqueue addOperation:op4];
}
```

![](http://upload-images.jianshu.io/upload_images/1727123-5d5c82fe93ae7952.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

#### 线程间通信
```objective-c
[[[NSOperationQueue alloc] init] addOperationWithBlock:^{
        .......
        // 回到主线程
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            ......
        }];
}];
```

### 其他
#### 线程同步：
为了防止多个线程可能会访问同一块资源，引发数据错乱和数据安全问题，所采取的措施。
- 互斥锁：给需要同步的代码块加一个互斥锁，就可以保证每次只有一个线程访问此代码块。

**售票问题：**   

```objective-c
@property (nonatomic , assign)int tickets;

 - (void)viewDidLoad {
    [super viewDidLoad];
    self.tickets = 5;
    NSThread *thread = [[NSThread alloc]initWithTarget:self selector:@selector(sellTicket) object:nil];
    thread.name = @"窗口1";
    [thread start];    
    NSThread *thread2 = [[NSThread alloc]initWithTarget:self selector:@selector(sellTicket) object:nil];
    thread2.name = @"窗口2";
    [thread2 start];
}
 - (void)sellTicket{
    while (YES) {
        //模拟网络延时
        [NSThread sleepForTimeInterval:1];
        if (self.tickets > 0) {
            self.tickets = self.tickets - 1;
            NSLog(@"%@ 剩余票数%d",[NSThread currentThread],self.tickets);
            continue;
        }
        NSLog(@"卖完了");
        break;
    }
}
```

运行结果:产生数据错乱问题

![](http://upload-images.jianshu.io/upload_images/1727123-b40b94971d6085da.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 **解决方法：** 使用互斥锁（同步锁）

 **格式：**`@synchronized(锁对象){需要锁定的代码}`

 **优缺点：** 能有效防止因多线程抢夺资源造成的数据安全问题。但是需要消耗大量的CPU资源。没有得到锁的线程一直在等待。
 
 **锁可以是任意对象，默认锁是开着的。**
 
```objective-c
@property (nonatomic , strong) NSObject *obj;
 - (void)viewDidLoad {
    [super viewDidLoad];
    self.tickets = 5;
    self.obj = [[NSObject alloc]init];//obj要初始化，锁才有效
    ......（创建线程）
}
 - (void)sellTicket{
    while (YES) {
        //模拟网络延时
        [NSThread sleepForTimeInterval:1];
        //锁是一个任意对象(任意对象都有一把锁)，默认锁是开着的     
        @synchronized(self.obj) {
            if (self.tickets > 0) {
                self.tickets = self.tickets - 1;
                NSLog(@"%@ 剩余票数%d",[NSThread currentThread],self.tickets);
                continue;
            }
            NSLog(@"卖完了");
            break;
        }
    }
}
```

运行结果：是线程安全的

![](http://upload-images.jianshu.io/upload_images/1727123-f94a09f9d89025c2.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

**注意：** 锁定一份代码只能用一把锁，使用多把锁无效。如果把上面的代码改成下面这样，同样会产生数据错乱问题。因为当前while循环中每次循环都创建一把新的锁，锁默认都是开着的。

```objective-c
while (YES) {
    [NSThread sleepForTimeInterval:1];
    NSObject *obj = [[NSObject alloc]init];  
    @synchronized(obj) {
        ......
        }
        NSLog(@"卖完了");
        break;
    }
}
```

**atomic 和nonatomic:**
 
nonatomic非原子属性：多个线程可以同时赋值同时读取。非线程安全的，适合内存小的移动设备。开发中建议把属性声明为nonatomic。
 
atomic原子属性：多个线程中只有一个线程能够对变量赋值(为setter加锁)，但多个线程可以同时**读取**。线程安全，但需要消耗大量资源。**原子属性有自旋锁**
 
互斥锁：如果发现其他线程正在执行锁定的代码，线程休眠（就绪状态），等其他线程开锁后，线程被唤醒。

自旋锁：如果发现其他线程正在执行锁定代码，线程会用死循环的方式一致等待锁定代码完成。自旋锁适合执行不耗时的操作。

不使用互斥锁，如果把tickets声明为atomic，再执行第一段“售票问题”代码的话会怎么样呢？`@property (nonatomic , assign)int tickets;`运行结果显示，自旋锁仍然会有线程安全问题。因为它只对setter加锁，对Getter不加锁。

#### 延时执行：
方式1:NSTimer

```objective-c
 NSTimer *timer = [NSTimer timerWithTimeInterval:1 target:self selector:@selector(task) userInfo:nil repeats:NO];
```
方式2：

```objective-c
[self performSelector:@selector(task) withObject:nil afterDelay:1];
```   

方法3:GCD

```objective-c
    //参数1:延时的时间 dispatch_time生成时间 纳秒为计时单位 精度高
    //参数2:队列
    //参数3:任务
    //异步执行
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    NSLog(@"task");
});
```

相关文章：

[Cocoa深入学习:NSOperationQueue、NSRunLoop和线程安全](https://blog.cnbluebox.com/blog/2014/07/01/cocoashen-ru-xue-xi-nsoperationqueuehe-nsoperationyuan-li-he-shi-yong/)

[iOS多线程你看我就够](http://www.jianshu.com/p/0b0d9b1f1f19)

[iOS 并发编程之 Operation Queues](http://blog.leichunfeng.com/blog/2015/07/29/ios-concurrency-programming-operation-queues/)

[GCD 深入理解：第一部分](https://github.com/nixzhu/dev-blog/blob/master/2014-04-19-grand-central-dispatch-in-depth-part-1.md)

[GCD 深入理解：第二部分](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md)
