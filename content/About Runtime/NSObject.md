[objc - 编译Runtime源码objc4-706](http://blog.csdn.net/WOTors/article/details/54426316?locationNum=7&fps=1)

# NSObject基类

NSObject源码中的定义：

在NSObject.mm文件中找到

```objc
@interface NSObject <NSObject> {
    Class isa  OBJC_ISA_AVAILABILITY;
}
```

Object.mm文件：

```cpp
typedef struct objc_class *Class; //类
typedef struct objc_object *id;	

@interface Object { 
    Class isa; 
} 
```
objc_object被包装成id类型，也即我们平时经常用到的id类型。

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

objc-private.h

```cpp
struct objc_object {
private:
    isa_t isa;
    ...
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

NSObject的第一个成员变量就是Class类型的isa。Class也即objc\_class，objc_class继承于objc_object，所以在objc_class中也包含isa_t类型的结构体isa。
为了方便阅读，我把它写成：

```cpp
struct objc_class : objc_object {
    isa_t isa;
    Class superclass;           //父类的指针
    cache_t cache;             // formerly cache pointer and vtable 方法缓存
    class_data_bits_t bits;    // class
    ...
}
```
我们经常说，所有的objc对象都包含一个isa指针，从源码上来看，准确说应该是isa_t结构体，而且objc的类也有这么一个isa，所以objc中的类也是一个对象。

除了isa，在objc_class中还有另外三个成员变量，之后才会谈到。
