## 一.预备知识

### isa
```cpp
union isa_t 
{
    isa_t() { }
    isa_t(uintptr_t value) : bits(value) { }

    Class cls;//指针
    uintptr_t bits;

#if SUPPORT_PACKED_ISA

//-------------------__x86_64__上的实现
# elif __x86_64__
#   define ISA_MASK        0x00007ffffffffff8ULL
#   define ISA_MAGIC_MASK  0x001f800000000001ULL
#   define ISA_MAGIC_VALUE 0x001d800000000001ULL
    struct {
        uintptr_t nonpointer        : 1; //0：普通isa指针，1：优化的指针用于存储引用计数
        uintptr_t has_assoc         : 1; //表示该对象是否包含associated object，如果没有，析构时会更快
        uintptr_t has_cxx_dtor      : 1; //表示对象是否含有c++或者ARC的析构函数，如果没有，析构更快
        uintptr_t shiftcls          : 44; // MACH_VM_MAX_ADDRESS 0x7fffffe00000 类的指针
        uintptr_t magic             : 6; //值为0x3b 用于在调试时分辨对象是否未完成初始化（用于调试器判断当前对象是真的对象还是没有初始化的空间）
        uintptr_t weakly_referenced : 1; //对象是否有过weak对象
        uintptr_t deallocating      : 1; //是否正在析构
        uintptr_t has_sidetable_rc  : 1; //该对象的引用计数值是否过大无法存储在isa指针，如果引用计数溢出了，引用计数会存储在sideTable中
        uintptr_t extra_rc          : 8; //用于保存自动引用计数的标志位，存储引用计数值减一后的结果。对象的引用计数超过 1，会存在这个这个里面，如果引用计数为 10，extra_rc的值就为 9。
#       define RC_ONE   (1ULL<<56)
#       define RC_HALF  (1ULL<<7)
    };

#endif
```
我们常说的isa指针实际上是一个union共同体`isa_t`，取决于其中的struct结构体成员，`isa_t`占64位空间。用64位来存储一个内存地址有点浪费，借鉴tagged Pointer，苹果对存储方案进行优化，64位中的一部分用来存储额外的内容。在`__x86_64__`下的标志位含义见注释。

### Tagged Pointer
假设我们要存储一个NSNumber对象，其值是一个整数。正常情况下，如果这个整数只是一个NSInteger的普通变量，那么它所占用的内存是与CPU的位数有关，在32位CPU下占4个字节，在64位CPU下是占8个字节的。而指针类型的大小通常也是与CPU位数相关，一个指针所占用的内存在32位CPU下为4个字节，在64位CPU下也是8个字节。

如果没有Tagged Pointer对象，从32位机器迁移到64位机器中后，虽然逻辑没有任何变化，但这种NSNumber、NSDate一类的对象所占用的内存会翻倍。

为了改进上面提到的内存占用和效率问题，苹果提出了Tagged Pointer对象。由于NSNumber、NSDate一类的变量本身的值需要占用的内存大小常常不需要8个字节。所以我们可以将一个对象的指针拆成两部分，一部分直接保存数据，另一部分作为特殊标记，表示这是一个特别的指针，不指向任何一个地址。

详细的技术可以看这个链接：[深入理解Tagged Pointer](http://www.infoq.com/cn/articles/deep-understanding-of-tagged-pointer/)

如果对象支持使用Tagged Pointer，其指针值会作为引用计数返回。

### SideTables && SideTable
```cpp
static StripedMap<SideTable>& SideTables() {
    return *reinterpret_cast<StripedMap<SideTable>*>(SideTableBuf);
}
```
为了管理所有对象的引用计数和weak指针，苹果创建了一个全局的`SideTables`，它实际上是一个全局的Hash表，存储了一个个`SideTable`结构体（接下来可能会看得有点绕，一个有s一个没有s）。Hash算法：点进`StripedMap`的定义，其中有一部分可以看到：

```cpp
template<typename T>
class StripedMap {
    enum { CacheLineSize = 64 };

	 
    struct PaddedT {
    //这个T类型就是SideTable
        T value alignas(CacheLineSize);//alignas 64位对齐
    };

    PaddedT array[StripeCount];//PaddedT数组,size=64

    static unsigned int indexForPointer(const void *p) {
        uintptr_t addr = reinterpret_cast<uintptr_t>(p);//地址的类型转换
        return ((addr >> 4) ^ (addr >> 9)) % StripeCount;
    }
}；
```
这里把对象的地址当做key，把对象地址右移4位的值和右移9位的值进行异或运算，得到的结果与64做模运算得到Hash值，作为数组下标。通过数组下标，可以定位获取value（也就是SideTable）。数组的size是64。

假设我们有足够多的对象地址，这些地址的分布比较平均，算法足够好那么Hash的结果也会很平均。Hash表有n个元素，那么就可以将冲突减少到n分之一。

SideTable结构体：

```cpp
struct SideTable {
    spinlock_t slock;       //保证原子操作的自旋锁
    RefcountMap refcnts;    //保存引用计数的散列表
    weak_table_t weak_table;//保存weak引用的全局散列表
    ...
};
```
SideTable用来管理引用计数表和weak表，用一个自旋锁来保证这些表操作时的竞态安全。

1. `spinlock_t slock`自旋锁，作用是在读写引用计数时对SideTable加锁，避免数据错误。为什么不在大的Hash表SideTables中加锁，而是在SideTable结构中加锁呢？在SideTable中加锁，锁的粒度小，每个SideTable可以做到相互独立。如果只对Hash表加锁，锁的粒度以整张表为单位，内存中对象的数量巨大，需要非常频繁地操作Hash表，锁被请求的频率很高、锁竞争强度大。锁分离可以改善这些问题。

2. `RefcountMap refcnts`保存对象具体的引用计数的值。RefcountMap可以把它理解成c++中的Map，维护了从对象地址到引用计数的映射。这里举个例子来理解一下这里的分块化方式：假设内存中有16个对象：地址0x0000、0x0001、...0x000f。然后我用一个散列表SideTables[8]来存放这16个对象，假设每两个对象映射相同（比如0x0000、0x0001这两个对象），冲突的概率是1/8，那么把他们的内存管理都放到同一个SideTable中，然后通过`table.refcnts.find(0x0000)`来获得地址为0x0000的对象的真正引用计数。

 可能由于内存中对象的数目十分巨大，这样做能起到分流的作用。Hash值相同的对象，交给了同一个`SideTable`进行管理。

 `RefcountMap`的细节稍后再谈，这里先把SideTable的构成过一遍。

3. `weak_table_t weak_table` 苹果使用一个全局的 weak 表来保存所有的 weak 引用。

### RefcountMap
```cpp
typedef objc::DenseMap<DisguisedPtr<objc_object>,size_t,true> RefcountMap;
```
RefcountMap实际上是一个DenseMap的类。沿着`DenseMap`-->`DenseMapBase`找，`DenseMapBase`实际上就是一个map，实现了迭代器和一些函数，比如`find`、`insert`、`erase`等等。

存储引用计数具体是通过DenseMap来实现的，这个类中包含了映射对象到其引用计数的键值对。键是`DisguisedPtr<objc_object>`，而值是`size_t`（相当于是unsigned long）。`DisguisedPtr`类是对 `objc_object *`指针及其一些操作进行的封装，在类注释中写到：
> DisguisedPtr<T> acts like pointer type T*, except the stored value is disguised to hide it from tools like `leaks`.nil is disguised as itself so zero-filled memory works as expected, which means 0x80..00 is also disguised as itself but we don't care. Note that weak_entry_t knows about this encoding.

所以`DisguisedPtr`类是为了让`objc_object*`看起来不会有内存泄漏，其内容相当于是对象的地址。而`size_t`则保存引用计数，64位，这里保存的是引用计数减一后的值。

```cpp
template<typename KeyT, typename ValueT,
         bool ZeroValuesArePurgeable = false, 
         typename KeyInfoT = DenseMapInfo<KeyT> >
class DenseMap
```
根据DenseMap模板的定义，`KeyInfoT`估计是专门用来描述键的，交给`DenseMapInfo`来生成键的描述。具体就不深究了，因为没弄懂它的用途。

```cpp
template<typename T>
struct DenseMapInfo<DisguisedPtr<T>> {
  static inline DisguisedPtr<T> getEmptyKey() {
    return DisguisedPtr<T>((T*)(uintptr_t)-1);
  }
  static inline DisguisedPtr<T> getTombstoneKey() {
    return DisguisedPtr<T>((T*)(uintptr_t)-2);
  }
  static unsigned getHashValue(const T *PtrVal) {//哈希算法
      return ptr_hash((uintptr_t)PtrVal);
  }
  static bool isEqual(const DisguisedPtr<T> &LHS, const DisguisedPtr<T> &RHS) {
      return LHS == RHS; 
  }
};
```

### weak_table_t
之前说weak表其实是一个Hash表，将对象的地址作为key，该指向对象的weak指针的**地址**数组作为value，由`weak_entry_t`这个结构来负责维护和存储。weak表的定义：

```cpp
struct weak_table_t {
    weak_entry_t *weak_entries;//是一个weak_entry_t数组
    size_t    num_entries;//维护数组的size
    uintptr_t mask; //参与判断引用计数的辅助量
    uintptr_t max_hash_displacement; //最大偏移量
};
```

`weak_entry_t`是weak表的一个内部结构体，定义如下：

```cpp
#define WEAK_INLINE_COUNT 4
#define REFERRERS_OUT_OF_LINE 2

struct weak_entry_t {
    DisguisedPtr<objc_object> referent;//key：对象地址
    union {
        struct {
            weak_referrer_t *referrers;//value：可变数组，保存所有指向这个对象的weak指针的地址。
            uintptr_t        out_of_line_ness : 2;
            uintptr_t        num_refs : PTR_MINUS_2;
            uintptr_t        mask;
            uintptr_t        max_hash_displacement;
        };
        struct {
            // out_of_line_ness field is low bits of inline_referrers[1]
            weak_referrer_t  inline_referrers[WEAK_INLINE_COUNT];//大小为4的数组，默认情况下用来存储弱引用的指针
        };
    };
};

typedef DisguisedPtr<objc_object *> weak_referrer_t;
```
根据前文的分析，DisguisedPtr是对`objc_object*`的封装，解决内存泄漏的问题。所以`referent`是对象的地址。

`referrers`是一个可变数组，保存了所有指向这个对象的弱引用的指针（的地址）。当对象被释放时，`referrers`中的所有指针都会被置为nil。

`inline_referrers`是一个大小为4的数组，默认情况下用来存储弱引用指针，如果数量大于4的时候就改用`referrers`来存储。

关于weak表更详细的分析，放到另一篇笔记上讲。

## 二.retain
retain方法的实现代码：

```cpp
- (id)retain {
    return ((id)self)->rootRetain();
}

ALWAYS_INLINE id 
objc_object::rootRetain()
{
    return rootRetain(false, false);
}
```
`rootRetain`对内存管理的原理就是将 `isa_t` 结构体中 `extra_rc` 标志位的值加一。在`isa_t`中，`extra_rc`保存的是对象额外的引用计数，也就是说如果他的引用计数为1，那么`extra_rc`的值为0。

`rootRetain`函数的两个参数传入的都是false，接下来对这个函数进行简化分析。

#### 1. retain count无进位，`extra_rc`的位数足够存储引用计数。
```cpp
ALWAYS_INLINE id 
objc_object::rootRetain(bool tryRetain, bool handleOverflow)
{
    if (isTaggedPointer()) return (id)this;//先看是否支持 TaggedPointer

    isa_t oldisa;
    isa_t newisa;

    do {
        oldisa = LoadExclusive(&isa.bits);//加载 isa 的值
        newisa = oldisa;
        
        uintptr_t carry;
        newisa.bits = addc(newisa.bits, RC_ONE, 0, &carry);  // extra_rc++ 将 isa_t 中的extra_rc的值加一
    } while (slowpath(!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits))); //更新 isa
    
    return (id)this;
}
```
这个函数中做的事情：

1. 把原isa取出来保存两份，`LoadExclusive`函数加载isa的值（这个函数实际上只是把参数原样返回了）。一份用来记录旧值，一份用来记录`extra_rc`的值加一。
2. 调用`addc`函数对`extra_rc`的值加一。
3. `StoreExclusive`函数更新isa。
4. 返回当前对象。

留意`#define RC_ONE   (1ULL<<56)`，`extra_rc`正好位于`isa_t`中的56~63位，所以`addc(newisa.bits, RC_ONE, 0, &carry)`是对`extra_rc`加一。

#### 2.有进位
```cpp
ALWAYS_INLINE id 
objc_object::rootRetain(bool tryRetain, bool handleOverflow)
{
    if (isTaggedPointer()) return (id)this;//先看是否支持 TaggedPointer

    isa_t oldisa;
    isa_t newisa;

    do {
        oldisa = LoadExclusive(&isa.bits);//加载 isa 的值
        newisa = oldisa;
        
        uintptr_t carry;
        newisa.bits = addc(newisa.bits, RC_ONE, 0, &carry);  // extra_rc++ 将 isa_t 中的extra_rc的值加一

        if (slowpath(carry)) {
            // newisa.extra_rc++ overflowed
            if (!handleOverflow) {
                ClearExclusive(&isa.bits); //ClearExclusive是个空实现？
                return rootRetain_overflow(tryRetain);
            }
        }
    } while (slowpath(!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits))); //更新 isa

    return (id)this;
}
```
如果`extra_rc`的值加一后溢出了，carry就会有值。接着如果`handleOverflow = false`（retain方法源码传入的就是false），不处理溢出，就会调用`ClearExclusive`和`rootRetain_overflow`函数进行处理（`ClearExclusive`点进源码看是个空实现，啥也没干）。

```cpp
NEVER_INLINE id 
objc_object::rootRetain_overflow(bool tryRetain)
{
    return rootRetain(tryRetain, true);
}
```
`rootRetain_overflow`函数重新调用了一次`rootRetain`，只不过这次参数`handleOverflow`传入的是true，接下来就要处理溢出了。

#### 3. 有进位，且处理溢出
```cpp
ALWAYS_INLINE id 
objc_object::rootRetain(bool tryRetain, bool handleOverflow)
{
    if (isTaggedPointer()) return (id)this;//先看是否支持 TaggedPointer

    bool sideTableLocked = false;
    bool transcribeToSideTable = false;

    isa_t oldisa;
    isa_t newisa;

    do {
        transcribeToSideTable = false;
        oldisa = LoadExclusive(&isa.bits);//加载 isa 的值
        newisa = oldisa;
        
        uintptr_t carry;
        newisa.bits = addc(newisa.bits, RC_ONE, 0, &carry);  // extra_rc++ 将 isa_t 中的extra_rc的值加一

        if (slowpath(carry)) {
            if (!tryRetain && !sideTableLocked) sidetable_lock(); //sideTable上锁
            sideTableLocked = true; //sideTable已经锁上了
            transcribeToSideTable = true;
            newisa.extra_rc = RC_HALF; //extra_rc标记为 RC_HALF
            newisa.has_sidetable_rc = true;
        }
    } while (slowpath(!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits))); //更新 isa

    if (slowpath(transcribeToSideTable)) {
        sidetable_addExtraRC_nolock(RC_HALF);
    }

    if (slowpath(!tryRetain && sideTableLocked)) sidetable_unlock(); //sideTable解锁
    return (id)this;
}


#define RC_HALF  (1ULL<<7)
```

处理溢出之前先对sideTable上锁，处理结束后解锁，保证引用计数读写的安全性。处理溢出时，把`extra_rc`的值置为`RC_HALF`，`RC_HALF = 0b10000000`。然后isa的`has_sidetable_rc`标志位置为true，表示引用计数过大溢出了。更新isa，接着调用`sidetable_addExtraRC_nolock`函数，传入参数`delta_rc = RC_HALF`。

```cpp
bool 
objc_object::sidetable_addExtraRC_nolock(size_t delta_rc)
{
    SideTable& table = SideTables()[this];//获取对象对应的SideTable

    size_t& refcntStorage = table.refcnts[this];//获取引用计数
    size_t oldRefcnt = refcntStorage;

    if (oldRefcnt & SIDE_TABLE_RC_PINNED) return true;//溢出标记位已经为1，SideTable中对象对应的RefcountMap引用计数存储已经满了，直接返回撤销行动。

    uintptr_t carry;
    //将 RC_HALF 添加到 oldRefcnt 中
    size_t newRefcnt = addc(oldRefcnt, delta_rc << SIDE_TABLE_RC_SHIFT, 0, &carry);//#define RC_HALF  (1ULL<<7)。SIDE_TABLE_RC_SHIFT = 2
    //溢出了
    if (carry) {
        refcntStorage = SIDE_TABLE_RC_PINNED | (oldRefcnt & SIDE_TABLE_FLAG_MASK);//与运算获得低两位标志位，或运算把pin位置1.相当于是把存储引用计数的区段（2~62位）每位都清零了，然后标记溢出。
        return true;
    }
    //没有溢出，存储新的引用计数到refcntStorage
    else {
        refcntStorage = newRefcnt;
        return false;
    }
}
```

`addc(oldRefcnt, delta_rc << SIDE_TABLE_RC_SHIFT, 0, &carry)`这里我们将 `RC_HALF` 添加到 `oldRefcnt` 中，其中的各种 `SIDE_TABLE `宏定义如下：

```
// 表示是否有弱引用指向这个对象，如果没有在析构时释放内存更快
#define SIDE_TABLE_WEAKLY_REFERENCED (1UL<<0) 
// 表示对象是否正在释放。1 正在释放，0 没有。
#define SIDE_TABLE_DEALLOCATING      (1UL<<1)
// 用于引用计数的加一\减一。实际上是加4\减4，因为低两位有其他含义，真正的计数位从第三位开始的。64位系统下，2~62位存储引用计数。
#define SIDE_TABLE_RC_ONE            (1UL<<2)
//溢出标志位。WORD_BITS在32位、64位系统下分别等于32、64。随着引用计数不断增加，如果这位变成1了，就表示引用计数值已经达到最大
#define SIDE_TABLE_RC_PINNED         (1UL<<(WORD_BITS-1))

#define SIDE_TABLE_RC_SHIFT 2
#define SIDE_TABLE_FLAG_MASK (SIDE_TABLE_RC_ONE-1)
```
因为 refcntStorage 中的 64 位的最低两位是有意义的标志位，所以在使用 addc 时要将 `delta_rc` 左移两位，获得一个新的引用计数 newRefcnt。

如果这时出现了溢出，那么就会撤销这次的行为。否则，会将新的引用计数存储到 refcntStorage 指针中。

### 4. 其他情况
```cpp
//没有开启isa优化
if (slowpath(!newisa.nonpointer)) {
    ClearExclusive(&isa.bits);
    if (!tryRetain && sideTableLocked) sidetable_unlock();
    if (tryRetain) return sidetable_tryRetain() ? (id)this : nil;
    else return sidetable_retain();
}

//正在析构
if (slowpath(tryRetain && newisa.deallocating)) {
    ClearExclusive(&isa.bits);
    if (!tryRetain && sideTableLocked) sidetable_unlock();
    return nil;
}
```

1. 没有开启isa优化

 由于这里的参数`tryRetain = false`、`sideTableLocked = false`，所以相当于只调用了`sidetable_retain`函数。把SideTable中存储的对象的引用计数取出，+1作为结果返回。

2. 对象正在析构

 返回nil。

## 三.release
```cpp
-(void) release {
    _objc_rootRelease(self);
}

void _objc_rootRelease(id obj) {
    obj->rootRelease();
}

ALWAYS_INLINE bool objc_object::rootRelease() {
    return rootRelease(true, false);
}
```
`release`实例方法实际上是调用`rootRelease`函数进行实现的。`rootRelease`的实现代码比较长，这里稍微简化一下进行分析。

### 1.无借位
```cpp
ALWAYS_INLINE bool 
objc_object::rootRelease(bool performDealloc, bool handleUnderflow)
{
    if (isTaggedPointer()) return false;//判断是否TaggedPointer

    isa_t oldisa;
    isa_t newisa;

 retry:
    do {
        oldisa = LoadExclusive(&isa.bits);//加载isa的值
        newisa = oldisa;
        uintptr_t carry;
        newisa.bits = subc(newisa.bits, RC_ONE, 0, &carry);  // extra_rc--
    } while (slowpath(!StoreReleaseExclusive(&isa.bits, oldisa.bits, newisa.bits)));//更新isa

    return false;
}
```
先判断是否TaggedPointer，如果是TaggedPointer可以直接返回，因为可以直接获得引用计数。

使用`LoadExclusive`获得isa，然后调用`subc`函数将isa中的`extra_rc`引用计数减一，最后调用`StoreReleaseExclusive`对isa进行更新。

### 2.从SideTable借位
```cpp
ALWAYS_INLINE bool 
objc_object::rootRelease(bool performDealloc, bool handleUnderflow)
{
    if (isTaggedPointer()) return false;//判断是否TaggedPointer

    bool sideTableLocked = false;

    isa_t oldisa;
    isa_t newisa;

 retry:
    do {
        oldisa = LoadExclusive(&isa.bits);//加载isa的值
        newisa = oldisa;
        
        uintptr_t carry;
        newisa.bits = subc(newisa.bits, RC_ONE, 0, &carry);  // extra_rc--
        if (slowpath(carry)) {//需要从SideTable借位
            goto underflow;
        }
    } while (slowpath(!StoreReleaseExclusive(&isa.bits, oldisa.bits, newisa.bits)));//更新isa

 underflow:
    newisa = oldisa;

    if (slowpath(newisa.has_sidetable_rc)) {
        if (!handleUnderflow) {//rootRelease方法传入的handleUnderflow为false
            ClearExclusive(&isa.bits);
            return rootRelease_underflow(performDealloc);
        }

        size_t borrowed = sidetable_subExtraRC_nolock(RC_HALF);//借位

        if (borrowed > 0) {
            newisa.extra_rc = borrowed - 1;  // redo the original decrement too
            bool stored = StoreReleaseExclusive(&isa.bits, oldisa.bits, newisa.bits);//更新isa
            if (!stored) {
                isa_t oldisa2 = LoadExclusive(&isa.bits);
                isa_t newisa2 = oldisa2;
                if (newisa2.nonpointer) {
                    uintptr_t overflow;
                    newisa2.bits = 
                        addc(newisa2.bits, RC_ONE * (borrowed-1), 0, &overflow);
                    if (!overflow) {
                        stored = StoreReleaseExclusive(&isa.bits, oldisa2.bits, 
                                                       newisa2.bits);
                    }
                }
            }
        }
    }
}    
```
`subc(newisa.bits, RC_ONE, 0, &carry)`在对`extra_rc-1`时需要借位，假设此时`isa_t`中的`has_sidetable_rc = true`，SideTable中存储了引用计数。`rootRelease`函数传入的`handleUnderflow`为false，代表不处理借位，所以会执行`rootRelease_underflow`函数，和retain时类似，此时重新调用`rootRelease`函数，只不过传入`handleUnderflow = true`，处理借位。然后调用`sidetable_subExtraRC_nolock`，把SideTable中的引用计数减去`RC_HALF`并进行借位得到`borrowed`。

```cpp
size_t 
objc_object::sidetable_subExtraRC_nolock(size_t delta_rc)
{
    SideTable& table = SideTables()[this];

    RefcountMap::iterator it = table.refcnts.find(this);
    if (it == table.refcnts.end()  ||  it->second == 0) {//找不到引用计数或者为0
        return 0;
    }
    size_t oldRefcnt = it->second;
    
    size_t newRefcnt = oldRefcnt - (delta_rc << SIDE_TABLE_RC_SHIFT);
    it->second = newRefcnt;
    return delta_rc;
}
```
接着重新设置`isa_t`中的`extra_rc`为`borrowed - 1`，更新isa。

### 3.销毁对象
如果在上一步调用`sidetable_subExtraRC_nolock`函数是，没有找到SideTable中的引用计数或者引用计数为0，那么就要向对象发送`dealloc`消息。

```cpp
if (slowpath(newisa.deallocating)) {//检查是否正在销毁对象
    ClearExclusive(&isa.bits);
    if (sideTableLocked) sidetable_unlock();
    return overrelease_error();//log重复销毁的提示
}

newisa.deallocating = true;//isa标记正在销毁对象
if (!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits)) goto retry;

if (slowpath(sideTableLocked)) sidetable_unlock();

__sync_synchronize();
if (performDealloc) { //传参performDealloc=true，发送dealloc消息
    ((void(*)(objc_object *, SEL))objc_msgSend)(this, SEL_dealloc);
}
```

### 4.其他情况
如果没有开启isa优化：

```cpp
 if (slowpath(!newisa.nonpointer)) {//没有开启isa优化
    return sidetable_release(performDealloc);
}
```
调用`sidetable_release`函数，直接对SideTable中存储的对象的引用计数进行操作。

```cpp
uintptr_t
objc_object::sidetable_release(bool performDealloc)
{
    SideTable& table = SideTables()[this];

    bool do_dealloc = false;

    table.lock();
    RefcountMap::iterator it = table.refcnts.find(this);
    if (it == table.refcnts.end()) {//没有找到引用计数
        do_dealloc = true;
        table.refcnts[this] = SIDE_TABLE_DEALLOCATING;//标记为正在析构
    } else if (it->second < SIDE_TABLE_DEALLOCATING) {//有弱引用。引用计数为0
        // SIDE_TABLE_WEAKLY_REFERENCED may be set. Don't change it.
        do_dealloc = true;//所以返回值还是1咯？
        it->second |= SIDE_TABLE_DEALLOCATING;//添加正在析构的标记
    } else if (! (it->second & SIDE_TABLE_RC_PINNED)) {//没有溢出
        it->second -= SIDE_TABLE_RC_ONE;//引用计数减1
    }
    table.unlock();
    if (do_dealloc  &&  performDealloc) {//如果需要释放就调用dealloc方法
        ((void(*)(objc_object *, SEL))objc_msgSend)(this, SEL_dealloc);
    }
    return do_dealloc;
}
```

## 四.获取引用计数 retainCount
在MRC环境可以使用`retainCount`方法来获得对象的引用计数。这一节我们来看一下它的实现：

```cpp
- (NSUInteger)retainCount {
    return ((id)self)->rootRetainCount();
}
```
`retainCount`实例方法实际上是调用`rootRetainCount`函数来实现的。

```cpp
inline uintptr_t objc_object::rootRetainCount()
{
    if (isTaggedPointer()) return (uintptr_t)this;//如果是TaggedPointer，直接返回，因为可以直接获取引用计数。

    sidetable_lock();
    isa_t bits = LoadExclusive(&isa.bits);//加载isa的值
    ClearExclusive(&isa.bits);
    if (bits.nonpointer) {
        uintptr_t rc = 1 + bits.extra_rc;
        if (bits.has_sidetable_rc) {
            rc += sidetable_getExtraRC_nolock();
        }
        sidetable_unlock();
        return rc;
    }

    sidetable_unlock();
    return sidetable_retainCount();
}

size_t objc_object::sidetable_getExtraRC_nolock()
{
    SideTable& table = SideTables()[this];
    RefcountMap::iterator it = table.refcnts.find(this);
    if (it == table.refcnts.end()) return 0;
    else return it->second >> SIDE_TABLE_RC_SHIFT;//右移两位。
}
```
首先判断这个对象是否支持TaggedPointer，如果使用了TaggedPointer，可以直接获取引用计数，返回。

如果不支持TaggedPointer，那么看一下isa是否开启优化了。如果开启了优化（`bits.nonpointer = true`），先从`isa_t`中的`extra_rc + 1`获取引用计数，然后如果`has_sidetable_rc = true`，那么从SideTable中获取余下存储的引用计数。

如果不支持TaggedPointer，也没有开启isa优化，调用`sidetable_retainCount`函数，把SideTable中存储的对象的引用计数取出，+1作为结果返回。

在 ARC 环境下，可以使用 Core Foundation 库的 `CFGetRetainCount()` 方法，也可以使用 Runtime 的 `_objc_rootRetainCount(id obj)` 方法来获取引用计数。这个函数也是调用`rootRetainCount()` 方法实现的。

通过上述几种方法得到引用计数不能完全尽信。
[可以看一下这篇文章中的测试](https://www.jianshu.com/p/9745f4cd088d)。总的来说就是不建议获取引用计数。

> 对于已释放的对象以及不正确的对象地址，有时也返回 “1”。它所返回的引用计数只是某个给定时间点上的值，该方法并未考虑到系统稍后会把自动释放吃池清空，因而不会将后续的释放操作从返回值里减去。clang 会尽可能把 NSString 实现成单例对象，其引用计数会很大。如果使用了 TaggedPointer，NSNumber 的内容有可能就不再放到堆中，而是直接写在宽敞的64位栈指针值里。其看上去和真正的 NSNumber 对象一样，只是使用 TaggedPointer 优化了下，但其引用计数可能不准确。[Objective-C 引用计数原理](http://yulingtianxia.com/blog/2015/12/06/The-Principle-of-Refenrence-Counting/)
 
 
## 总结
1. 如果是TaggedPointer，可以直接获得对象的引用计数。
2. 存储引用计数会用到isa中的`extra_rc`和SideTable。 
3. 如果没有开启isa指针优化，那么会直接对`SideTable`中的引用计数进行操作。
4. 在引用计数=0时，会调用dealloc方法回收对象。
5. `extra_rc`的值=真实的引用计数-1。
6. 根据苹果内存管理的规则，使用alloc, new, copy, mutableCopy创建的对象，引用计数为1



参考文章：

[iOS管理对象内存的数据结构以及操作算法--SideTables、RefcountMap、weak_table_t-二](https://www.jianshu.com/p/8577286af88e)

[Objective-C 引用计数原理](http://yulingtianxia.com/blog/2015/12/06/The-Principle-of-Refenrence-Counting/)
