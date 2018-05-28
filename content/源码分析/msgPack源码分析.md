### 一、pack.h 数据打包（序列化）
定义了基本的数据结构，以及一些序列化函数的声明。

数据结构

```c
#define msgpack_pack_user msgpack_packer*

typedef struct msgpack_packer {
	void* data;						//数据，实际上是msgpack_sbuffer* data
	msgpack_packer_write callback;	//回调函数
} msgpack_packer;
```

回调函数声明 - typedef函数指针

```c
typedef int (*msgpack_packer_write)(void* data, const char* buf, unsigned int len);
```

另外定义了一些宏，方便写接口。具体函数的实现在`pack_template.h`文件中。

```c
#define msgpack_pack_inline_func(name) \
	inline int msgpack_pack ## name

#define msgpack_pack_inline_func_cint(name) \
	inline int msgpack_pack ## name

#define msgpack_pack_inline_func_fixint(name) \
	inline int msgpack_pack_fix ## name

#define msgpack_pack_append_buffer(user, buf, len) \
	return (*(user)->callback)((user)->data, (const char*)buf, len)
```

### 二、pack_template.h 序列化模板

针对各种数据类型的数据序列化函数的具体实现。

#### 1.大小端模式的问题。

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

#### 2.整数序列化

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

2. 16bit、32bit、64bit无符号整数

 8bit无符号整数部分同上。
 
 `2^8 <= d < 2^16`，序列化用三个字节，第一个字节固定TAG为0xcd，后两个字节表示数（小端模式要逆序存放）。
 
 `2^16 <= d < 2^32`，序列化用五个字节，第一个字节固定TAG为0xce，后四个字节表示数（小端模式要逆序存放）。

 `2^32 <= d < 2^64`，序列化用九个字节，第一个字节固定TAG为0xcf，后八个字节表示数（小端模式要逆序存放）。

 从源码来看，8、16、32、64bit uint序列化分开了几个函数，里面逻辑的重复度挺高的，但是估计是考虑到大小端字节序的问题，所以还是不得不拆成几个函数来写。另外，在小端模式下`_msgpack_store16`、`_msgpack_store32`、`_msgpack_store64`这几个函数用来将数据进行字节逆序（**变成大端模式的表达**）。

3. 有符号整数
 
 其中正整数部分序列化同上。
 
 根据文档，negative fixint的定义，头三个bit为`111`，余下5个bit用来表示数。所以`-2^5 <= d < 0`序列化用一个字节。

 `-2^7 <= d < -2^5`，序列化两个字节，第一个字节固定TAG=0xd0。

 `-2^15 <= d < -2^7`，序列化三字节，第一个字节固定TAG=0xd1。
 
 `-2^31 <= d < -2^15`，序列化五字节，第一个字节固定TAG=0xd2。
 
 `-2^63 <= d < -2^31`，序列化九字节，第一个字节固定TAG=0xd3。
 
#### 3.浮点数序列化

序列化格式：TAG+Value。

[float数据在内存中的存储方法](https://blog.csdn.net/yezhubenyue/article/details/7436624) 
[double数据的内存存储方式](https://blog.csdn.net/lai123wei/article/details/7220684)

float型数据在内存中占用4字节存储，double占用8字节存储。源码中用了一个比较巧妙的做法把float、double转化为对应的32byte、64byte数据：

```c
float:
union { float f; uint32_t i; } mem;

double:
union { double f; uint64_t i; } mem;
```
把浮点数用整数的方式表达出来，然后**转换成大端模式字节序**。float类型的TAG为0xca，double类型的TAG为0xcb。

#### 4.Nil序列化

格式：TAG

0xc0

#### 5.Boolean类型序列化
格式: TAG

flase 0xc2，true 0xc3。

#### 6.Array类型序列化

格式：TAG + Length（数组长度） + Value

`msgpack_pack_array`这个函数中只拼接了TAG和序列化的length。

当数组长度<16，tag和length可以用一个字节表达。TAG固定为`1001`4个bit，余下4个bit表示长度。

当数组长度小于(2^16)-1，TAG = 0xdc，然后用固定两个字节表示长度。 当数组长度小于(2^32)-1，TAG = 0xdd，固定4字节表示长度。表示长度要用大端字节序。

value部分的序列化按照2~5基础数据类型序列化做。

#### 7.Map类型序列化

格式：TAG + Length + Value。TAG、Length序列化形式基本同上。

#### 8.Raw（string）类型序列化

格式：TAG + Length + Value。TAG、Length序列化形式基本同上。



### 三、object.h 基本数据结构

枚举`msgpack_object_type`对象类型：nil、boolean、正整数、负整数、double、raw（其实就是string）、array、map。

```c
typedef enum {
	MSGPACK_OBJECT_NIL					= 0x00,
	MSGPACK_OBJECT_BOOLEAN				= 0x01,
	MSGPACK_OBJECT_POSITIVE_INTEGER		= 0x02,
	MSGPACK_OBJECT_NEGATIVE_INTEGER		= 0x03,
	MSGPACK_OBJECT_DOUBLE				= 0x04,
	MSGPACK_OBJECT_RAW					= 0x05,
	MSGPACK_OBJECT_ARRAY				= 0x06,
	MSGPACK_OBJECT_MAP					= 0x07,
} msgpack_object_type;
```

所有原始数据经过“包装”之后会变成以下`msgpack_object`数据结构：

1. 对象

 ```c
typedef struct msgpack_object {
	msgpack_object_type type;//对象类型
	msgpack_object_union via;//数据实体
} msgpack_object;
```

2. 对象数据实体

 ```c
//这是一个联合体
typedef union {
	bool boolean;
	uint64_t u64;
	int64_t  i64;
	double   dec;
	msgpack_object_array array;
	msgpack_object_map map;
	msgpack_object_raw raw;
} msgpack_object_union;
```

3. 数组

 ```c
typedef struct {
	uint32_t size;				//大小
	struct msgpack_object* ptr;	//数组元素（对象）
} msgpack_object_array;
```

4. 字典

 ```c
typedef struct {
	uint32_t size;					//大小
	struct msgpack_object_kv* ptr;	//字典元素-对象键值对
} msgpack_object_map;
```

5. 键值对

 ```c
typedef struct msgpack_object_kv {
	msgpack_object key;	//键
	msgpack_object val;	//值
} msgpack_object_kv;
```

6. rawData

 ```c
typedef struct {
	uint32_t size; 	//大小
	const char* ptr;	//字符数组
} msgpack_object_raw;
```

### 四、object.c

`int msgpack_pack_object(msgpack_packer* pk, msgpack_object d)`函数。对经包装的数据对象`msgpack_object`进行序列化，返回值-1表示不成功，0为成功。

`void msgpack_object_print(FILE* out, msgpack_object o)`函数，打印数据对象的信息。

`bool msgpack_object_equal(const msgpack_object x, const msgpack_object y)`函数，判断两个对象是否相等

### 五、sbuffer.h

数据结构，存放缓冲数据

```c
typedef struct msgpack_sbuffer {
	size_t size; //已使用
	char* data;  //指向这一整块内存的指针
	size_t alloc;//总容量
} msgpack_sbuffer;
```

每一个`msgpack_sbuffer`结构对应绑定一个回调函数。这种绑定关系通过`msgpack_packer`结构体完成。回调函数实际上做的是把回调数据buf写入到sbuffer缓冲结构中：

```c
//sbuffer写入函数
static inline int msgpack_sbuffer_write(void* data, const char* buf, unsigned int len)
{
	msgpack_sbuffer* sbuf = (msgpack_sbuffer*)data;

	//扩容
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

在MessagePackPacker.m文件中绑定

```c
+ (NSData*)pack:(id)obj {
	msgpack_sbuffer* buffer = msgpack_sbuffer_new();//初始化一个新的msgpack_sbuffer缓冲结构，分配内存
	msgpack_packer* pk = msgpack_packer_new(buffer, msgpack_sbuffer_write);//初始化msgpack_packer结构体
	
	//...
}
```

回调函数在什么时候调用？序列化完成时。见pack_template.h，以其中一处回调为例：

```c
//第一个参数是msgpack_packer*
msgpack_pack_inline_func(_uint8)(msgpack_pack_user x, uint8_t d)
{
	msgpack_pack_real_uint8(x, d);
}

#define msgpack_pack_append_buffer(user, buf, len) \
	return (*(user)->callback)((user)->data, (const char*)buf, len)

#define msgpack_pack_real_uint8(x, d) \
do { \
	if(d < (1<<7)) { \
		/* fixnum */ \
		msgpack_pack_append_buffer(x, &TAKE8_8(d), 1); \  //回调
	} else { \
		/* unsigned 8 */ \
		unsigned char buf[2] = {0xcc, TAKE8_8(d)}; \
		msgpack_pack_append_buffer(x, buf, 2); \          //回调
	} \
} while(0)
```

### 六、序列化入口

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