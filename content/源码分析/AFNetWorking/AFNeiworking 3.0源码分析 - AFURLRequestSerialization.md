`AFURLRequestSerialization`模块主要做的两样事情：

1.创建普通`NSMutableURLRequest`请求对象

2.创建multipart `NSMutableURLRequest`请求对象

此外还有比如：处理查询的 URL 参数

`AFURLRequestSerialization`是一个协议，它定义了一个方法：

```objective-c
- (nullable NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(nullable id)parameters
                                        error:(NSError * _Nullable __autoreleasing *)error
```

`AFHTTPRequestSerializer`及其子类遵循这个协议。

现在从AFHTTPRequestSerializer这个类入手分析。

# 1.创建普通NSMutableURLRequest请求
```objective-c
//创建一般的NSMutableURLRequest对象，设置HTTPMethod、请求属性、HTTPHeader和处理参数
- (NSMutableURLRequest *)requestWithMethod:(NSString *)method
                                 URLString:(NSString *)URLString
                                parameters:(id)parameters
                                     error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(method);
    NSParameterAssert(URLString);

    NSURL *url = [NSURL URLWithString:URLString];

    NSParameterAssert(url);
    //创建URLRequest、设置请求的方法
    NSMutableURLRequest *mutableRequest = [[NSMutableURLRequest alloc] initWithURL:url];
    mutableRequest.HTTPMethod = method;
    //通过mutableObservedChangedKeyPaths设置NSMutableURLRequest请求属性
    for (NSString *keyPath in AFHTTPRequestSerializerObservedKeyPaths()) {
        if ([self.mutableObservedChangedKeyPaths containsObject:keyPath]) {
            //用KVC的方式，给request设置属性值
            [mutableRequest setValue:[self valueForKeyPath:keyPath] forKey:keyPath];
        }
    }
    //设置http header和参数（拼接到url还是放到http body中）
    mutableRequest = [[self requestBySerializingRequest:mutableRequest withParameters:parameters error:error] mutableCopy];

	return mutableRequest;
}
```

这个方法做了三件事：

1.设置request请求类型`mutableRequest.HTTPMethod = method;`

2.设置request的一些属性。

2.1这里用到了`AFHTTPRequestSerializerObservedKeyPaths()`c函数。

```objective-c
//单例。观察者keyPath集合。需要观察的request属性：allowsCellularAccess、cachePolicy、HTTPShouldHandleCookies、HTTPShouldUsePipelining、networkServiceType、timeoutInterval
static NSArray * AFHTTPRequestSerializerObservedKeyPaths() {
    static NSArray *_AFHTTPRequestSerializerObservedKeyPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _AFHTTPRequestSerializerObservedKeyPaths = @[NSStringFromSelector(@selector(allowsCellularAccess)), NSStringFromSelector(@selector(cachePolicy)), NSStringFromSelector(@selector(HTTPShouldHandleCookies)), NSStringFromSelector(@selector(HTTPShouldUsePipelining)), NSStringFromSelector(@selector(networkServiceType)), NSStringFromSelector(@selector(timeoutInterval))];
    });
    return _AFHTTPRequestSerializerObservedKeyPaths;
}
```

这个函数创建了一个数组单例，里面装的都是`NSURLRequest`的属性。

2.2`mutableObservedChangedKeyPaths `是AFHTTPRequestSerializer类的一个属性，它在`-init`方法中进行了初始化。另外在`-init`方法中还对上面设置的6个与`NSURLRequest`相关的属性添加观察者（KVO）：

```objective-c
    self.mutableObservedChangedKeyPaths = [NSMutableSet set];
    for (NSString *keyPath in AFHTTPRequestSerializerObservedKeyPaths()) {
        if ([self respondsToSelector:NSSelectorFromString(keyPath)]) {
            //为请求的属性添加观察者
            /*
             observer: 观察者对象. 其必须实现方法observeValueForKeyPath:ofObject:change:context:.
             keyPath: 被观察的属性，其不能为nil.
             options: 设定通知观察者时传递的属性值，新值、旧值，通常设置为NSKeyValueObservingOptionNew。
             context: 一些其他的需要传递给观察者的上下文信息，通常设置为nil
             */
            [self addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:AFHTTPRequestSerializerObserverContext];
        }
    }
```

KVO触发的方法，`mutableObservedChangedKeyPaths `用于记录这些属性的变化（由我们自己设置request的属性值）：

```objective-c
//观察者接收通知，通过实现下面的方法，完成对属性改变的响应。将新的属性存储在一个名为 mutableObservedChangedKeyPaths的集合中
//change: 属性值，根据- addObserver: forKeyPath: options: context:的Options设置，给出对应的属性值
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(__unused id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if (context == AFHTTPRequestSerializerObserverContext) {
        if ([change[NSKeyValueChangeNewKey] isEqual:[NSNull null]]) {
            [self.mutableObservedChangedKeyPaths removeObject:keyPath];
        } else {
            [self.mutableObservedChangedKeyPaths addObject:keyPath];
        }
    }
}
```

这些被监听的属性值改变时是这样通知他们的观察者对象的：

```objective-c
/*
 willChangeValueForKey通知观察到的对象，给定属性的值即将更改。在手动实现KVO时，使用此方法通知观察对象，键值即将更改。
 值更改后，必须使用相同的参数调用相应的didChangeValueForKey：
 */
- (void)setAllowsCellularAccess:(BOOL)allowsCellularAccess {
    [self willChangeValueForKey:NSStringFromSelector(@selector(allowsCellularAccess))];
    _allowsCellularAccess = allowsCellularAccess;
    [self didChangeValueForKey:NSStringFromSelector(@selector(allowsCellularAccess))];
}
```

2.3最后用KVC给request设置这些属性值。

`[mutableRequest setValue:[self valueForKeyPath:keyPath] forKey:keyPath];`

3.对网络请求参数进行编码

```objective-c
- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(id)parameters
                                        error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(request);
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    //设置请求头 不会覆盖原有的header
    [self.HTTPRequestHeaders enumerateKeysAndObjectsUsingBlock:^(id field, id value, BOOL * __unused stop) {
        if (![request valueForHTTPHeaderField:field]) {
            [mutableRequest setValue:value forHTTPHeaderField:field];
        }
    }];

    NSString *query = nil;//格式化的请求参数
    if (parameters) {
        //如果有自定义block
        if (self.queryStringSerialization) {
            NSError *serializationError;
            //用自定义block来格式化请求参数
            query = self.queryStringSerialization(request, parameters, &serializationError);

            if (serializationError) {
                if (error) {
                    *error = serializationError;
                }

                return nil;
            }
        } else {
            switch (self.queryStringSerializationStyle) {
                case AFHTTPRequestQueryStringDefaultStyle:
                    //调用 AFQueryStringFromParameters 将参数转换为查询参数
                    query = AFQueryStringFromParameters(parameters);
                    break;
            }
        }
    }
    //将参数 parameters 添加到 URL 或者 HTTP body 中
    //GET HEAD DELETE，参数拼接到url
    if ([self.HTTPMethodsEncodingParametersInURI containsObject:[[request HTTPMethod] uppercaseString]]) {
        if (query && query.length > 0) {
            mutableRequest.URL = [NSURL URLWithString:[[mutableRequest.URL absoluteString] stringByAppendingFormat:mutableRequest.URL.query ? @"&%@" : @"?%@", query]];//根据是否已有查询字符串进行拼接？已有就用‘&’，没有就用‘？’
        }
    }
    //参数添加到httpbody中 ，比如POST PUT
    else {
        if (!query) {
            query = @"";
        }
        if (![mutableRequest valueForHTTPHeaderField:@"Content-Type"]) {
            [mutableRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        }
        [mutableRequest setHTTPBody:[query dataUsingEncoding:self.stringEncoding]];
    }

    return mutableRequest;
}
```

3.1设置请求头。从`self.HTTPRequestHeaders`中拿到header，赋值到请求的request中去，如果原先的header已经存在就不进行设置。

3.2对网络请求参数进行编码。
如果有自定的block来格式化（转码）请求参数就用自定义block。

```objective-c
if (self.queryStringSerialization) {
            NSError *serializationError;
            //用自定义block来格式化请求参数
            query = self.queryStringSerialization(request, parameters, &serializationError);
```

如果没有自定义block来处理就使用AF的转码方式：

```objective-c
//把dictionary参数转换、拼接成字符串参数
/*
 NSDictionary *info = @{@"account":@"zhangsan",@"password":@"123456"};
AFQueryStringFromParameters(info)的结果是：account=zhangsan&password=123456 (没有百分比编码)
 
  NSDictionary *info = @{@"student":@{@"name":@"zhangsan",@"age":@"15"}};
 AFQueryStringFromParameters(info)的结果是：student[name]=zhangsan&student[age]=15 (没有百分比编码)
 */
NSString * AFQueryStringFromParameters(NSDictionary *parameters) {
    NSMutableArray *mutablePairs = [NSMutableArray array];
    for (AFQueryStringPair *pair in AFQueryStringPairsFromDictionary(parameters)) {
        [mutablePairs addObject:[pair URLEncodedStringValue]];
    }
    //拆分数组返回的参数字符串
    return [mutablePairs componentsJoinedByString:@"&"];
}

//网络请求参数拼接处理入口。
NSArray * AFQueryStringPairsFromDictionary(NSDictionary *dictionary) {
    return AFQueryStringPairsFromKeyAndValue(nil, dictionary);
}

//递归处理value。如果当前的 value 是一个集合类型的话，那么它就会不断地递归调用自己。
NSArray * AFQueryStringPairsFromKeyAndValue(NSString *key, id value) {
    NSMutableArray *mutableQueryStringComponents = [NSMutableArray array];
    //排序。根据需要排序的对象的description来进行升序排列，
    //description返回的是NSString，compare:使用的是NSString的compare:方法
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"description" ascending:YES selector:@selector(compare:)];

    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = value;
        // Sort dictionary keys to ensure consistent ordering in query string, which is important when deserializing potentially ambiguous sequences, such as an array of dictionaries
        for (id nestedKey in [dictionary.allKeys sortedArrayUsingDescriptors:@[ sortDescriptor ]]) {
            id nestedValue = dictionary[nestedKey];
            if (nestedValue) {
                [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue((key ? [NSString stringWithFormat:@"%@[%@]", key, nestedKey] : nestedKey), nestedValue)];
            }
        }
    } else if ([value isKindOfClass:[NSArray class]]) {
        NSArray *array = value;
        for (id nestedValue in array) {
            [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue([NSString stringWithFormat:@"%@[]", key], nestedValue)];
        }
    } else if ([value isKindOfClass:[NSSet class]]) {
        NSSet *set = value;
        for (id obj in [set sortedArrayUsingDescriptors:@[ sortDescriptor ]]) {
            [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue(key, obj)];
        }
    } else {
        [mutableQueryStringComponents addObject:[[AFQueryStringPair alloc] initWithField:key value:value]];
    }

    return mutableQueryStringComponents;
}
```

主要是根据value的类型来用`AFQueryStringPairsFromKeyAndValue `这个函数递归处理value参数，直到解析的类型不是array\dictionary\set。

- 这里涉及到一个类`AFQueryStringPair `：

```objective-c
//参数转化的中间模型
 @interface AFQueryStringPair : NSObject
 @property (readwrite, nonatomic, strong) id field;
 @property (readwrite, nonatomic, strong) id value;
 - (instancetype)initWithField:(id)field value:(id)value;
 - (NSString *)URLEncodedStringValue;
 @end

 @implementation AFQueryStringPair
 - (instancetype)initWithField:(id)field value:(id)value {
    self = [super init];
    if (!self) {
        return nil;
    }
    self.field = field;
    self.value = value;
    return self;
}

 //百分号编码后，用"="拼接field value值
 - (NSString *)URLEncodedStringValue {
    if (!self.value || [self.value isEqual:[NSNull null]]) {
        return AFPercentEscapedStringFromString([self.field description]);
    } else {
        return [NSString stringWithFormat:@"%@=%@", AFPercentEscapedStringFromString([self.field description]), AFPercentEscapedStringFromString([self.value description])];
    }
}
@end
```

`AFQueryStringPair`这个类相当于是一个参数转化的中间模型，在`AFQueryStringPairsFromKeyAndValue `函数递归处理的最后：

```objective-c
[mutableQueryStringComponents addObject:[[AFQueryStringPair alloc] initWithField:key value:value]];
```

就是这样把一对field-value值保存起来。再通过`-URLEncodedStringValue `方法对field-value百分比编码、"="拼接。

举个例子理解一下这个参数格式化：

```objective-c
 NSDictionary *info = @{@"account":@"zhangsan",@"password":@"123456"};
AFQueryStringFromParameters(info)的结果是：account=zhangsan&password=123456 (没有百分比编码)
 
  NSDictionary *info = @{@"student":@{@"name":@"zhangsan",@"age":@"15"}};
 AFQueryStringFromParameters(info)的结果是：student[name]=zhangsan&student[age]=15 (没有百分比编码)
```

- 关于参数百分比编码：

根据RFC 3986的规定：URL百分比编码的保留字段分为：

```
1.':'  '#'  '['  ']'  '@'  '?'  '/'
2.'!'  '$'  '&'  '''  '('  ')'  '*'  '+'  ','  ';' '='
```

在对查询字段百分比编码时，'?'和'/'可以不用编码，其他的都要进行编码。下面这段代码结合注释也很好理解，就不过多展开了。

```objective-c
//对字符串进行百分比编码
NSString * AFPercentEscapedStringFromString(NSString *string) {
    //过滤需要编码的字符
    static NSString * const kAFCharactersGeneralDelimitersToEncode = @":#[]@"; // does not include "?" or "/" due to RFC 3986 - Section 3.4
    static NSString * const kAFCharactersSubDelimitersToEncode = @"!$&'()*+,;=";
    //？和/不需要被编码，所以除了？和/之外的字符要从URLQueryAllowedCharacterSet中剔除
    NSMutableCharacterSet * allowedCharacterSet = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowedCharacterSet removeCharactersInString:[kAFCharactersGeneralDelimitersToEncode stringByAppendingString:kAFCharactersSubDelimitersToEncode]];

//    为了处理类似emoji这样的字符串，rangeOfComposedCharacterSequencesForRange 使用了while循环来处理，也就是把字符串按照batchSize分割处理完再拼回。
    static NSUInteger const batchSize = 50;
    NSUInteger index = 0;
    NSMutableString *escaped = @"".mutableCopy;

    while (index < string.length) {
        NSUInteger length = MIN(string.length - index, batchSize);
        NSRange range = NSMakeRange(index, length);

        // To avoid breaking up character sequences such as 👴🏻👮🏽
        //对emoji这类特殊字符的处理。分开一个字符串时保证我们不会分开被称为代理对的东西。
        range = [string rangeOfComposedCharacterSequencesForRange:range];

        NSString *substring = [string substringWithRange:range];
        NSString *encoded = [substring stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];//编码
        [escaped appendString:encoded];

        index += range.length;
    }
	return escaped;
}
```

3.3根据请求类型，将参数字符串添加到 URL 或者 HTTP body 中
如果是GET、HEAD、DELETE，则把请求参数拼接到url后面的。而POST、PUT是把请求参数拼接到http body。

# 2.创建multipart NSMutableURLRequest请求对象

这一部分主要是对上传文件做的一些封装。Multipart是HTTP协议为Web表单新增的上传文件的协议，Content-Type的类型扩充了multipart/form-data用以支持向服务器发送二进制数据。它基于HTTP POST的方法，数据同样是放在body，跟普通POST方法的区别是数据不是key=value形式。更多关于multipart/form-data请求请戳：[HTTP协议之multipart/form-data请求分析](https://my.oschina.net/cnlw/blog/168466)

请求体HTTP Body的格式大致如下：

```objective-c
--boundary //上边界 //“boundary”是一个边界，没有实际的意义，可以用任意字符串来替代
Content-Disposition: form-data; name=xxx; filename=xxx
Content-Type: application/octet-stream
（空一行）
文件内容的二进制数据
--boundary-- //下边界
```

请求体内容分为四个部分:

1.上边界

2.头部,告诉服务器要做数据上传,包含:

a. 服务器的接收字段name=xxx。xxx是负责上传文件脚本中的 字段名,开发的时候,可以咨询后端程序员，不需要自己设定。

b. 文件在服务器中保存的名称filename=xxx。xxx可以自己指定,不一定和本地原本的文件名相同

c. 上传文件的数据类型 application/octet-stream

3.上传文件的数据部分(二进制数据)

4.下边界部分,严格按照字符串格式来设置.

上边界部分和下边界部分的字符串,最后都要转换成二进制数据,和文件部分的二进制数据拼接在一起,作为请求体发送给服务器.
[NSURLConnection笔记-上传文件](http://www.jianshu.com/p/efe496adef04)

要构造Multipart里的数据有三种方式：

> 最简单的方式就是直接拼数据，要发送一个文件，就直接把文件所有内容读取出来，再按上述协议加上头部和分隔符，拼接好数据后扔给NSURLRequest的body就可以发送了，很简单。但这样做是不可用的，因为文件可能很大，这样拼数据把整个文件读进内存，很可能把内存撑爆了。 

> 第二种方法是不把文件读出来，不在内存拼，而是新建一个临时文件，在这个文件上拼接数据，再把文件地址扔给NSURLRequest的bodyStream，这样上传的时候是分片读取这个文件，不会撑爆内存，但这样每次上传都需要新建个临时文件，对这个临时文件的管理也挺麻烦的。

> 第三种方法是构建自己的数据结构，只保存要上传的文件地址，边上传边拼数据，上传是分片的，拼数据也是分片的，拼到文件实体部分时直接从原来的文件分片读取。这方法没上述两种的问题，只是实现起来也没上述两种简单，AFNetworking就是实现这第三种方法，而且还更进一步，除了文件，还可以添加多个其他不同类型的数据，包括NSData，和InputStream。

在Multipart这一部分代码比较长，涉及到几个类和协议，这里先把它们的关系图放出来：

![](http://upload-images.jianshu.io/upload_images/1727123-c9735035d39e31ba.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

## 2.1AFHTTPBodyPart
`AFHTTPBodyPart`实际上做的是对Multipart请求体各部分（初始边界、头部、内容数据实体、结束边界）做拼接和读取的封装。

NSData \ FileUrl \ NSInputStream 类型的数据在`AFHTTPBodyPart`中都转换成NSInputStream。

```objective-c
//根据body的数据类型，NSData\NSURL\NSInputStream转换成输入流并返回
//inputStream值保存了数据实体，没有分隔符和头部
- (NSInputStream *)inputStream {
    if (!_inputStream) {
        if ([self.body isKindOfClass:[NSData class]]) {
            _inputStream = [NSInputStream inputStreamWithData:self.body];
        } else if ([self.body isKindOfClass:[NSURL class]]) {
            _inputStream = [NSInputStream inputStreamWithURL:self.body];
        } else if ([self.body isKindOfClass:[NSInputStream class]]) {
            _inputStream = self.body;
        } else {
            _inputStream = [NSInputStream inputStreamWithData:[NSData data]];
        }
    }
    return _inputStream;
}
```

`_inputStream`只保存了数据实体（body），不包含上下边界和头部信息。

`AFHTTPBodyPart`读取数据是边读边拼接的，用一个状态机来确定现在数据读到哪一部分，依次往后传递进行状态切换。要注意的是，在读取数据实体（body）部分是用流（NSInputStream）来处理的，读之前打开流，读完之后关闭流然后进入下一阶段：

```objective-c
//用状态机切换
- (BOOL)transitionToNextPhase {
    //主线程执行本方法
    if (![[NSThread currentThread] isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self transitionToNextPhase];
        });
        return YES;
    }

    switch (_phase) {
        //读取完初始边界
        case AFEncapsulationBoundaryPhase:
            _phase = AFHeaderPhase;
            break;
        //读取完头部，准备读取body，打开流 准备接受数据
        case AFHeaderPhase:
            [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
            [self.inputStream open];
            _phase = AFBodyPhase;
            break;
        //读取完body，关闭流
        case AFBodyPhase:
            [self.inputStream close];
            _phase = AFFinalBoundaryPhase;
            break;
        //读取完结束边界
        case AFFinalBoundaryPhase:
        default:
            _phase = AFEncapsulationBoundaryPhase;
            break;
    }
    //重置
    _phaseReadOffset = 0;

    return YES;
}
```

结合状态机，读取数据是分块进行的，拼接数据也是分块的，边读边拼接。并且使用`totalNumberOfBytesRead `的局部变量来保存已经读取的字节数，以此来定位要读的数据位置：

```objective-c
//把请求体读到buffer中。边读取边拼接数据
- (NSInteger)read:(uint8_t *)buffer
        maxLength:(NSUInteger)length
{
    NSInteger totalNumberOfBytesRead = 0;

    if (_phase == AFEncapsulationBoundaryPhase) {
        NSData *encapsulationBoundaryData = [([self hasInitialBoundary] ? AFMultipartFormInitialBoundary(self.boundary) : AFMultipartFormEncapsulationBoundary(self.boundary)) dataUsingEncoding:self.stringEncoding];
        totalNumberOfBytesRead += [self readData:encapsulationBoundaryData intoBuffer:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
    }

    if (_phase == AFHeaderPhase) {
        NSData *headersData = [[self stringForHeaders] dataUsingEncoding:self.stringEncoding];
        totalNumberOfBytesRead += [self readData:headersData intoBuffer:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
    }

    if (_phase == AFBodyPhase) {
        NSInteger numberOfBytesRead = 0;

        //读取给定缓冲区中给定的字节数。返回的结果：正数表示读取的字节数。0表示达到缓冲区的结尾。-1表示操作失败;
        numberOfBytesRead = [self.inputStream read:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
        if (numberOfBytesRead == -1) {
            return -1;
        } else {
            totalNumberOfBytesRead += numberOfBytesRead;

            if ([self.inputStream streamStatus] >= NSStreamStatusAtEnd) {
                [self transitionToNextPhase];
            }
        }
    }

    if (_phase == AFFinalBoundaryPhase) {
        NSData *closingBoundaryData = ([self hasFinalBoundary] ? [AFMultipartFormFinalBoundary(self.boundary) dataUsingEncoding:self.stringEncoding] : [NSData data]);
        totalNumberOfBytesRead += [self readData:closingBoundaryData intoBuffer:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
    }

    return totalNumberOfBytesRead;
}

- (NSInteger)readData:(NSData *)data
           intoBuffer:(uint8_t *)buffer
            maxLength:(NSUInteger)length
{
    NSRange range = NSMakeRange((NSUInteger)_phaseReadOffset, MIN([data length] - ((NSUInteger)_phaseReadOffset), length));
    [data getBytes:buffer range:range];

    _phaseReadOffset += range.length;//记录当前阶段已被读取的字节数

    if (((NSUInteger)_phaseReadOffset) >= [data length]) {
        [self transitionToNextPhase];
    }

    return (NSInteger)range.length;
}
```

通过阅读上面这两个方法，很容易猜测，`- read: maxLength:`这个方法会在其他的代码中的某个循环中被调用（主要是数据实体部分的读取拼接是分块进行而不是一次性的）。

## 2.2AFMultipartBodyStream
`AFMultipartBodyStream`继承NSInputStream ，遵循NSStreamDelegate协议。

`AFMultipartBodyStream`封装了整个multipart数据的读取。它有一个NSSArray类型的`HTTPBodyParts`属性，用来保存每一个`AFHTTPBodyPart`对象，所以很直观地就想到了是对多文件上传的封装。

对整个multipart数据的读取，主要是根据读取的位置确定当前读的是哪个`AFHTTPBodyPart`，然后调用`AFHTTPBodyPart`的`- read: maxLength:`读取、拼接数据，最后记录读取的每一个`AFHTTPBodyPart`的数据长度总和。

`AFMultipartBodyStream`重写了NSInputStream的`- read: maxLength:`方法：

```objective-c
//重写方法
- (NSInteger)read:(uint8_t *)buffer
        maxLength:(NSUInteger)length
{
    if ([self streamStatus] == NSStreamStatusClosed) {
        return 0;
    }

    NSInteger totalNumberOfBytesRead = 0;
    //self.numberOfBytesInPacket用于3G网络请求优化，指定每次读取的数据包大小，建议值kAFUploadStream3GSuggestedPacketSize
    //遍历读取数据
    while ((NSUInteger)totalNumberOfBytesRead < MIN(length, self.numberOfBytesInPacket)) {
        //self.currentHTTPBodyPart不存在，或者没有可读的字节（已经读完）
        if (!self.currentHTTPBodyPart || ![self.currentHTTPBodyPart hasBytesAvailable]) {
            //看看还有没有下一个。把下一个请求体赋值给当前请求体，如果下一个是nil就退出循环
            if (!(self.currentHTTPBodyPart = [self.HTTPBodyPartEnumerator nextObject])) {
                break;
            }
        } else {
            //剩余数据长度?
            //这里maxLength是进入AFHTTPBodyPart读取的maxLength
            NSUInteger maxLength = MIN(length, self.numberOfBytesInPacket) - (NSUInteger)totalNumberOfBytesRead;
            //读到buffer中
            NSInteger numberOfBytesRead = [self.currentHTTPBodyPart read:&buffer[totalNumberOfBytesRead] maxLength:maxLength];
            if (numberOfBytesRead == -1) {
                self.streamError = self.currentHTTPBodyPart.inputStream.streamError;
                break;
            } else {
                totalNumberOfBytesRead += numberOfBytesRead;
                //延时用于3G网络请求优化，读取数据延时，建议值kAFUploadStream3GSuggestedDelay
                if (self.delay > 0.0f) {
                    [NSThread sleepForTimeInterval:self.delay];
                }
            }
        }
    }

    return totalNumberOfBytesRead;
}
```

对初始边界和结束边界进行设置，比如多文件上传时设置第一个文件的初始边界，和最后一个文件的结束边界。

除此之外，它还对多文件上传的初始边界和结束边界进行设置。

对于多文件上传的请求体格式：（以多文件+普通文本为例）

```
多文件+普通文本 上传的请求体格式如下：

--boundary\r\n           // 第一个文件参数//上边界，不过也可以写成这样：\r\n--boundary\r\n 
Content-Disposition: form-data; name=xxx; filename=xxx\r\n
Content-Type:image/jpeg\r\n\r\n        
（空一行）        
上传文件的二进制数据部分    
\r\n--boundary\r\n    // 第二个文件参数//上边界 //文件一的下边界可略，在这句之前插入文件一的下边界\r\n--boundary--也可以
Content-Disposition: form-data; name=xxx; filename=xxx\r\n
Content-Type:text/plain\r\n\r\n
（空一行）                
上传文件的二进制数据部分  
\r\n--boundary\r\n    //普通文本参数 //上边界
Content-Disposition: form-data; name="xxx"\r\n\r\n    //name是服务器的接收字段，不需要自己制定
（空一行）     
普通文本二进制数据     
\r\n--boundary--       // 下边界
```

在两个文件之间不需要把上一个文件的结束边界也拼接上去，`\r\n--boundary\r\n`暂且叫做“中间边界”吧。知道这一协议格式之后，那么下面这段代码也很好理解了：

```objective-c
//初始边界和结束边界的设置。多文件上传时设置第一个文件的上边界，和最后一个文件的下边界
- (void)setInitialAndFinalBoundaries {
    if ([self.HTTPBodyParts count] > 0) {
        for (AFHTTPBodyPart *bodyPart in self.HTTPBodyParts) {
            bodyPart.hasInitialBoundary = NO;
            bodyPart.hasFinalBoundary = NO;
        }
        [[self.HTTPBodyParts firstObject] setHasInitialBoundary:YES];
        [[self.HTTPBodyParts lastObject] setHasFinalBoundary:YES];
    }
}
```

由于`AFMultipartBodyStream`继承`NSInputStream` ，遵循`NSStreamDelegate`协议，所以这个类里还重写了很多`NSStream`的方法：

```objective-c
#pragma mark - NSInputStream
//重写方法
- (BOOL)getBuffer:(__unused uint8_t **)buffer
           length:(__unused NSUInteger *)len
{
    return NO;
}

//判断数据是否已经读完了，open状态就是还有数据
- (BOOL)hasBytesAvailable {
    return [self streamStatus] == NSStreamStatusOpen;
}

#pragma mark - NSStream

- (void)open {
    if (self.streamStatus == NSStreamStatusOpen) {
        return;
    }
    self.streamStatus = NSStreamStatusOpen;
    [self setInitialAndFinalBoundaries];
    self.HTTPBodyPartEnumerator = [self.HTTPBodyParts objectEnumerator];
}

- (void)close {
    self.streamStatus = NSStreamStatusClosed;
}

- (id)propertyForKey:(__unused NSString *)key {
    return nil;
}

- (BOOL)setProperty:(__unused id)property
             forKey:(__unused NSString *)key
{
    return NO;
}

//设置runloop为了让NSStreamDelegate收到stream状态改变回调。不过这里NSURLRequest没有用到delegate处理状态改变就写成空实现了。
- (void)scheduleInRunLoop:(__unused NSRunLoop *)aRunLoop
                  forMode:(__unused NSString *)mode
{}

- (void)removeFromRunLoop:(__unused NSRunLoop *)aRunLoop
                  forMode:(__unused NSString *)mode
{}
```

## 2.3AFStreamingMultipartFormData
`AFStreamingMultipartFormData`遵循`AFMultipartFormData`协议。是对`AFMultipartBodyStream`更上一层的封装。

`AFStreamingMultipartFormData`管理了一个`AFMultipartBodyStream`类型的属性`bodyStream`。调用`AFStreamingMultipartFormData`对象的几种append方法就可以添加 FileURL/NSData/NSInputStream几种不同类型的数据，`AFStreamingMultipartFormData`内部把这些数据转换成一个个`AFHTTPBodyPart `，并添加到`AFMultipartBodyStream`里（用`AFMultipartBodyStream`的HTTPBodyParts数组把它们一个个保存起来）。最后把`AFMultipartBodyStream`赋给原来`NSMutableURLRequest`的bodyStream：

```objective-c
//通过本地文件url获取数据
- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name
                     fileName:(NSString *)fileName
                     mimeType:(NSString *)mimeType
                        error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(fileURL);
    NSParameterAssert(name);
    NSParameterAssert(fileName);
    NSParameterAssert(mimeType);

    //url不是fileurl
    if (![fileURL isFileURL]) {
        NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey: NSLocalizedStringFromTable(@"Expected URL to be a file URL", @"AFNetworking", nil)};
        if (error) {
            *error = [[NSError alloc] initWithDomain:AFURLRequestSerializationErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }
        return NO;
    }
    //路径不可达
    else if ([fileURL checkResourceIsReachableAndReturnError:error] == NO) {
        NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey: NSLocalizedStringFromTable(@"File URL not reachable.", @"AFNetworking", nil)};
        if (error) {
            *error = [[NSError alloc] initWithDomain:AFURLRequestSerializationErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }
        return NO;
    }
    //获取本地文件属性。获取不到就不添加
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:error];
    if (!fileAttributes) {
        return NO;
    }
    //设置 http请求体的header
    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", name, fileName] forKey:@"Content-Disposition"];
    [mutableHeaders setValue:mimeType forKey:@"Content-Type"];

    //生成AFHTTPBodyPart对象，拼接到AFMultipartBodyStream对象数组中
    AFHTTPBodyPart *bodyPart = [[AFHTTPBodyPart alloc] init];
    bodyPart.stringEncoding = self.stringEncoding;
    bodyPart.headers = mutableHeaders;
    bodyPart.boundary = self.boundary;
    bodyPart.body = fileURL;
    bodyPart.bodyContentLength = [fileAttributes[NSFileSize] unsignedLongLongValue];//获取文件大小
    [self.bodyStream appendHTTPBodyPart:bodyPart];

    return YES;
}
```

```
//把数据跟请求建立联系的核心方法
//数据最终通过setHTTPBodyStream:传递给request
- (NSMutableURLRequest *)requestByFinalizingMultipartFormData {
    if ([self.bodyStream isEmpty]) {
        return self.request;
    }

    // Reset the initial and final boundaries to ensure correct Content-Length
    [self.bodyStream setInitialAndFinalBoundaries];
    //将输入流作为请求体
    [self.request setHTTPBodyStream:self.bodyStream];
    //设置请求头
    [self.request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", self.boundary] forHTTPHeaderField:@"Content-Type"];
    [self.request setValue:[NSString stringWithFormat:@"%llu", [self.bodyStream contentLength]] forHTTPHeaderField:@"Content-Length"];

    return self.request;
}
```

NSURLSession发送请求时会读取这个`bodyStream `，在读取数据是会调用bodyStream的`- read: maxLength:`方法，也即`AFMultipartBodyStream `重写的`- read: maxLength:`方法，不断读取之前append的AFHTTPBodyPart数据直到读完。

## 2.4创建multipart NSMutableURLRequest请求对象

```objective-c
//multipart传数据
//GET和HEAD不能用multipart传数据，一般都是用POST
- (NSMutableURLRequest *)multipartFormRequestWithMethod:(NSString *)method
                                              URLString:(NSString *)URLString
                                             parameters:(NSDictionary *)parameters
                              constructingBodyWithBlock:(void (^)(id <AFMultipartFormData> formData))block
                                                  error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(method);
    NSParameterAssert(![method isEqualToString:@"GET"] && ![method isEqualToString:@"HEAD"]);

    NSMutableURLRequest *mutableRequest = [self requestWithMethod:method URLString:URLString parameters:nil error:error];

    __block AFStreamingMultipartFormData *formData = [[AFStreamingMultipartFormData alloc] initWithURLRequest:mutableRequest stringEncoding:NSUTF8StringEncoding];

    if (parameters) {
        //把请求参数也放在multipart里
        for (AFQueryStringPair *pair in AFQueryStringPairsFromDictionary(parameters)) {
            NSData *data = nil;
            if ([pair.value isKindOfClass:[NSData class]]) {
                data = pair.value;
            } else if ([pair.value isEqual:[NSNull null]]) {
                data = [NSData data];
            } else {
                data = [[pair.value description] dataUsingEncoding:self.stringEncoding];
            }
            if (data) {
                [formData appendPartWithFormData:data name:[pair.field description]];
            }
        }
    }

    //执行对外暴露的block接口。
//比如可以在block里拼接其他一些文件数据。调用AFStreamingMultipartFormData的几个append方法
    if (block) {
        block(formData);
    }
    //把stream跟request建立联系的核心方法
    //数据最终通过setHTTPBodyStream:传递给request
    return [formData requestByFinalizingMultipartFormData];
}
```

## 2.5其他
在`AFMultipartBodyStream`中有以下这么几个方法看得不太懂，不知道为什么要这样写：

```objective-c
#pragma mark - Undocumented CFReadStream Bridged Methods
- (void)_scheduleInCFRunLoop:(__unused CFRunLoopRef)aRunLoop                     
                     forMode:(__unused CFStringRef)aMode
{}

- (void)_unscheduleFromCFRunLoop:(__unused CFRunLoopRef)aRunLoop
                         forMode:(__unused CFStringRef)aMode
{}

- (BOOL)_setCFClientFlags:(__unused CFOptionFlags)inFlags                
                 callback:(__unused CFReadStreamClientCallBack)inCallback                  
                  context:(__unused CFStreamClientContext *)inContext {    
    return NO;
}
```

[AFNetworking2.0源码解析<二>](http://blog.cnbang.net/tech/2371/) 中提到：

> NSURLRequest的setHTTPBodyStream接受的是一个NSInputStream*参数，那我们要自定义inputStream的话，创建一个NSInputStream的子类传给它是不是就可以了？实际上不行，这样做后用NSURLRequest发出请求会导致crash，提示[xx _scheduleInCFRunLoop:forMode:]: unrecognized selector。
这是因为NSURLRequest实际上接受的不是NSInputStream对象，而是CoreFoundation的CFReadStreamRef对象，因为CFReadStreamRef和NSInputStream是toll-free bridged，可以自由转换，但CFReadStreamRef会用到CFStreamScheduleWithRunLoop这个方法，当它调用到这个方法时，object-c的toll-free bridging机制会调用object-c对象NSInputStream的相应函数，这里就调用到了_scheduleInCFRunLoop:forMode:，若不实现这个方法就会crash。

# 3.其他
AFJSONRequestSerializer和AFPropertyListRequestSerializer这两个AFHTTPRequestSerializer的子类的实现都比较简单，主要是对这个协议方法进行重写。具体代码阅读都没什么难度，就不展开讲了。

```objective-c
- (nullable NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(nullable id)parameters
                                        error:(NSError * _Nullable __autoreleasing *)error NS_SWIFT_NOTHROW;
```


详细源码注释[请戳github](https://github.com/huixinHu/AFNetworking-)

参考文章：

[AFNetworking到底做了什么](http://www.jianshu.com/p/856f0e26279d)

[AFNetworking2.0源码解析<二>](http://blog.cnbang.net/tech/2371/)

http://www.cnblogs.com/chenxianming/p/5674652.html

[通读AFN②--AFN的上传和下载功能分析、SessionTask及相应的session代理方法的使用细节](http://www.cnblogs.com/Mike-zh/p/5172389.html)