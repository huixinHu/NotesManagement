《Objective-C高级编程》这本书就讲了三个东西：自动引用计数、block、GCD，偏向于从原理上对这些内容进行讲解而且涉及到一些比较底层的实现，再加上因为中文翻译以及内容条理性等方面的原因，书本有些内容比较晦涩难懂，在初初读的时候一脸懵逼。本文是对书中block一章的内容做的一些笔记，所以侧重的是讲原理，同时也会对书中讲得晦涩或不合理的地方相对进行一些补充和扩展。

#1.Block结构与实质
使用Block的时候，编译器对Block做了怎样的转换？分析工具clang

例1

```objective-c
#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    void (^blk)(void) = ^{
        NSLog(@"hello");
    };
    blk();
    
    return 0;
}
```

clang：

```cpp
//block实现结构体
struct __block_impl {
  void *isa;
  int Flags;
  int Reserved;
  void *FuncPtr;
};

//block结构体
struct __main_block_impl_0 {
  struct __block_impl impl;
  struct __main_block_desc_0* Desc;
  __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int flags=0) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};

//block代码块中的实现
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {

        NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_f871c6_mi_0);
    }

//block描述结构体
static struct __main_block_desc_0 {
  size_t reserved;
  size_t Block_size;
} __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0)};

int main(int argc, const char * argv[]) {
//block实现
    void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA));
//block调用
    ((void (*)(__block_impl *))((__block_impl *)blk)->FuncPtr)((__block_impl *)blk);

    return 0;
}
```
从main函数入手，对应OC的代码，里面一共做了两件事：实现block、调用block。

1.实现block

```cpp
void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA));
```

它调用了`__main_block_impl_0`结构体的构造函数来实现。`__main_block_impl_0`结构体有两个成员变量，分别是`__block_impl`结构体和`__main_block_desc_0`结构体。

```cpp
// impl结构体
struct __block_impl {
  void *isa;  // 存储位置，_NSConcreteStackBlock、_NSConcreteGlobalBlock、_NSConcreteMallocBlock
  int Flags;  // 按位表示一些 block 的附加信息
  int Reserved;  // 保留变量
  void *FuncPtr;  // 函数指针，指向 Block 要执行的函数，即__main_block_func_0
};

// Desc结构体
static struct __main_block_desc_0 {
  size_t reserved;  // 结构体信息保留字段
  size_t Block_size;  // __main_block_impl_0结构体大小
} __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0)};
```

再来看`__main_block_impl_0`结构体的构造函数

```cpp
__main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int flags=0) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
```

第一个参数需要传入一个函数指针，第二个参数是作为静态全局变量初始化的`__main_block_desc_0`结构体实例指针，第三个参数flags有默认值0。重点看第一个参数，实际调用中传入的是`__main_block_func_0`函数指针：

```cpp
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {

        NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_f871c6_mi_0);
    }
```
这个函数对应的实际上就是block中{}块中的内容，**通过block使用的匿名函数实际上被作为简单的c语言函数来处理**。这个函数的参数`__cself`就相当于OC里的self，`__cself`是`__main_block_impl_0`结构体指针。

**总结：**

```
void (^blk)(void) = ^{
        NSLog(@"hello");
    };

clang:
void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA));
```

实现block，实际就是在方法中声明一个结构体，并且初始化该结构体的成员。
将block语法生成的block赋值给block类型的变量blk，等同于将`__main_block_impl_0`结构体实例的指针赋给变量blk。

2.调用block

```cpp
((void (*)(__block_impl *))((__block_impl *)blk)->FuncPtr)((__block_impl *)blk);
```
调用block就相对简单多了。将第一步生成的block作为参数传入FucPtr（也即_main_block_func_0函数），就能访问block实现位置的上下文。

自此，block结构总体上分析完了，上面的c代码看起来很复杂，但仔细读的话还是很好理解的。
关于[block的数据结构](https://opensource.apple.com/source/libclosure/libclosure-63/Block_private.h.auto.html)和[runtime](http://llvm.org/svn/llvm-project/compiler-rt/trunk/lib/BlocksRuntime/runtime.c)是开源的。block的数据结构：

```cpp
struct Block_descriptor_1 {
    uintptr_t reserved;
    uintptr_t size;
};
 
struct Block_layout {
    void *isa;
    volatile int32_t flags; // contains ref count
    int32_t reserved; 
    void (*invoke)(void *, ...);
    struct Block_descriptor_1 *descriptor;
    // imported variables
};
```

![block结构](http://upload-images.jianshu.io/upload_images/1727123-b2963eb80edb4d78.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

[图片来源](http://www.galloway.me.uk/2013/05/a-look-inside-blocks-episode-3-block-copy/)

这张图有几个要说明的地方：

variables：block捕获的变量，block 能够访问它外部的局部变量，就是因为将这些变量（或变量的地址）复制到了结构体中。这部分接下来会写到。
而对于copy和dispose的部分，之后也会谈到。

在objc中，根据对象的定义，凡是首地址是isa的结构体指针，都可以认为是对象(id)。**这样在objc中，block实际上就算是对象。**

#2.截获外部变量
外部变量有四种类型：自动变量、静态变量、静态全局变量、全局变量。我们知道，如果不使用`__block` 就无法在block中修改自动变量的值。

那么block是怎么截获外部变量的呢？测试代码：

例2：

```objective-c
int a = 1;
static int b = 2;

int main(int argc, const char * argv[]) {

    int c = 3;
    static int d = 4;
    NSMutableString *str = [[NSMutableString alloc]initWithString:@"hello"];
    void (^blk)(void) = ^{
        a++;
        b++;
        d++;
        [str appendString:@"world"];
        NSLog(@"1----------- a = %d,b = %d,c = %d,d = %d,str = %@",a,b,c,d,str);
    };
    
    a++;
    b++;
    c++;
    d++;
	str = [[NSMutableString alloc]initWithString:@"haha"];
    NSLog(@"2----------- a = %d,b = %d,c = %d,d = %d,str = %@",a,b,c,d,str);
    blk();
    
    return 0;
}
```

运行结果：

```
 2----------- a = 2,b = 3,c = 4,d = 5,str = haha
 1----------- a = 3,b = 4,c = 3,d = 6,str = helloworld
```

clang转换之后：

```cpp
struct __block_impl {
  void *isa;
  int Flags;
  int Reserved;
  void *FuncPtr;
};

int a = 1;
static int b = 2;
struct __main_block_impl_0 {
  struct __block_impl impl;
  struct __main_block_desc_0* Desc;
  int *d;
  NSMutableString *str;
  int c;
  __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int *_d, NSMutableString *_str, int _c, int flags=0) : d(_d), str(_str), c(_c) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};

static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
  int *d = __cself->d; // bound by copy
  NSMutableString *str = __cself->str; // bound by copy
  int c = __cself->c; // bound by copy

        a++;
        b++;
        (*d)++;
        ((void (*)(id, SEL, NSString *))(void *)objc_msgSend)((id)str, sel_registerName("appendString:"), (NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_1);
        NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_2,a,b,c,(*d),str);
    }
static void __main_block_copy_0(struct __main_block_impl_0*dst, struct __main_block_impl_0*src) {_Block_object_assign((void*)&dst->str, (void*)src->str, 3/*BLOCK_FIELD_IS_OBJECT*/);}

static void __main_block_dispose_0(struct __main_block_impl_0*src) {_Block_object_dispose((void*)src->str, 3/*BLOCK_FIELD_IS_OBJECT*/);}

static struct __main_block_desc_0 {
  size_t reserved;
  size_t Block_size;
  void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0*);
  void (*dispose)(struct __main_block_impl_0*);
} __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0), __main_block_copy_0, __main_block_dispose_0};

int main(int argc, const char * argv[]) {
    int c = 3;
    static int d = 4;
    NSMutableString *str = ((NSMutableString *(*)(id, SEL, NSString *))(void *)objc_msgSend)((id)((NSMutableString *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("NSMutableString"), sel_registerName("alloc")), sel_registerName("initWithString:"), (NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_0);
    void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, &d, str, c, 570425344));

    a++;
    b++;
    c++;
    d++;
    str = ((NSMutableString *(*)(id, SEL, NSString *))(void *)objc_msgSend)((id)((NSMutableString *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("NSMutableString"), sel_registerName("alloc")), sel_registerName("initWithString:"), (NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_3);
    NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_4,a,b,c,d,str);
    ((void (*)(__block_impl *))((__block_impl *)blk)->FuncPtr)((__block_impl *)blk);

    return 0;
}
```

![为了区别block实现前后栈上变量的变化，用栈1、栈2来做区别](http://upload-images.jianshu.io/upload_images/1727123-6fe5f9e29fc8a949.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

变量a、b是全局的，它们在全局区。变量c、str在函数栈上，为了区别在block实现前、后函数栈上的变量，下文会用“栈1”、“栈2”来区别。

1.自动变量、静态变量。
在`__main_block_impl_0`结构体中可以看到，成员变量多了：

```objective-c
int *d;
NSMutableString *str;
int c;
```

这也是为什么说block会截获变量。接着看到构造函数：

```cpp
__main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int *_d, NSMutableString *_str, int _c, int flags=0) : d(_d), str(_str), c(_c) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
```

构造函数中多了`int *_d`, `NSMutableString *_str`, `int _c`三个参数，并对对应结构体成员变量进行初始化。自此，自动变量和静态变量被截获为成员变量。

截获变量的时机：在main函数的实现中，

```cpp    
void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, &d, str, c, 570425344));
```

在实现block时，会将栈1参数传入构造函数中进行初始化，所以，block会在实现的地方截获变量，而截获的变量的值也是实现时刻的变量值。另外，如果block语法表达式中没有使用到的静态变量、自动变量是不会被追加到`__main_block_impl_0`结构体中的。

然后我们来看一下这个问题：为什么在block语法表达式中不能改变自动变量的值，而静态变量却可以呢？从运行结果来看，为什么block内打印的自动变量的值没有变化？

看到`__main_block_func_0`函数的实现：

```cpp
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
  int *d = __cself->d; // bound by copy
  NSMutableString *str = __cself->str; // bound by copy
  int c = __cself->c; // bound by copy

        a++;
        b++;
        (*d)++;
        ((void (*)(id, SEL, NSString *))(void *)objc_msgSend)((id)str, sel_registerName("appendString:"), (NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_b870bb_mi_1);
        NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_b870bb_mi_2,a,b,c,(*d),str);
    }
```

为了便于下文的理解，我会把以下“=”左边的变量，称为“临时变量”。

```
  int *d = __cself->d; // bound by copy
  NSMutableString *str = __cself->str; // bound by copy
  int c = __cself->c; // bound by copy
```

- 自动变量

 测试代码中的自动变量有两种：1、基本类型的自动变量 int c，2、指向对象的指针的自动变量 `NSMutableString *str`。有一个概念要强调，指针的值是地址。

 ```cpp
  struct __main_block_impl_0 {
  struct __block_impl impl;
  struct __main_block_desc_0* Desc;
  int *d;
  NSMutableString *str;
  int c;
  __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int *_d, NSMutableString *_str, int _c, int flags=0) : d(_d), str(_str), c(_c) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};
```

 分析各种变量之间的关系：

 block截获自动变量为结构体成员变量，对应的数据类型是一样的。

 1、在实现block，调用`__main_block_impl_0`构造函数时，栈1自动变量的瞬时值就被截获、复制保存到结构体成员变量中初始化。block结构体成员变量c得到的是自动变量c的值3，成员变量str得到的是自动变量str的值（可变字符串对象1的地址）。

 2、在实现block后、调用block前，即栈2修改自动变量的值，对结构体中存储的成员变量的值不会造成影响。此时，自动变量c的值为4，str的值为可变字符串对象2的地址。

 3、调用block时，即调用`__main_block_func_0`函数，此时函数中临时变量c、str取到的值是结构体中成员变量存储的值，也即是3和可变字符串对象1的地址。

 如果在block内修改自动变量的值是可行的，也就相当于是在`__main_block_func_0`函数中通过修改临时变量的值，来达到修改栈上自动变量的值的目的。但根据上面分析，每一步都是**值传递**，所以栈上的自动变量的值修改和`__main_block_func_0`函数中修改临时变量的值互不影响。
 
 OC可能就是基于这一点，在编译层面就防止开发者犯错，因此如果在block中修改自动变量的值就会报错！

 如果在block内修改自动变量的值，那代码应该是这样的：

 ```cpp
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
  NSMutableString *str = __cself->str; // bound by copy
  int c = __cself->c; // bound by copy
  
  c++；
  str = ((NSMutableString *(*)(id, SEL, NSString *))(void *)objc_msgSend)((id)((NSMutableString *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("NSMutableString"), sel_registerName("alloc")), sel_registerName("initWithString:"), (NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_150b21_mi_3);
    }
```

 ![](http://upload-images.jianshu.io/upload_images/1727123-2789618770e0f230.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 虽然在block内不能修改str的值，即重新指向其他地址，比如`str = [[NSMutableString alloc]init];`，但可以在block内对str进行操作，比如`[str appendString:@"world"];`。

 ![](http://upload-images.jianshu.io/upload_images/1727123-18c3d31806f54718.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 结论：block在实现时捕获自动变量的瞬时值。

 总结:block捕获到的变量，都是赋值给block的结构体的，相当于const不可改。可以这样理解block内c和str都是const类型。str理解成是常量指针，所以不能修改它指向其他对象但可以修改它所指向对象的“值”。

- 静态变量

 从结构体成员变量` int *d;`看出，block截获静态变量为结构体成员变量，截获的是静态变量的**指针**(不是值传递了！)。

 调用block时，即调用`__main_block_func_0`函数，此时函数中临时变量d取到的值是结构体中成员变量存储的值，即指针，`int *d = __cself->d;`。
 
 这看起来似乎和 自动变量是指向对象的指针 的情况差不多，但一点不同的是，在block内修改静态变量的值是**通过修改指针所指变量**的来做的：`(*d)++`。而这也是为什么block内能修改自动变量的原因。

2.静态全局变量、全局变量。从运行结果来看，这两种外部变量的值都在block内、外得到增加。因为他们是全局的，作用域很广，所以在block内、外都可以访问得到它们。因为这两种变量都没有被追加到`__main_block_impl_0`结构体中成为成员变量，所以我觉得它们不算是被捕获。

分析到这里，相信上面测试代码为什么会得出这样的运行结果应该也能理解了吧？
```
 2----------- a = 2,b = 3,c = 4,d = 5,str = haha
 1----------- a = 3,b = 4,c = 3,d = 6,str = helloworld
```

**总结：**

1. 自动变量（基本数据类型变量、对象类型的指针变量），可以被block捕获，但捕获的是自动变量的值。不能在block内部改变自动变量的值。
2. 静态变量，可以被block捕获，捕获的是变量的地址。通过使用静态变量的指针对其进行访问，可以在block内改变值。
3. 在block内没有被使用到的自动变量、静态变量不会被捕获。
4. 全局变量、静态全局变量，因为作用域范围广，所以可以在block内改变它们的值。

现在来思考一个问题：
静态变量可以在block里面直接改变值是通过传递内存地址值来实现的。那么为什么自动变量没有使用这种方法呢？
下面看一个例子：例3

```objective-c
void(^blk_t)();
@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
        int i = 1;
        int *a = &i;
        static int j = 2;
        blk_t = ^{
            (*a)++;
            NSLog(@"%d, %d", *a, j);
        };
    blk_t();
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    blk_t();
}
```

ARC下运行结果：

```
2,2
1073741825,2 //点击
```

这段代码说明，变量作用域结束时，该作用域栈上的自动变量就被释放了，因此，不能通过指针访问原来的自动变量。栈上的变量被释放掉了,因此点击屏幕时访问释放掉的变量就会得到意想不到的值。

比如很多时候，block是作为参数传递供以后回调用的。往往回调时，定义变量所在的函数栈已经展开了，局部变量已经不再栈中了。

插一个题外话：

```objective-c
void(^blk_t)();
@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    {
        int i = 1;
        int *a = &i;
 
        blk_t = ^{
            (*a)++;
            NSLog(@"%d", *a);
        };
    }
    blk_t();
}
```

本来例3这段代码是想这样写的，但运行结果很正常。一度很疑惑，以为调用block时栈变量没有释放掉。但实际上它已经释放了，只是它原来所占的地址还没重新被分配给别的变量用，数据还是保持原来的。[栈上占用的空间什么时候被释放](http://bbs.csdn.net/topics/370229380)
例3的代码会跑出这样的结果，猜测和runloop休眠、唤醒之间释放自动释放池有关。


#3.block的存储域以及内存管理
##3.1存储域
一般，block有三种：`_NSConcreteGlobalBlock`、`_NSConcreteStackBlock`、`_NSConcreteMallocBlock`，根据Block对象创建时所处数据区不同而进行区别。

##_NSConcreteGlobalBlock
是设置在程序的全局数据区域（.data区）中的Block对象。在全局声明实现的block 或者 没有用到自动变量的block为`_NSConcreteGlobalBlock`，生命周期从创建到应用程序结束。

- 全局block：

  ```objective-c
  void (^glo_blk)(void) = ^{
      NSLog(@"global");
  };
  
  int main(int argc, const char * argv[]) {
      glo_blk();
      NSLog(@"%@",[glo_blk class]);
  }
  ```

  运行结果：
  
  ```
  global
  __NSGlobalBlock__
  ```
  同时，clang编译后isa指针为`_NSConcreteGlobalBlock`。

- 在函数栈上创建但没有截获自动变量

  ```objective-c
  int glo_a = 1;
  static int sglo_b =2;
  int main(int argc, const char * argv[]) {
      void (^glo_blk1)(void) = ^{//没有使用任何外部变量
          NSLog(@"glo_blk1");
      };
      glo_blk1();
      NSLog(@"glo_blk1 : %@",[glo_blk1 class]);
      
      static int c = 3;
      void(^glo_blk2)(void) = ^() {//只用到了静态变量、全局变量、静态全局变量
          NSLog(@"glo_a = %d,sglo_b = %d,c = %d",glo_a,sglo_b,c);
      };
      glo_blk2();
      NSLog(@"glo_blk2 : %@",[glo_blk2 class]);
  ```
  
  运行结果：
  
  ```
  glo_blk1
  glo_blk1 : __NSGlobalBlock__
  glo_a = 1,sglo_b = 2,c = 3
  glo_blk2 : __NSGlobalBlock__
  ```
  
  然而，从clang编译结果来看，这两个block的isa的指针值都是_NSConcreteStackBlock。

##`_NSConcreteStackBlock`和`_NSConcreteMallocBlock`

`_NSConcreteStackBlock`是设置在栈上的block对象，生命周期由系统控制的，一旦所属作用域结束，就被系统销毁了。

`_NSConcreteMallocBlock`是设置在堆上的block对象，生命周期由程序员控制的。

稍微改动一下例3的代码：

```objective-c
void(^blk_t)();
@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    int i = 1;
    int *a = &i;
    blk_t = ^{
        (*a)++;
        NSLog(@"%d", *a );
    };
    NSLog(@"%@",[blk_t class]);
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    blk_t();
}
```

运行结果：

ARC:

```
__NSMallocBlock__
2017-08-11 23:45:52.513 RACPROJECT[49348:1786654] 1073741825
```
MRC：

![](http://upload-images.jianshu.io/upload_images/1727123-699d3da00d9cdca6.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

运行结果会根据ARC\MRC环境而有所不同。

1. block的类型在ARC下是`_NSConcreteMallocBlock`，而在MRC下是_`NSConcreteStackBlock`。在ARC有效时，大多数情况下编译器会恰当地判断，自动生成将block从栈上复制到堆上的代码。
2. 在MRC下，由于Block是`_NSConcreteStackBlock`类型，它是存在于该函数的栈帧上的。当函数返回时，函数的栈帧被销毁，这个block的内存也会被清除。因此在点击屏幕时，程序如图出现crash。

 所以在函数结束后仍然需要这个block时，就必须用copy实例方法将它拷贝到堆上。这样即使Block作用域结束，堆上的Block还可以继续使用。

```objective-c
- (void)viewDidLoad {
    [super viewDidLoad];
    int i = 1;
    int *a = &i;
    blk_t = [^{
        (*a)++;
        NSLog(@"%d", *a );
    } copy];
    NSLog(@"%@",[blk_t class]);
}
```

MRC运行结果：

```
__NSMallocBlock__
```

##3.2block的自动拷贝和手动拷贝
在ARC有效时，大多数情况下编译器会进行判断，自动生成将Block从栈上复制到堆上的代码，以下几种情况栈上的Block会自动复制到堆上：

- 调用Block的copy方法
- 将Block作为函数返回值时
- 将Block赋值给__strong修饰的变量或Block类型成员变量时
- 向Cocoa框架含有usingBlock的方法或者GCD的API传递Block参数时

因此ARC环境下多见的是MallocBlock，但StackBlock也是存在的：
不要进行任何copy、赋值等等操作，直接使用block

```objective-c
int main(int argc, const char * argv[]) {
    int val = 1;
    NSLog(@"Stack Block:%@", [^{NSLog(@"Stack Block:%d",val);} class]);
}
```

运行结果：

```
Stack Block:__NSStackBlock__
```

以上四种情况之外，都推荐使用block的copy实例方法把block复制到堆上。比如：
block为函数参数的时候，就需要我们手动的copy一份到堆上了。这里除去GCD API、系统框架中本身带usingBlock的方法，其他我们自定义的方法传递Block为参数的时候都需要手动copy一份到堆上。例4：

```objective-c
id getBlockArray()
{
    int val = 10;
    return [[NSArray alloc] initWithObjects:
            ^{NSLog(@"blk0:%d", val);},
            ^{NSLog(@"blk1:%d", val);}, nil];
}
int main(int argc, char * argv[]) {
    id obj = getBlockArray();
    void (^blk)(void) = [obj objectAtIndex:1];
    blk();
    return 0;
}
```

运行，这段程序崩溃。
在NSArray类的initWithObjects方法上传递block参数不属于上面系统自动复制的情况（不属于使用Cocoa框架含有usingBlock的方法传递block参数）。通过之前的分析，显而易见`^{NSLog(@"blk0:%d", val);}`是StackBlock，在getBlockArray函数执行结束时，栈上的block被废弃，因此在执行源代码的`[obj objectAtIndex:1]`时，就发生异常。

解决办法：手动复制

```objective-c
id getBlockArray()
{
    int val = 10;
    return [[NSArray alloc] initWithObjects:
            [^{NSLog(@"blk0:%d", val) ;} copy],
            [^{NSLog(@"blk1:%d", val);} copy], nil];
}

int main(int argc, char * argv[]) {
    id obj = getBlockArray();
    void (^blk)(void) = [obj objectAtIndex:1];
    blk();
    return 0;
}
```

最后。ARC会自动处理block的内存，不用手动release，但MRC下需要，否则会内存泄漏。

##3.3block的copy和release
###copy
block的复制可以使用，`Block_copy()`函数又或者copy实例方法。
`Block_copy()`的实现。在[Block.h](https://opensource.apple.com/source/clang/clang-137/src/projects/compiler-rt/BlocksRuntime/Block.h)文件中看到(在Xcode中也可以找到)：

```cpp
#define Block_copy(...) ((__typeof(__VA_ARGS__))_Block_copy((const void *)(__VA_ARGS__)))
```

`Block_copy()`的原型是`_Block_copy()`函数，而实际上最后调用的是[_Block_copy_internal()](http://llvm.org/svn/llvm-project/compiler-rt/trunk/lib/BlocksRuntime/runtime.c)函数：

```objective-c
//这里传入的参数实际上就是Block
void *_Block_copy(const void *arg) {
    return _Block_copy_internal(arg, WANTS_ONE);
}

static void *_Block_copy_internal(const void *arg, const int flags) {
    struct Block_layout *aBlock;

    //1.如果传递的参数为NULL，返回NULL。
    if (!arg) return NULL;
    
    //2.参数类型转换。转为指向Block_layout结构体的指针。Block_layout结构体请回顾文章开头，相当于clang转换后的__main_block_impl_0结构体，包括指向block的实现功能的指针和各种数据。
    aBlock = (struct Block_layout *)arg;

    //3.如果block的flags包含BLOCK_NEEDS_FREE，表明它是堆上的Block（为什么？见第7步注释）
    //增加引用计数，返回相同的block
    if (aBlock->flags & BLOCK_NEEDS_FREE) {
        // latches on high
        latching_incr_int(&aBlock->flags);
        return aBlock;
    }
    //这里删掉了与垃圾回收（GC）相关的代码，GC不做讨论

    //4.如果是全局block，什么也不做，返回相同的block
    else if (aBlock->flags & BLOCK_IS_GLOBAL) {
        return aBlock;
    }

    // Its a stack block.  Make a copy.
    if (!isGC) {
        //5.能够走到这里，表明是一个栈Block。需要复制到堆上。第一步申请内存
        struct Block_layout *result = malloc(aBlock->descriptor->size);
        if (!result) return (void *)0;
        //6.将栈数据复制到堆上
        memmove(result, aBlock, aBlock->descriptor->size); // bitcopy first
        //7.更新block的flags
        //第一句后面的注释说它不是必须的。
        result->flags &= ~(BLOCK_REFCOUNT_MASK);    // XXX not needed
        //设置flags为BLOCK_NEEDS_FREE，表明它是一个堆block。内存支持它一旦引用计数=0，
        //就进行释放。 “|1”是用来把block的引用计数设置为1。
        result->flags |= BLOCK_NEEDS_FREE | 1;
        //8.block的isa指针设置为_NSConcreteMallocBlock
        result->isa = _NSConcreteMallocBlock;
        //9.如果block有copy helper函数就调用它（和block所持有对象的内存管理有关，文章后面会讲到这部分）
        if (result->flags & BLOCK_HAS_COPY_DISPOSE) {
            //printf("calling block copy helper %p(%p, %p)...\n", aBlock->descriptor->copy, result, aBlock);
            (*aBlock->descriptor->copy)(result, aBlock); // do fixup
        }
        return result;
    }
    else {
        //GC相关
    }
}
```

对`_NSConcreteGlobalBlock`、`_NSConcreteStackBlock`、`_NSConcreteMallocBlock`这三种block，调用copy方法的总结：

![](http://upload-images.jianshu.io/upload_images/1727123-1d1214b806eb925a.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

不管block配置在哪里，调用copy方法进行复制不会产生任何问题。根据实际情况需要决定是否调用copy，如果在所有情况下都进行复制是不可取的做法，这样会浪费cpu资源。

###release
同样地，block的释放可以使用`Block_release()`函数或者release方法。

```cpp
#define Block_release(...) _Block_release((const void *)(__VA_ARGS__))
```

`Block_release()`原型是`_Block_release()`函数：

```objective-c
void _Block_release(void *arg) {
    //1.参数类型转换，转换为一个指向Block_layout结构体的指针。
    struct Block_layout *aBlock = (struct Block_layout *)arg;
    if (!aBlock) return;

    //2.取出flags中表示引用计数的部分，并且对它递减。
    int32_t newCount;
    newCount = latching_decr_int(&aBlock->flags) & BLOCK_REFCOUNT_MASK;
    //3.如果引用计数>0，表明仍然有对block的引用，block不需要释放
    if (newCount > 0) return;

    if (aBlock->flags & BLOCK_IS_GC) {
        //GC相关
    }
    //4.flags包含BLOCK_NEEDS_FREE（堆block），且引用计数=0
    else if (aBlock->flags & BLOCK_NEEDS_FREE) {
        //如果有copy helper函数就调用，释放block捕获的一些对象，对应_Block_copy_internal中的第9步
        if (aBlock->flags & BLOCK_HAS_COPY_DISPOSE)(*aBlock->descriptor->dispose)(aBlock);
        //释放block
        _Block_deallocator(aBlock);
    }
    //5.全局Block，什么也不做
    else if (aBlock->flags & BLOCK_IS_GLOBAL) {
        ;
    }
    //6.发生了一些奇怪的事情导致堆栈block视图被释放，打印日志警告开发者
    else {
        printf("Block_release called upon a stack Block: %p, ignored\n", (void *)aBlock);
    }
}
```

`_Block_copy_internal()`第9步和`_Block_release()`第4步中，block所持有对象的内存管理相关内容之后再详细说明。

#4.__block说明符
回顾在第二节中截获自动变量值的例子。block在实现时捕获自动变量的瞬时值，而且不允许在block内修改；因为超出栈作用域就会被释放的原因，也无法用指针传递的方式来实现在block内修改自动变量。

我们知道使用__block 修饰自动变量就可以在block内改变外部自动变量的值。那__block又是怎样实现这个目的的呢？以下分为基本数据类型、对象类型的指针变量来说明。
##4.1基本数据类型的变量
例5：

```objective-c
int main(int argc, const char * argv[]) {

    __block int c = 3;
    void (^blk)(void) = ^{
        c++;
        NSLog(@"1--- c = %d",c);
    };

    c++;
    NSLog(@"2--- c = %d",c);
    blk();
    NSLog(@"3--- c = %d",c);

    return 0;
}
```
运行结果：

```
2--- c = 4
1--- c = 5
3--- c = 5
```

clang：

```cpp
// __block为变量c创建的结构体，其中成员c为c的值，forwarding为指向自己的指针
struct __Block_byref_c_0 {
  void *__isa;
__Block_byref_c_0 *__forwarding;
 int __flags;
 int __size;
 int c;
};

// block结构体
struct __main_block_impl_0 {
  struct __block_impl impl;
  struct __main_block_desc_0* Desc;
  __Block_byref_c_0 *c; // by ref
  __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, __Block_byref_c_0 *_c, int flags=0) : c(_c->__forwarding) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};

// block的函数实现
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
  __Block_byref_c_0 *c = __cself->c; // bound by ref

        (c->__forwarding->c)++;
        NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_944c40_mi_0,(c->__forwarding->c));
    }

//捕获的变量的copy和release
static void __main_block_copy_0(struct __main_block_impl_0*dst, struct __main_block_impl_0*src) {_Block_object_assign((void*)&dst->c, (void*)src->c, 8/*BLOCK_FIELD_IS_BYREF*/);}

static void __main_block_dispose_0(struct __main_block_impl_0*src) {_Block_object_dispose((void*)src->c, 8/*BLOCK_FIELD_IS_BYREF*/);}

//block的描述结构体
static struct __main_block_desc_0 {
  size_t reserved;
  size_t Block_size;
  void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0*);
  void (*dispose)(struct __main_block_impl_0*);
} __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0), __main_block_copy_0, __main_block_dispose_0};

int main(int argc, const char * argv[]) {

    __attribute__((__blocks__(byref))) __Block_byref_c_0 c = {(void*)0,(__Block_byref_c_0 *)&c, 0, sizeof(__Block_byref_c_0), 3};
    void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, (__Block_byref_c_0 *)&c, 570425344));

    (c.__forwarding->c)++;
    NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_944c40_mi_1,(c.__forwarding->c));
    ((void (*)(__block_impl *))((__block_impl *)blk)->FuncPtr)((__block_impl *)blk);
    NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_944c40_mi_2,(c.__forwarding->c));

    return 0;
}
```

注意到，加了`__block`修饰的int c变量变成了：`__Block_byref_c_0`结构体类型的变量

```
__attribute__((__blocks__(byref))) __Block_byref_c_0 c = {(void*)0,(__Block_byref_c_0 *)&c, 0, sizeof(__Block_byref_c_0), 3};
```

`__main_block_impl_0`结构体中c变量不再是int类型了，而是变成了一个指向`__Block_byref_c_0`结构体的**指针**。`__Block_byref_c_0`结构如下：

```cpp
struct __Block_byref_c_0 {
	void *__isa;
	__Block_byref_c_0 *__forwarding;
	int __flags;
	int __size;
	int c;
};
```

`__Block_byref_c_0`结构体的成员变量`__forwarding`初始化为指向自身的指针。而原本自动变量的值3，也成为了结构体中的成员变量。如下`__block int c = 3;`变成`__Block_byref_c_0`类型的变量：

```cpp
__Block_byref_c_0 c = {
  (void*)0,
  (__Block_byref_c_0 *)&c, //指向自己
  0, 
  sizeof(__Block_byref_c_0), 
  3//c的值
};
```

**自动变量c加了`__block`，在clang编译后变成了一个结构体`__Block_byref_c_0`**。正是如此，这个值才能被多个block共享、并且不受栈帧生命周期的限制。（把__block 变量当成是对象）

看到block的结构体初始化，__Block_byref_c_0类型的变量c**以指针形式进行传递**：

```c
void (*blk)(void) = ((void (*)())&__main_block_impl_0(
(void *)__main_block_func_0,
 &__main_block_desc_0_DATA,
 (__Block_byref_c_0 *)&c,
 570425344)
);
```

**block 捕获`__block`变量，捕获的是对应结构体的变量的地址。**

再看一下block执行部分的代码：

```c
__Block_byref_c_0 *c = __cself->c; // bound by ref
(c->__forwarding->c)++;
```

`__Block_byref_c_0 *c = __cself->c;`取到指向`__Block_byref_c_0`结构体类型的变量c的指针。

`(c->__forwarding->c)++;`然后通过`__forwarding`访问到成员变量c，也就是原先的自动变量。

![](http://upload-images.jianshu.io/upload_images/1727123-0a45a2b59908f555.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

那么现在问题来了：

1. block作为回调执行时，局部变量已经出栈了，为什么这时代码还能正常工作？
2. __forwarding初始化为指向自身的指针，为什么要通过它来取得我们要修改的变量而不是`c->c`直接取出呢？


##__block变量的内存管理 - copy和release
```c
//dst：目标地址 src：源地址
static void __main_block_copy_0(struct __main_block_impl_0*dst, struct __main_block_impl_0*src) {_Block_object_assign((void*)&dst->c, (void*)src->c, 8/*BLOCK_FIELD_IS_BYREF*/);}

static void __main_block_dispose_0(struct __main_block_impl_0*src) {_Block_object_dispose((void*)src->c, 8/*BLOCK_FIELD_IS_BYREF*/);}
```

在上面clang转换的代码中看到这样两个函数，简单来说他们就是用来做`__block`的复制和释放的，其后中调用到的`_Block_object_assign()`函数和`_Block_object_dispose()`函数源码可以在[runtime.c](http://llvm.org/svn/llvm-project/compiler-rt/trunk/lib/BlocksRuntime/runtime.c)看到。`BLOCK_FIELD_IS_BYREF`是block截获`__block`变量的特殊标志。

另外我们也留意到`__main_block_desc_0`结构体中多了两个成员变量：

```c
void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0*);
void (*dispose)(struct __main_block_impl_0*);
```
上面两个函数以指针形式被赋值到`__main_block_desc_0`结构体成员变量copy和dispose中。

虽然这两个函数没有看到明显的调用，但在block从栈复制到堆上时以及堆上的Block被废弃时会调用到这些函数去处理`__block`变量（从第3.3节，block的copy函数源码第9步和release函数第4步可知）。

![](http://upload-images.jianshu.io/upload_images/1727123-71de94955428882c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

![](http://upload-images.jianshu.io/upload_images/1727123-b6782b3d2696708b.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

以`_Block_object_assign()`函数为例，从上面的源码截图中可以得知，实际上它最后调用的是`_Block_byref_assign_copy()`函数。总结一下上面截图函数所做的事情：

栈block通过copy复制到了了堆上。此时，block使用到的`__block`变量也会被复制到堆上并被block**持有**。如果block已经在堆上，再复制block也不会对所使用的`__block`有影响。

![](http://upload-images.jianshu.io/upload_images/1727123-23093e5dab52b4d3.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

如果是多个block使用了同一个`__block`变量，那么，有多少个block被复制到堆上，堆上的`__block`变量就被多少个block持有。当`__block`变量没有被任何block持有时（block被废弃了），它就会被释放。（`__block`的思考方式和oc的引用计数式内存管理是相似的，而且`__block`对应的结构体里也有`__isa`指针，所以在我看来也可以把`__block`变量当成对象来思考）

栈上`__block`变量被复制到堆上后，会将成员变量`__forwarding`指针从指向自己换成指向堆上的`__block`，而堆上`__block`的`__forwarding`才是指向自己。

![](http://upload-images.jianshu.io/upload_images/1727123-0916a08caf9f7d62.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

这样，不管`__block`变量是在栈上还是在堆上，都可以通过`__forwarding`来访问到变量值。

因此例5代码中，block内的`^{c++;};`和block外的`c++;`在clang中转换为如下形式：`(c->__forwarding->c)++;`。
到此，两个问题都回答了。

**总结：**

1. block捕获`__block`变量，捕获的是对应结构体的变量的地址。
2. 可以把`__block`当做对象来看待。当block复制到堆上，block使用到的`__block`变量也会被复制到堆上并被block持有。

至于release的过程，就相当于copy的逆过程，很好理解就不多说了。


###block持有对象
另外，回顾第二节中的例2，block中使用到（默认）附有__strong修饰符的NSMutableString类对象的自动变量`NSMutableString *str = [[NSMutableString alloc]initWithString:@"hello"];`。转换源码之后，同样地多了`__main_block_copy_0 `和`__main_block_dispose_0 `函数。

> 因为在C语言的结构体中，编译器没法很好的进行初始化和销毁操作。这样对内存管理来说是很不方便的。所以就在 `__main_block_desc_0`结构体中间增加成员变量 `void (\*copy)(struct __main_block_impl_0\*, struct __main_block_impl_0\*)`和`void (\*dispose)(struct __main_block_impl_0\*)`，利用OC的Runtime进行内存管理。

与`__block`相似，**对象类型的指针变量被block截获值（地址），而block被复制到堆上后持有这个对象**，因此，它可以超出作用域而存在。当堆上block被废弃时，释放block持有的对象（不是持有变量）。指针指向的对象并不会随block的复制而复制到堆上。

![](http://upload-images.jianshu.io/upload_images/1727123-df2541419ae2ff8c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

`_Block_object_assign`函数的调用相当于把对象retain了，因此block持有对象。

##4.2对象类型的指针变量
```objective-c
__block NSObject *obj = [[NSObject alloc]init];
    NSLog(@"----%@,%p",obj,&obj);
    void (^blk)(void) = ^{
        NSLog(@"----%@,%p",obj,&obj);
    };
    blk();
```

clang:

```c
//与__block普通类型变量相比，这个结构体体多了两个成员变量
struct __Block_byref_obj_0 {
  void *__isa;
__Block_byref_obj_0 *__forwarding;
 int __flags;
 int __size;
 void (*__Block_byref_id_object_copy)(void*, void*);//多出来的
 void (*__Block_byref_id_object_dispose)(void*);//多出来的
 NSObject *obj;
};
//这也多出来的，对应上面的copy函数指针
static void __Block_byref_id_object_copy_131(void *dst, void *src) {
 _Block_object_assign((char*)dst + 40, *(void * *) ((char*)src + 40), 131);
}
//多出来，对饮跟上面的dispose函数指针
static void __Block_byref_id_object_dispose_131(void *src) {
 _Block_object_dispose(*(void * *) ((char*)src + 40), 131);
}
//余下的部分基本和__block普通类型变量差不多
struct __main_block_impl_0 {
  struct __block_impl impl;
  struct __main_block_desc_0* Desc;
  __Block_byref_obj_0 *obj; // by ref
  __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, __Block_byref_obj_0 *_obj, int flags=0) : obj(_obj->__forwarding) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};

static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
  __Block_byref_obj_0 *obj = __cself->obj; // bound by ref

        NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_a45e66_mi_1,(obj->__forwarding->obj),&(obj->__forwarding->obj));
    }
static void __main_block_copy_0(struct __main_block_impl_0*dst, struct __main_block_impl_0*src) {_Block_object_assign((void*)&dst->obj, (void*)src->obj, 8/*BLOCK_FIELD_IS_BYREF*/);}

static void __main_block_dispose_0(struct __main_block_impl_0*src) {_Block_object_dispose((void*)src->obj, 8/*BLOCK_FIELD_IS_BYREF*/);}

static struct __main_block_desc_0 {
  size_t reserved;
  size_t Block_size;
  void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0*);
  void (*dispose)(struct __main_block_impl_0*);
} __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0), __main_block_copy_0, __main_block_dispose_0};
int main(int argc, const char * argv[]) {
    __attribute__((__blocks__(byref))) __Block_byref_obj_0 obj = {(void*)0,(__Block_byref_obj_0 *)&obj, 33554432, sizeof(__Block_byref_obj_0), __Block_byref_id_object_copy_131, __Block_byref_id_object_dispose_131, ((NSObject *(*)(id, SEL))(void *)objc_msgSend)((id)((NSObject *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("NSObject"), sel_registerName("alloc")), sel_registerName("init"))};
    NSLog((NSString *)&__NSConstantStringImpl__var_folders_7__3g67htjj4816xmx7ltbp2ntc0000gn_T_main_a45e66_mi_0,(obj.__forwarding->obj),&(obj.__forwarding->obj));
    void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, (__Block_byref_obj_0 *)&obj, 570425344));
    ((void (*)(__block_impl *))((__block_impl *)blk)->FuncPtr)((__block_impl *)blk);

    return 0;
}
```
```
__block NSObject *obj = [[NSObject alloc]init];
相当于
__block __strong NSObject *obj = [[NSObject alloc]init];
```

可以看到，和4.1节一样，block 捕获`__block`变量，捕获的是对应结构体的变量的地址。并且当block从栈复制到堆上，`__block`变量从栈复制到堆，且堆`__block`变量持有赋值给它的对象。当`__block`变量被废弃时，释放赋值给`__block`变量的对象。

```
持有关系：堆Block -> 堆__block变量 -> 对象
只要堆上的__block变量存在，对象就继续处于被持有的状态。
```

###总结一下以上4个章节：
- **捕获**和**持有**是两个概念，不要混淆。（**持有**是MRC下的说法，而在ARC下的内存管理我们谈的是“强弱指针引用”。）
- block相当于是对象。
- 能够被block捕获的变量：自动变量、静态变量、`__block`变量。block捕获：自动变量的值（基本数据类型-值，对象类型指针-对象地址）；静态变量的地址；`__block`变量则是其对应结构体变量的指针：地址。
- 自动变量是值传递，所以不能在block内改变值。
- __block变量和静态变量是地址传递，可以在block内直接改变值。
- 全局变量、静态全局变量，因为作用域范围广，所以可以在block内改变它们的值
- 为了解决block所在变量域结束后block仍然可用的问题，需要把栈block复制到堆上
- ARC时，在四种情况下stackBlock会自动复制到堆上，其余时候必须手动copy才会复制到堆上；而MRC则不会，只有手动copy才会复制到堆上
- `__block`变量也可以当成是对象看待。block复制到堆上时，它使用到的`__block`变量也会复制到堆上，无论MRC还是ARC。
- block复制到堆上引起的持有对象的关系：

 ```
对象类型变量：堆Block -> 对象
__block 普通基本数据类型变量：堆Block -> 堆__block变量
__block __strong 对象类型变量： 堆Block -> 堆__block变量 -> 对象
对象本身就在堆区，不存在复制不复制的说法，只是它被“持有”的数量有所增加
```
- 在ARC下，`__block`会导致对象被retain。而在MRC下不会。

#5.循环引用
循环引用是什么其实很多人应该都知道，这里简单提一下。比如说：
1.多个对象之间相互引用形成环。A对象强引用B，B强引用A，于是两者内存一直无法释放。
2.对象自己引用自己。

例6：多个对象之间相互引用形成环。

```objective-c
#import <Foundation/Foundation.h>
typedef void (^PersonBlock)(void);
@interface Person : NSObject
@property (nonatomic ,assign) NSInteger age;
@property (nonatomic ,strong) NSString *name;
- (void)configurePersonBlock:(PersonBlock)blk_t;
@end

#import "Person.h"
@interface Person()
//不作为公有属性，而是在对外方法接口中把Block传进来
@property (nonatomic ,strong) PersonBlock blk;
@end

@implementation Person
- (void)configurePersonBlock:(PersonBlock)blk_t{
    self.blk = blk_t;
}

- (void)actionComplete{
    self.blk();
}
@end
```

```
#import "ViewController.h"
#import "BViewController.h"

@interface ViewController ()
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    UIButton *btn = [[UIButton alloc]initWithFrame:CGRectMake(50, 50, 50, 50)];
    btn.backgroundColor = [UIColor redColor];
    [self.view addSubview:btn];
    [btn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)click:(id)sender {
    BViewController *bVC = [[BViewController alloc]init];
    [self.navigationController pushViewController:bVC animated:YES];
}
@end
--------------------------------------------------------------------
#import "BViewController.h"
#import "Person.h"
@interface BViewController ()
@property (nonatomic ,strong) Person *person;
@property (nonatomic ,copy) NSString *str;
@end

@implementation BViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.str = @"haha";
    
    self.person = [[Person alloc]init];
    self.person.name = @"commet";
    self.person.age = 18;
    [self.person configurePersonBlock:^{
        NSLog(@"printf str:%@",self.str);
    }];
    [self.person actionComplete];
}
@end
```

![1.多个对象之间相互引用形成环。](http://upload-images.jianshu.io/upload_images/1727123-f1b08c20d1e6843d.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

成环：B控制器通过strong实例变量持有person对象，person持有block，block又持有self（即B控制器）。

block用到的外部的对象，mallocBlock会在内部持有它。

Block捕获了实例变量_var，那么也会自动把self变量一起捕获了，因为实例变量是与self所指代的实例相关联在一起的。但是像例6这样写：

```objective-c
[self.person configurePersonBlock:^{
    NSLog(@"%ld",_var);
}];
```

由于没有明确使用self变量，所以很容易就会忘记self也被捕获了。而直接访问实例变量和通过self来访问是等效的，所以通常属性来访问实例变量，这样就明确地使用了self了。
self也是对象，所以block捕获它的时候也会持有该对象。

例7：自己引用自己

```objective-c
#import "ViewController.h"
#import "Person.h"

@interface ViewController ()
@property (nonatomic ,strong) Person *person;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    Person *person1 = [[Person alloc]init];
    person1.name = @"commet";
    person1.age = 18;
    [person1 configurePersonBlock:^{
        NSLog(@"%@",person1.name);
    }];
}
@end
```

![2.自己引用自己](http://upload-images.jianshu.io/upload_images/1727123-8e3a01c27bcc5b9c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

##5.1解除循环引用
以例6为例分析：

![](http://upload-images.jianshu.io/upload_images/1727123-78720f9ed3ac385d.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

例6的引用环是这样的，只要打破其中一道引用，就能解除循环引用。

- 解除①引用

可以这么修改：

```objective-c
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.str = @"haha";
    
    self.person = [[Person alloc]init];
    self.person.name = @"commet";
    self.person.age = 18;
    [self.person configurePersonBlock:^{
        NSLog(@"printf str:%@",self.str);
        self.person = nil;//改了这里
    }];
    [self.person actionComplete];
}
```

![B控制器push没有发生内存泄漏](http://upload-images.jianshu.io/upload_images/1727123-ca4f3cfda083610e.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

ps:必须执行block才能解除①的引用。

- 解除②引用

在Person类中:

```objective-c
@implementation Person

- (void)configurePersonBlock:(PersonBlock)blk_t{
    self.blk = blk_t;
}

- (void)actionComplete{
    self.blk();
    self.blk = nil;//改了这句
}
```

然后在控制器中调用它：

```objective-c
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.str = @"haha";
    
    self.person = [[Person alloc]init];
    self.person.name = @"commet";
    self.person.age = 18;
    [self.person configurePersonBlock:^{
        NSLog(@"printf str:%@",self.str);
    }];
    [self.person actionComplete];
}
```

![B控制器push还是没有发生内存泄漏](http://upload-images.jianshu.io/upload_images/1727123-2c957ea046bb0571.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

但是前面这两种做法又并不是那么合理，因为他们都强迫调用actionComplete这个方法来解除其中一层引用，但有时候你无法假定调用者一定会这么做。

- 解除③引用

block要使用的外部变量，作为block形参传递进block。

```objective-c
Person类
#import <Foundation/Foundation.h>
typedef void (^PersonBlock)(NSString *);

@interface Person : NSObject
@property (nonatomic ,assign) NSInteger age;
@property (nonatomic ,strong) NSString *name;

- (void)configurePersonBlock:(PersonBlock)blk_t;

- (void)actionComplete:(NSString *)str;
@end

#import "Person.h"
@interface Person()
@property (nonatomic ,strong) PersonBlock blk;
@end

@implementation Person

- (void)configurePersonBlock:(PersonBlock)blk_t{
    self.blk = blk_t;
}

- (void)actionComplete:(NSString *)str{
    self.blk(str);
}
@end
----------------------------------------------------------------

#import "BViewController.h"
#import "Person.h"
@interface BViewController ()
@property (nonatomic ,strong) Person *person;
@property (nonatomic ,copy) NSString *str;
@end

@implementation BViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.str = @"haha";
    
    self.person = [[Person alloc]init];
    self.person.name = @"commet";
    self.person.age = 18;
    [self.person configurePersonBlock:^(NSString *str) {
        NSLog(@"printf str:%@",str);
    }];
    [self.person actionComplete:self.str];

}
@end
```

![B控制器push依旧没有发生内存泄漏](http://upload-images.jianshu.io/upload_images/1727123-e4c928405cd4a3e9.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

这种方法存在一个缺点，就是如果在block中要使用到很多外部变量、对象，那么就要给Block添加很多参数。

往往我们使用__weak来打破这种强引用。

```objective-c
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.str = @"haha";
    
    self.person = [[Person alloc]init];
    self.person.name = @"commet";
    self.person.age = 18;
    
    __weak typeof(self) weakself = self;
    [self.person configurePersonBlock:^ {
        NSLog(@"printf str:%@",weakself.str);
    }];
    [self.person actionComplete];

}
```

但也不是说在block中就一定要使用weakself，因为有时候循环引用未必存在：
比如说Masonry，一般我们是这样写的：

```objective-c
[_view mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(60, 60));
        make.right.equalTo(self.view.mas_right).offset(-24);
        make.bottom.equalTo(self.view.mas_bottom).offset(-50);
    }];
```

显然block引用了self，但这样写并没有引起循环引用，查看Masonry源码：

```objective-c
- (NSArray *)mas_makeConstraints:(void(^)(MASConstraintMaker *))block {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    MASConstraintMaker *constraintMaker = [[MASConstraintMaker alloc] initWithView:self];
    block(constraintMaker);
    return [constraintMaker install];
}
```
在`mas_makeConstraints`这个方法中，可以看到self并没有强引用block，而这个block只是作为参数传递进来并直接调用而已。

说完weakself那么不得不提起strongself了。Apple 官方文档有讲到，如果在 Block 执行完成之前，self 被释放了，weakSelf 也会变为 nil。比如：

```objective-c
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
        
    Person *person = [[Person alloc]init];
    person.name = @"commet";
    person.age = 18;
    
    __weak typeof(person) weakPerson = person;
    [person configurePersonBlock:^ {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"printf str:%@",weakPerson.name);
        });
    }];
    [person actionComplete];
}
```

运行结果：

```
printf str:(null)
```

`[person actionComplete];`调用block之后，viewDidLoad方法作用域结束后，person对象被释放。由于`dispatch_after`的延迟执行，在Block执行完成前，捕获的对象释放了，block捕获weakPerson变为nil。

由于weakself无法控制对象释放时机所带来的问题，我们在Block中使用`__strong`修饰weakself保证任何情况下self在超出作用域后仍能够使用，防止self的提前释放。

```objective-c
__weak typeof(person) weakPerson = person;
    [person configurePersonBlock:^ {
        __strong typeof(weakPerson) strongPerson = weakPerson;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"printf str:%@",strongPerson.name);
        });
    }];
    [person actionComplete];
```

当block执行完毕就会释放自动变量strongSelf，释放对self的强引用。
所以总结来说，weakself是用来解决block循环引用的问题的，而strongself是用来解决在block执行过程中self提前释放的问题。


最后还有一种解除循环引用的方法：使用__block变量。
修改一下例7：

```objective-c
- (void)viewDidLoad {
    [super viewDidLoad];

    Person *person1 = [[Person alloc]init];
    person1.name = @"commet";
    person1.age = 18;
    
    __block Person *blkPerson = person1;
    
    [person1 configurePersonBlock:^{
        NSLog(@"%@",blkPerson.name);
        blkPerson = nil;
    }];
    person1.blk();
}
```

![](http://upload-images.jianshu.io/upload_images/1727123-be9bd6844172ff83.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

这段代码没有引起循环引用，但是如果没有执行赋值给成员变量的blk的block（即删掉`person1.blk();`这句），就会造成循环引用引起内存泄漏。person持有block，block持有`__block`变量，`__block`变量又持有person对象，于是就形成了保留环...

![](http://upload-images.jianshu.io/upload_images/1727123-dc913b4bca434d7a.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

虽然使用`__block`可以控制对象的持有时间，在执行block时可以动态地决定是否将nil或者其他对象赋值在`__block`变量中，但它有一个缺点就是，必须执行一次block才能打破循环引用。

ps:在ARC下`__block`会导致对象被retain，有可能导致循环引用。而在MRC下，则不会retain这个对象，也不会导致循环引用。




参考文档：
[Block_private.h ](https://opensource.apple.com/source/libclosure/libclosure-63/Block_private.h.auto.html)
[runtime.c](http://llvm.org/svn/llvm-project/compiler-rt/trunk/lib/BlocksRuntime/runtime.c)
文章：
[A look inside blocks: Episode 3 (Block_copy)](http://www.galloway.me.uk/2013/05/a-look-inside-blocks-episode-3-block-copy/)
[objc 中的 block](https://blog.ibireme.com/2013/11/27/objc-block/)
[谈Objective-C block的实现](http://blog.devtang.com/2013/07/28/a-look-inside-blocks/)
[Block 小测验](https://www.zybuluo.com/MicroCai/note/49713)
[深入研究Block用weakSelf、strongSelf、@weakify、@strongify解决循环引用](http://www.jianshu.com/p/701da54bd78c)