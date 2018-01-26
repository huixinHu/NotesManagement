本文基于objc4-709源码进行分析。关于源码编译：[objc - 编译Runtime源码objc4-706](http://blog.csdn.net/WOTors/article/details/54426316?locationNum=7&fps=1)

# 类和对象

## 1.类和对象的结构概要

NSObject是所有类的基类，NSObject在源码中的定义：

在NSObject.mm文件中找到

```objc
@interface NSObject <NSObject> {
    Class isa  OBJC_ISA_AVAILABILITY;
}
```
NSObject类的第一个成员变量就是Class类型的isa。

Object.mm文件：

```cpp
typedef struct objc_class *Class; //类
typedef struct objc_object *id;	

@interface Object { 
    Class isa; 
} 
```
Class就是c语言定义的objc_class结构体类型的指针，objc中的类实际上就是objc_class。

而id类型就是objc_object结构体类型的指针（就是我们平时经常用到的id类型），我们平时用的id可以用来声明一个对象，说明objc中的对象实际上就是objc_object。

objc-runtime-new.h

```cpp
struct objc_class : objc_object {
    // Class ISA;
    Class superclass;           //父类的指针
    cache_t cache;             // formerly cache pointer and vtable 方法缓存
    class_data_bits_t bits;    // class
    ...
}
```

objc_class继承于objc_object，objc中的类也是一个对象。

objc-private.h

```cpp
struct objc_object {
private:
    isa_t isa;//objc_object唯一成员变量
public:
	Class ISA();
    Class getIsa();
    void initIsa(Class cls /*nonpointer=false*/);
    
    ...
private:
    void initIsa(Class newCls, bool nonpointer, bool hasCxxDtor);
}
```

```cpp
union isa_t 
{
    isa_t() { }
    isa_t(uintptr_t value) : bits(value) { }

    Class cls;
    uintptr_t bits;
    
    ...
}
```
objc_object是objc中对象的定义。isa 是 objc_object的唯一成员变量。我们经常说，所有的objc对象都包含一个isa指针，从源码上来看，现在准确说应该是isa_t结构体（isa指针应该是isa_t联合体中的`Class cls`指针）。当objc为一个对象分配内存，初始化实例变量后，在这些**对象**的实例变量的结构体中的第一个就是isa。

为了方便阅读，我把objc_class写成：

```cpp
struct objc_class : objc_object {
    isa_t isa;
    Class superclass;           //父类的指针
    cache_t cache;             // formerly cache pointer and vtable 方法缓存
    class_data_bits_t bits;    // class
    ...
}
```

在objc中，**对象**的方法的实现不会存储在每个对象的结构体中，而是在相应的类里（如果每一个对象都要维护一个实例方法列表，那么开销太大了）。当一个**实例方法**被调用时，会通过对象的isa，在对应的类中找到方法的实现（具体是在class_data_bits_t结构体中查找，里面有一个方法列表）。
![](/Users/huhuixin/Desktop/Snip20180125_2.png)

同时我们还从源码中看到，objc_class结构体中还有一个Class类型的superclass成员变量，指向了父类。通过这个指针可以查找从父类继承的方法。

然而，对于类对象来说，它的isa又是什么呢？objective-c里面有一种叫做meta class元类的东西。
![对象、类、元类关系图](/Users/huhuixin/Desktop/objc-isa-class-diagram.png)

为了让我们能够调用类方法，类的isa“指针”必须指向一个类结构，并且该类结构必须包含我们可以调用的类方法列表。这就导致了元类的定义：元类是类对象的类。

类方法调用时，通过类的isa“指针”在元类中获取方法的实现。元类中存储了一个类的所有类方法。

从上图中总结以下几个信息：
- root class(class)就是NSObject，由于它是基类，所以它没有父类。
- 实例对象的isa指向其类，类的isa指向其元类。每个元类的isa都指向根元类root class(meta)，根元类的isa指向自己。
- 根元类的父类指针指向基类（NSObject）。

[What is a meta-class in Objective-C?](http://www.cocoawithlove.com/2010/01/what-is-meta-class-in-objective-c.html)

## 2.isa_t结构体的分析
通过源码，我们可以知道isa_t实际上是一个union联合体。其中的方法、成员变量、结构体公用一块空间。取决于其中的结构体，最终isa_t共占64位内存空间

```cpp
union isa_t 
{
    isa_t() { }
    isa_t(uintptr_t value) : bits(value) { }

    Class cls;//指针
    uintptr_t bits;

#if SUPPORT_PACKED_ISA

//-------------------arm64上的实现
# if __arm64__
#   define ISA_MASK        0x0000000ffffffff8ULL//ISA_MAGIC_MASK 和 ISA_MASK 分别是通过掩码的方式获取MAGIC值 和 isa类指针
#   define ISA_MAGIC_MASK  0x000003f000000001ULL
#   define ISA_MAGIC_VALUE 0x000001a000000001ULL
    struct {
        uintptr_t nonpointer        : 1;    //0：普通isa指针，1：优化的指针用于存储引用计数
        uintptr_t has_assoc         : 1;    //表示该对象是否包含associated object，如果没有，析构时会更快
        uintptr_t has_cxx_dtor      : 1;    //表示对象是否含有c++或者ARC的析构函数，如果没有，析构更快
        uintptr_t shiftcls          : 33;   // MACH_VM_MAX_ADDRESS 0x1000000000 类的指针
        uintptr_t magic             : 6;    //用于在调试时分辨对象是否未完成初始化（用于调试器判断当前对象是真的对象还是没有初始化的空间）
        uintptr_t weakly_referenced : 1;    //对象是否有过weak对象
        uintptr_t deallocating      : 1;    //是否正在析构
        uintptr_t has_sidetable_rc  : 1;    //该对象的引用计数值是否过大无法存储在isa指针
        uintptr_t extra_rc          : 19;   //存储引用计数值减一后的结果。对象的引用计数超过 1，会存在这个这个里面，如果引用计数为 10，extra_rc的值就为 9。
#       define RC_ONE   (1ULL<<45)
#       define RC_HALF  (1ULL<<18)
    };

//-------------------__x86_64__上的实现
# elif __x86_64__
#   define ISA_MASK        0x00007ffffffffff8ULL
#   define ISA_MAGIC_MASK  0x001f800000000001ULL
#   define ISA_MAGIC_VALUE 0x001d800000000001ULL
    struct {
        uintptr_t nonpointer        : 1;
        uintptr_t has_assoc         : 1;
        uintptr_t has_cxx_dtor      : 1;
        uintptr_t shiftcls          : 44; // MACH_VM_MAX_ADDRESS 0x7fffffe00000
        uintptr_t magic             : 6;  //值为0x3b
        uintptr_t weakly_referenced : 1;
        uintptr_t deallocating      : 1;
        uintptr_t has_sidetable_rc  : 1;
        uintptr_t extra_rc          : 8;
#       define RC_ONE   (1ULL<<56)
#       define RC_HALF  (1ULL<<7)
    };

# else
#   error unknown architecture for packed isa
# endif

#endif

...略
```

由于源码要在mac os下才能编译，因此接下来都基于__x86_64__分析，arm64其实大同小异。

源码中遇到的编译宏的说明：

`SUPPORT_PACKED_ISA`：表示平台是否支持在 isa 指针中插入除 Class 之外的信息。如果支持就会将 Class 信息放入 isa_t 定义的 struct 内（shiftcls），并附上一些其他信息，比如引用计数，析构状态；如果不支持，那么不会使用 isa_t 内定义的 struct，这时 isa_t 只使用 cls成员变量(Class 指针，经常说的“isa指针”就是这个)。在 iOS 以及 MacOSX 上，SUPPORT_PACKED_ISA 定义为 1（支持）。

struct结构体的成员含义：

```
参数					   含义
nonpointer		0 表示普通的 isa 指针，1 表示使用优化，存储引用计数
has_assoc		表示该对象是否包含 associated object 关联对象，如果没有，则析构时会更快
has_cxx_dtor		表示该对象是否有 C++ 或 ARC 的析构函数，如果没有，则析构时更快
shiftcls		类的指针
magic			__x86_64__环境初始化值为 0x3b，用于在调试时分辨对象是否未完成初始化。
weakly_referenced	表示该对象是否有过 weak 对象，如果没有，则析构时更快
deallocating		表示该对象是否正在析构
has_sidetable_rc	表示该对象的引用计数值是否过大无法存储在 isa 指针
extra_rc		存储引用计数值减一后的结果。19位将保存对象的引用计数，这样对引用计数的操作只需要原子的修改这个指针即可，如果引用计数超出19位，才会将引用计数保存到外部表，而这种情况往往是很少的，因此效率将会大大提高。
```
在初始化一节会对其中一些参数继续谈谈。

### 初始化
在我们调用alloc来实例化对象时，会调用到```objc_object::initInstanceIsa(Class cls, bool hasCxxDtor)``` 方法。方法的具体实现：

```cpp
inline void 
objc_object::initInstanceIsa(Class cls, bool hasCxxDtor)
{
    initIsa(cls, true, hasCxxDtor);
}

inline void 
objc_object::initIsa(Class cls, bool nonpointer, bool hasCxxDtor) 
{     
    if (!nonpointer) {
        isa.cls = cls;
    } else {
        isa_t newisa(0);

#if SUPPORT_INDEXED_ISA
        newisa.bits = ISA_INDEX_MAGIC_VALUE;
        newisa.has_cxx_dtor = hasCxxDtor;
        newisa.indexcls = (uintptr_t)cls->classArrayIndex();
#else
//__x86_64__和arm64会进入这个条件分支
        newisa.bits = ISA_MAGIC_VALUE;
        newisa.has_cxx_dtor = hasCxxDtor;
        newisa.shiftcls = (uintptr_t)cls >> 3;
#endif
        isa = newisa;
    }
}
```

`initInstanceIsa`方法实际上调用了`initIsa`方法，并且传入`nonpointer=true`参数。

由于isa_t是一个联合体，所以`newisa.bits = ISA_MAGIC_VALUE;`把isa_t中的struct结构体初始化为：
![](/Users/huhuixin/Desktop/objc-isa-isat-bits.png)
实际上只设置了nonpointer和magic的值。

#### nonpointer
nonpointer 表示是否对isa开启指针优化。

先介绍一种称为Tagged Pointer的技术，这是苹果为64位设备提出的节省内存和提高执行效率的一种优化方案。

> 假设我们要存储一个NSNumber对象，其值是一个整数。正常情况下，如果这个整数只是一个NSInteger的普通变量，那么它所占用的内存是与CPU的位数有关，在32位CPU下占4个字节，在64位CPU下是占8个字节的。而指针类型的大小通常也是与CPU位数相关，一个指针所占用的内存在32位CPU下为4个字节，在64位CPU下也是8个字节。
> 
> 如果没有Tagged Pointer对象，从32位机器迁移到64位机器中后，虽然逻辑没有任何变化，但这种NSNumber、NSDate一类的对象所占用的内存会翻倍。
> 
> 为了改进上面提到的内存占用和效率问题，苹果提出了Tagged Pointer对象。由于NSNumber、NSDate一类的变量本身的值需要占用的内存大小常常不需要8个字节，拿整数来说，4个字节所能表示的有符号整数就可以达到20多亿。所以我们可以将一个对象的指针拆成两部分，一部分直接保存数据，另一部分作为特殊标记，表示这是一个特别的指针，不指向任何一个地址。

技术详细可以查看以下两个链接。

[深入理解Tagged Pointer](http://www.infoq.com/cn/articles/deep-understanding-of-tagged-pointer/)

[64位与Tagged Pointer](http://blog.xcodev.com/posts/tagged-pointer-and-64-bit/)

虽然Tagged Pointer专门用来存储小的对象，例如NSNumber和NSDate。但在isa指针优化上用到了tagged Pointer的概念。

使用整个指针大小的内存来存储isa有些浪费，在arm64上运行的iOS只用了33位（和结构体中shiftcls的33无关，Mac OS用了47位），剩下的31位用于其他目的。

nonpointer = 0 ，raw isa，表示isa_t不使用struct结构体，访问对象的 isa 会直接返回 cls 指针，cls 会指向对象所属的类的结构。这是在 iPhone 迁移到 64 位系统之前时 isa 的类型。

nonpointer = 1，isa_t使用了struct结构体，此时 isa 不再是指针，不能直接访问 objc_object 的 isa 成员变量，但是其中也有 cls 的信息，只是其中关于类的指针都是保存在 shiftcls 中。

#### magic
用于判断当前对象是否已经完成初始化。

#### has_cxx_dtor
接着设置has_cxx_dtor，这一位表示当前对象是否有 C++ 或者 ObjC 的析构器，如果没有析构器就会快速释放内存。

#### shiftcls
`newisa.shiftcls = (uintptr_t)cls >> 3;` 将对象对应的类的指针存入结构体的shiftcls成员中。

将cls（地址）右移三位的原因：字节对齐。

[为什么需要字节对齐](http://blog.csdn.net/qq_25077833/article/details/53454958)

[C语言字节对齐问题详解](https://www.cnblogs.com/clover-toeic/p/3853132.html)
> 对象的内存地址必须对齐到字节的倍数，这样可以提高代码运行的性能，在 iPhone5s 中虚拟地址为 33 位，所以用于对齐的最后三位比特为 000，我们只会用其中的 30 位来表示对象的地址。
> 
> 将cls右移三位，可以将地址中无用的后三位清除减小内存的消耗。

### ISA()
由于开启了指针优化后，isa不再是指针，要获取类指针就要用到 ISA() 方法。

```cpp
#define ISA_MASK 0x00007ffffffffff8ULL

inline Class 
objc_object::ISA() 
{
#if SUPPORT_INDEXED_ISA
    if (isa.nonpointer) {
        uintptr_t slot = isa.indexcls;
        return classForIndex((unsigned)slot);
    }
    return (Class)isa.bits;
#else
    return (Class)(isa.bits & ISA_MASK); //按位与运算获取类指针，__x86_64__是44位
#endif
}
```
