
# 一、序列化

入口MessagePackPacker类。

```objective-c
+ (NSData*)pack:(id)obj {
	// Creates buffer and serializer instance
	msgpack_sbuffer* buffer = msgpack_sbuffer_new();
	msgpack_packer* pk = msgpack_packer_new(buffer, msgpack_sbuffer_write);
	
	// Pack the root array or dictionary node, which recurses through the rest
	[self packObject:obj into:pk];
	
	// Bridge the data back to obj-c's world
	NSData* data = [NSData dataWithBytes:buffer->data length:buffer->size];
	
	// Free
	msgpack_sbuffer_free(buffer);
	msgpack_packer_free(pk);
	
	return data;
}
```

## 1.初始化msgpack_sbuffer结构

`msgpack_sbuffer* buffer = msgpack_sbuffer_new();`初始化`msgpack_sbuffer`数据结构并分配内存，该结构用于存放缓冲数据：

```c
typedef struct msgpack_sbuffer {
	size_t size; //已使用
	char* data;  //指向这一整块内存的指针
	size_t alloc;//总容量
} msgpack_sbuffer;
```

## 2.初始化msgpack_packer结构

`msgpack_packer`数据结构定义如下：

```c
#define msgpack_pack_user msgpack_packer*

typedef struct msgpack_packer {
	void* data;						//数据，实际上是msgpack_sbuffer* data
	msgpack_packer_write callback;	//回调函数
} msgpack_packer;
 
 //函数指针
typedef int (*msgpack_packer_write)(void* data, const char* buf, unsigned int len);
```

`msgpack_packer* pk = msgpack_packer_new(buffer, msgpack_sbuffer_write);`对该结构体进行初始化，给每一个`msgpack_sbuffer`结构对应绑定一个回调函数。

```c
inline void msgpack_packer_init(msgpack_packer* pk, void* data, msgpack_packer_write callback)
{
	pk->data = data;
	pk->callback = callback;
}

inline msgpack_packer* msgpack_packer_new(void* data, msgpack_packer_write callback)
{
	msgpack_packer* pk = (msgpack_packer*)calloc(1, sizeof(msgpack_packer));
	if(!pk) { return NULL; }
	msgpack_packer_init(pk, data, callback);
	return pk;
}
```

回调函数实际上做的是把回调数据buf写入到sbuffer缓冲结构中：

```c
//sbuffer写入函数
//参数1：sbuffer结构体指针 参数2：待写入数据（回调的数据） 参数3：待写入长度
static inline int msgpack_sbuffer_write(void* data, const char* buf, unsigned int len)
{
	msgpack_sbuffer* sbuf = (msgpack_sbuffer*)data;

	//判断要不要扩容
	if(sbuf->alloc - sbuf->size < len) {
		size_t nsize = (sbuf->alloc) ?
				sbuf->alloc * 2 : MSGPACK_SBUFFER_INIT_SIZE;
        //len比较大时
		while(nsize < sbuf->size + len) { nsize *= 2; }

		void* tmp = realloc(sbuf->data, nsize);//对已分配内存进行大小调整，内容不变
		if(!tmp) { return -1; }

		sbuf->data = (char*)tmp;//调整指针
		sbuf->alloc = nsize;//调整总容量
	}

	memcpy(sbuf->data + sbuf->size, buf, len);//把buf数据复制到sbuffer中（拼接到原有数据的后面）
	sbuf->size += len;
	return 0;
}
```

## 3.序列化

```objective-c
[self packObject:obj into:pk];
```
序列化过程中核心的一步交给下面的方法完成。

```objective-c
// Pack a single object into the given packer
+ (void)packObject:(id)obj into:(msgpack_packer*)pk {
    //数组类型
	if ([obj isKindOfClass:[NSArray class]]) {
        //先拼接tag+序列化length
		msgpack_pack_array(pk, ((NSArray*)obj).count);
        //依次逐个序列化数组元素，并拼接
		for (id arrayElement in obj) {
			[self packObject:arrayElement into:pk];//递归操作
		}
	}
    //字典类型
    else if ([obj isKindOfClass:[NSDictionary class]]) {
        //tag+length
		msgpack_pack_map(pk, ((NSDictionary*)obj).count);
        //依次序列化key + value
		for(id key in obj) {
			[self packObject:key into:pk];
			[self packObject:[obj objectForKey:key] into:pk];
		}
	}
    //字符串类型
    else if ([obj isKindOfClass:[NSString class]]) {
		const char *str = ((NSString*)obj).UTF8String;
		int len = strlen(str);
		msgpack_pack_raw(pk, len);
		msgpack_pack_raw_body(pk, str, len);
	}
    //NSNumber（数字、boolean）
    else if ([obj isKindOfClass:[NSNumber class]]) {
		[self packNumber:obj into:pk];//根据具体的类型再分别调用不同的序列化函数
	}
    //Nil类型
    else if (obj==[NSNull null]) {
		msgpack_pack_nil(pk);
	} else {
		NSLog(@"Could not messagepack object: %@", obj);
	}
}
```
待序列化的数据大致可以分成3类：

1. 基本数据：int、float、double、boolean、nil；
2. 复合数据：数组、字典；
3. 字符串。

复合数据是由基本数据组成的，所以先从基本数据入手分析。

### 3.1基本数据

NSNumber类型的数据最终会由`+ (void)packNumber:(NSNumber*)num into:(msgpack_packer*)pk`方法进行处理。在这个方法中，根据细分的数据类型分别调用对应的函数进行处理。各种数据类型的数据序列化函数的具体实现都落在 pack_template.h 文件中。


#### 大小端模式的问题

比如 `unsigned int value = 0x12345678`，用 `unsigned char buf[4]`存储：

- 大端模式 低地址存放高位

 ```
buf[3] (0x78) -- 低位
buf[2] (0x56)
buf[1] (0x34)
buf[0] (0x12) -- 高位
```
　　
- 小端模式 低地址存放低位

 ```
buf[3] (0x12) -- 高位
buf[2] (0x34)
buf[1] (0x56)
buf[0] (0x78) -- 低位
```

对应大小端分别定义了宏，取一个数的低8位：

```c
#if defined(__LITTLE_ENDIAN__)
#define TAKE8_8(d)  ((uint8_t*)&d)[0]
#define TAKE8_16(d) ((uint8_t*)&d)[0]
#define TAKE8_32(d) ((uint8_t*)&d)[0]
#define TAKE8_64(d) ((uint8_t*)&d)[0]
#elif defined(__BIG_ENDIAN__)
#define TAKE8_8(d)  ((uint8_t*)&d)[0]
#define TAKE8_16(d) ((uint8_t*)&d)[1]
#define TAKE8_32(d) ((uint8_t*)&d)[3]
#define TAKE8_64(d) ((uint8_t*)&d)[7]
#endif
```

**msgPack序列化格式大致可以界定为TAG + (LENGTH) + (VALUE)，其中LENGTH和VALUE可选。LENGTH和VALUE部分，都要用大端字节序。**

#### 整数序列化

序列化格式：TAG+Value

1. 8bit无符号整数

 ```c
 //第一个参数是msgpack_packer*
#define msgpack_pack_real_uint8(x, d) \
do { \
	if(d < (1<<7)) { \
		/* fixnum */ \
		msgpack_pack_append_buffer(x, &TAKE8_8(d), 1); \
	} else { \
		/* unsigned 8 */ \
		unsigned char buf[2] = {0xcc, TAKE8_8(d)}; \
		msgpack_pack_append_buffer(x, buf, 2); \
	} \
} while(0)
```
 如果这个数`0<d<128`（7个bit足够表达），根据msgPack官方文档中positive fixint的定义，**序列化用一个字节就可以表示这个数**，首位bit为0，其余的7个bit用来表示这个数。

 如果这个数需要用8个bit表达（`128<=d<256`），那么序列化需要用两个字节，第一个字节固定TAG为0xcc，第二个字节8个bit用来表示这个数。
 
 ```
 #define msgpack_pack_append_buffer(user, buf, len) \
	return (*(user)->callback)((user)->data, (const char*)buf, len)
 ```
 
 `msgpack_pack_append_buffer`函数调用了之前提到的回调函数，把序列化数据写入到sbuffer缓冲结构中：

2. 16bit、32bit、64bit无符号整数

 8bit无符号整数部分同上。
 
 `2^8 <= d < 2^16`，序列化用三个字节，第一个字节固定TAG为0xcd，后两个字节表示数。
 
 `2^16 <= d < 2^32`，序列化用五个字节，第一个字节固定TAG为0xce，后四个字节表示数。

 `2^32 <= d < 2^64`，序列化用九个字节，第一个字节固定TAG为0xcf，后八个字节表示数。

 从源码来看，8、16、32、64bit uint序列化分开了几个函数，里面逻辑的重复度挺高的，但是估计是考虑到大小端字节序的问题，所以还是不得不拆成几个函数来写。另外，在小端模式下`_msgpack_store16`、`_msgpack_store32`、`_msgpack_store64`这几个函数用来将数据进行字节逆序。

3. 有符号整数
 
 其中正整数部分序列化同上。
 
 根据文档，negative fixint的定义，头三个bit为`111`，余下5个bit用来表示数。所以`-2^5 <= d < 0`序列化用一个字节。

 `-2^7 <= d < -2^5`，序列化两个字节，第一个字节固定TAG=0xd0。

 `-2^15 <= d < -2^7`，序列化三字节，第一个字节固定TAG=0xd1。
 
 `-2^31 <= d < -2^15`，序列化五字节，第一个字节固定TAG=0xd2。
 
 `-2^63 <= d < -2^31`，序列化九字节，第一个字节固定TAG=0xd3。
 
#### 浮点数序列化

序列化格式：TAG+Value。

float类型的TAG为0xca，double类型的TAG为0xcb。

Value部分的处理：

[float数据在内存中的存储方法](https://blog.csdn.net/yezhubenyue/article/details/7436624) 

[double数据的内存存储方式](https://blog.csdn.net/lai123wei/article/details/7220684)

float型数据在内存中占用4字节存储，double占用8字节存储。源码中用了一个比较巧妙的做法把float、double转化为对应的32byte、64byte数据：

```c
float:
union { float f; uint32_t i; } mem;

double:
union { double f; uint64_t i; } mem;
```
把浮点数的存储用整数的方式表达出来，然后**转换成大端模式字节序**。

#### Nil序列化

格式：TAG = 0xc0

#### Boolean类型序列化
格式: TAG

flase 0xc2，true 0xc3。

### 3.2 数组

格式：TAG + Length（数组长度） + Value。Value部分由每个元素的TAG -（Length）-（Value）组成。

`+ (void)packObject:(id)obj into:(msgpack_packer*)pk`方法中数组序列化部分的代码：

```objective-c
//序列化数组长度。T-L
msgpack_pack_array(pk, ((NSArray*)obj).count);
//逐个元素递归进行序列化 T-(L)-(V)
for (id arrayElement in obj) {
	[self packObject:arrayElement into:pk];
}
```

`msgpack_pack_array`这个函数中只拼接了TAG和序列化的length。

当数组长度<16，Tag+Length可以用一个字节表达。TAG固定为`1001`4个bit，余下4个bit表示长度。

当数组长度小于(2^16)-1，TAG = 0xdc，然后用固定两个字节表示长度。 当数组长度小于(2^32)-1，TAG = 0xdd，固定4字节表示长度。Length要用大端字节序。


### 3.3 字典

格式：TAG + Length + Value ，之后为便于表达，用首字母缩写替代。Value部分由字典的每个元素序列化组成。字典元素key-obj对，先序列化key后序列化obj。

```
T-L | T-L-V T-L-V | T-L-V T-L-V | T-L-V T-L-V |....
     -----------------------------------------
      value部分，为便于阅读用'|'表示分割字典元素。每个元素的key、obj各自都是T-L-V
```

```objective-c
//序列化字典长度 T-L
msgpack_pack_map(pk, ((NSDictionary*)obj).count);
//逐个元素递归进行序列化。键、值都要分开进行序列化。
for(id key in obj) {
	[self packObject:key into:pk];
	[self packObject:[obj objectForKey:key] into:pk];
}
```

### 3.4 Raw（string）类型序列化

格式：TAG + Length + Value。Value部分记得要用大端字节序。

## 4.把数据转换为二进制格式

`NSData* data = [NSData dataWithBytes:buffer->data length:buffer->size];`

## 5.释放资源

```c
msgpack_sbuffer_free(buffer);
msgpack_packer_free(pk);
```

# 二、反序列化
之前写过一个json解析器的代码，然后看了msgPack反序列化的代码，发现思路基本上都差不多...使用流的方式，解析器从头扫描一次字符串，就能完整解析出对应的数据结构。无论是Json解析还是msgPack解析，本质上，这类解析器就是一个**状态机**，根据定义好的格式，就能实现状态转移。

解析的过程包括词法分析和语法分析两个部分，词法分析就是按照构词规则将字符串解析成TOKEN流。得到TOKEN后，就进行语法分析，检查这些TOKEN序列构成的msgPack字节流结构是否合法。

比如masPack是由一系列`TAG`+`Length`+`Value`构成的，那么TAG就可以是TOKEN。在代码具体实现中，Length并没有作为TOKEN（读到TAG后，根据TAG分析Length占多少字节，然后解析出Length的值l，然后数据流直接向前移动l字节开始解析Value）。在msgPack源码中TOKEN定义在`unpack_define.h`文件中。

有了TOKEN还不行，我们还需要将某个元素的字面量保存起来，所以还要定义一个包装对象结构体：

```c
typedef struct msgpack_object {
	msgpack_object_type type;//类型 
	msgpack_object_union via;//数据
} msgpack_object;
```

具体的源码是不会逐句逐句分析的，因为解析原理很好懂，就是一个状态机。核心解析函数是`unpack_template.h`文件中的`template_excute`。

另外有一点，觉得msgPack的TAG设计真的挺巧妙的。所有的TAG用1字节（或者几个bit）表示，比较特殊的几种：

```
format name 		first byte (in binary)
positive fixint		0xxxxxxx	
fixmap				1000xxxx	
fixarray			1001xxxx	
fixstr				101xxxxx	
negative fixint		111xxxxx //结合：计算机中负数的二进制表示
```

其余的TAG都是`110xxxxx`，每一个TAG都不是其他TAG的前缀，这种设计使得TAG和后面的数据很容易分离出来。原本我以为TAG的后5个bit是随意取的，只要不重复就行。实际上，以`T-L-V`格式组成序列化的元素，表达`L`所需的字节长度就设计在这5个bit中。比如float32元素，TAG = 0xca，通过运算：`1 << (TAG & 0x03)`可以得到Length部分的长度是4字节。TAG = 0xca\~0xd3都可以用`1 << (TAG & 0x03)`得到Length部分的长度，而TAG = 0xda\~0xdf用`2 << (TAG & 0x01)`得到Length的长度。

槽点：代码使用了很多宏，夹杂着goto语句，而且有一些无用代码，虽然核心代码是写得简洁了但是看得略难受...

