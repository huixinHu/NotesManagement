AF中**对接收响应的过程**进行序列化，这涉及到`AFURLResponseSerialization`模块。将请求返回的数据解析成对应的格式。而这个模块使用在 `AFURLSessionManager`
也就是核心类中。

# 1.模块结构
**协议：**

```objective-c
@protocol AFURLResponseSerialization <NSObject, NSSecureCoding, NSCopying>
```

该协议只有一个必须实现的方法

```objective-c
- (nullable id)responseObjectForResponse:(nullable NSURLResponse *)response
                           data:(nullable NSData *)data
                          error:(NSError * _Nullable __autoreleasing *)error
```

**根类：**

`AFHTTPResponseSerializer`遵循`AFURLResponseSerialization `协议。

**子类：**

`AFJSONResponseSerializer`、`AFXMLParserResponseSerializer`、`AFXMLDocumentResponseSerializer`、`AFPropertyListResponseSerializer`、`AFImageResponseSerializer`、`AFCompoundResponseSerializer`，即所有子类都遵循`AFURLResponseSerialization `协议。

# 2.AFHTTPResponseSerializer
这是这个模块中最基本的类。

- 初始化

 ```objective-c
 + (instancetype)serializer {
    return [[self alloc] init];
}

 - (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    self.acceptableStatusCodes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)];//200-299的HTTP状态码。NSIndexSet是一个有序的，唯一的，无符号整数的集合。
    self.acceptableContentTypes = nil;//没有对接收的内容类型加以限制
    return self;
}
```

 属性`acceptableContentTypes `和` acceptableStatusCodes`是在初始化时给定默认值的，我们也可以自己去定义。不在接受范围内的状态码和内容类型会在数据解析时发生错误。
 
 设置了可接受的http status code是200-299，因为只有这些状态码表示获得了有效的响应。
 
 另外，没有对可接受的MIME type进行设置（交给子类来做）。在老版本的AF中，还有`stringEncoding `，规定utf8数据格式。

- 验证响应和数据的有效性

 ```objective-c
//验证响应和数据的有效性（验证MIMEType和status code）。子类可添加其他特定域的检查。
 - (BOOL)validateResponse:(NSHTTPURLResponse *)response
                    data:(NSData *)data
                   error:(NSError * __autoreleasing *)error
{
    BOOL responseIsValid = YES;//response是否合法
    NSError *validationError = nil;
    //response是否存在和类型判断，如果response为空或者不是NSHTTPURLResponse类型，responseIsValid=YES!
    if (response && [response isKindOfClass:[NSHTTPURLResponse class]]) {
        //根据在初始化方法中初始化的属性 acceptableContentTypes 和 acceptableStatusCodes 来判断当前响应是否有效
        //1.response的内容类型不对（MIMEType）
        if (self.acceptableContentTypes && ![self.acceptableContentTypes containsObject:[response MIMEType]] &&
            !([response MIMEType] == nil && [data length] == 0)) {
            //数据解析失败
            if ([data length] > 0 && [response URL]) {
                //NSLocalizedDescriptionKey是NSError头文件中预定义的键，标识错误的本地化描述.可以通过NSError的localizedDescription方法获得对应的值信息
                //NSURLErrorFailingURLErrorKey相应的值是包含导致加载失败的URL的NSURL。 此键仅存在于NSURLErrorDomain中。
                //生成错误信息字典。会返回unacceptable content-type的信息，并将错误信息记录在了mutableUserInfo中
                NSMutableDictionary *mutableUserInfo = [@{
                                                          NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedStringFromTable(@"Request failed: unacceptable content-type: %@", @"AFNetworking", nil), [response MIMEType]],
                                                          NSURLErrorFailingURLErrorKey:[response URL],                                                          AFNetworkingOperationFailingURLResponseErrorKey: response,
                                                        } mutableCopy];
                if (data) {                    mutableUserInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] = data;
                }
                //+errorWithDomain: code: userInfo:创建和初始化NSError对象
                //NSErrorDomain错误域 - 这可以是预定义的NSError域之一，也可以是描述自定义域的任意字符串。 域名不能为空。
                //收到的内容数据具有未知内容编码（解析数据出错）。NSURLErrorCannotDecodeContentData = -1016，NSError错误码
                //出现错误时通过AFErrorWithUnderlyingError函数生成本地格式化的错误
                validationError = AFErrorWithUnderlyingError([NSError errorWithDomain:AFURLResponseSerializationErrorDomain code:NSURLErrorCannotDecodeContentData userInfo:mutableUserInfo], validationError);
            }

            responseIsValid = NO;
        }
        //2.状态码无效
        if (self.acceptableStatusCodes && ![self.acceptableStatusCodes containsIndex:(NSUInteger)response.statusCode] && [response URL]) {
            //-localizedStringForStatusCode:根据状态码获取本地化文本内容
            NSMutableDictionary *mutableUserInfo = [@{
                                               NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedStringFromTable(@"Request failed: %@ (%ld)", @"AFNetworking", nil), [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], (long)response.statusCode],
                                               NSURLErrorFailingURLErrorKey:[response URL],                                               AFNetworkingOperationFailingURLResponseErrorKey: response,
                                       } mutableCopy];
            if (data) {                mutableUserInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] = data;
            }
            //收到从服务器来的错误数据 NSURLErrorBadServerResponse = -1011,NSError错误码
            validationError = AFErrorWithUnderlyingError([NSError errorWithDomain:AFURLResponseSerializationErrorDomain code:NSURLErrorBadServerResponse userInfo:mutableUserInfo], validationError);
            responseIsValid = NO;
        }
    }
    if (error && !responseIsValid) {
        *error = validationError;
    }
    return responseIsValid;
}
/*
 1.如果content-type不满足，那么产生的validationError就是Domain为AFURLResponseSerializationErrorDomain，code为NSURLErrorCannotDecodeContentData。
如果MIME type不满足，，那么产生的validationError就是Domain为AFURLResponseSerializationErrorDomain，code为NSURLErrorBadServerResponse。
 2.方法中，有可能会出现两个错误，在self.acceptableContentTypes和self.acceptableStatusCodes这两个判断中，如果都出现错误怎么办呢？
 这就用到了NSUnderlyingErrorKey 这个字段，它表示一个优先的错误，value为NSError对象。
 */
```

 1.根据初始化中的属性`acceptableContentTypes `和` acceptableStatusCodes`判断响应是否有效。
 
 2.content-type不对，返回unacceptable content-type的信息，并将错误信息记录在了`mutableUserInfo`中。MIME type不对，处理相似，这里不展开。
这个记录了错误信息的字典，系统提供的KEY值：
 
 ![](http://upload-images.jianshu.io/upload_images/1727123-7e52971d01d3f19b.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
 
 ![](http://upload-images.jianshu.io/upload_images/1727123-c58c5b8cc27035e4.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
 
 不过也可以自定义KEY值，比如AF中就自定义了`AFNetworkingOperationFailingURLResponseErrorKey`和`AFNetworkingOperationFailingURLResponseDataErrorKey`。

 3.出现错误时通过`AFErrorWithUnderlyingError`函数生成本地格式化的错误。
 
 3.1.如果content-type不满足，那么产生的`validationError`就是Domain为`AFURLResponseSerializationErrorDomain`，code为`NSURLErrorCannotDecodeContentData`的自定义NSError。
 
 3.2.如果MIME type不满足，那么产生的`validationError`就是Domain为`AFURLResponseSerializationErrorDomain`，code为`NSURLErrorBadServerResponse`的自定义NSError。
 
 关于`NSError`:[NSError详解 NSError错误code对照表 自定义NSError](http://blog.csdn.net/hdfqq188816190/article/details/52754943)

 4.如果content type和MIMEtype同时出错，这就用到了`NSUnderlyingErrorKey`这个字段，它表示一个优先的错误，value为NSError对象。

 具体看下面这个函数：
 
 ```objective-c
//生成本地格式化的错误。填充错误信息，一些处理过程中产生的错误信息填充到我们需要返回给用户的自定义错误中
static NSError * AFErrorWithUnderlyingError(NSError *error, NSError *underlyingError) {
    //NSUnderlyingErrorKey表示优先错误
    if (!error) {
        return underlyingError;
    }

    if (!underlyingError || error.userInfo[NSUnderlyingErrorKey]) {
        return error;
    }

    NSMutableDictionary *mutableUserInfo = [error.userInfo mutableCopy];
    mutableUserInfo[NSUnderlyingErrorKey] = underlyingError;

    return [[NSError alloc] initWithDomain:error.domain code:error.code userInfo:mutableUserInfo];
}
```
在两者都出错的情况下，那么UnderlyingError就是content type error。

- 协议的实现

 1.AFURLResponseSerialization协议：

 ```objective-c
//从与指定响应相关联的数据中decode得到的响应对象。
 - (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing *)error{
    //调用验证方法，返回data
    [self validateResponse:(NSHTTPURLResponse *)response data:data error:error];
    return data;
}
```

 把验证方法调用完之后就返回data，没有其他实现了。

 2.NSSecureCoding、NSCopying协议：一些归档和自定义copy的方法，比较常规的写法，不做说明了。

# 3.AFJSONResponseSerializer
可接受的数据类型：`application/json`，`text/json`，`text/javascript`。

- 协议的实现

 ```objective-c
 - (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing *)error
{
    //验证MIMEType和status code
    if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
        //error为空或者 错误、优先错误匹配error code和domain（在这里是content type类型的错误）
        if (!error || AFErrorOrUnderlyingErrorHasCodeInDomain(*error, NSURLErrorCannotDecodeContentData, AFURLResponseSerializationErrorDomain)) {
            return nil;
        }
    }

    // Workaround for behavior of Rails to return a single space for `head :ok` (a workaround for a bug in Safari), which is not interpreted as valid input by NSJSONSerialization.
    // See https://github.com/rails/rails/issues/1742
    //数据是否是一个空格
    BOOL isSpace = [data isEqualToData:[NSData dataWithBytes:" " length:1]];
    //如果数据为空或者是空格，就不json解析
    if (data.length == 0 || isSpace) {
        return nil;
    }
    
    NSError *serializationError = nil;
    //json解析。NSJSON只支持解析UTF8编码的数据
    id responseObject = [NSJSONSerialization JSONObjectWithData:data options:self.readingOptions error:&serializationError];

    if (!responseObject)
    {
        if (error) {
            //用json解析的error去填充错误信息
            *error = AFErrorWithUnderlyingError(serializationError, *error);
        }
        return nil;
    }
    //是否要从响应的JSON数据中删除带有“NSNull”值的键
    if (self.removesKeysWithNullValues) {
        return AFJSONObjectByRemovingKeysWithNullValues(responseObject, self.readingOptions);
    }

    return responseObject;
}
```

 1.验证响应
 
 验证失败。在没有error 或者 错误中的code是`NSURLErrorCannotDecodeContentData`（即content type不匹配）的情况下，是不能解析数据的，就返回nil。用到的函数：

 ```objective-c
// 检测错误或者优先错误中是否匹配code和domain
static BOOL AFErrorOrUnderlyingErrorHasCodeInDomain(NSError *error, NSInteger code, NSString *domain) {
    //判断错误域和传过来的域名是否一致，错误code是否一致
    if ([error.domain isEqualToString:domain] && error.code == code) {
        return YES;
    } else if (error.userInfo[NSUnderlyingErrorKey]) {//如果NSUnderlyingErrorKey对应有值，就再进行判断
        return AFErrorOrUnderlyingErrorHasCodeInDomain(error.userInfo[NSUnderlyingErrorKey], code, domain);
    }

    return NO;
}
```

 2.处理返回的数据中只有空格的情况
 
 如果数据为空或者只有一个空格，就不解析。

 3.解析JSON
 
 `readingOptions`属性设置json的读取选项。这里的默认值是`NSJSONReadingMutableContainers `
```
typedef NS_OPTIONS(NSUInteger, NSJSONReadingOptions) {
    //返回可变容器，NSMutableDictionary或NSMutableArray
    NSJSONReadingMutableContainers = (1UL << 0), 
    //返回的JSON对象中字符串的值为NSMutableString
    NSJSONReadingMutableLeaves = (1UL << 1),
    //允许JSON字符串最外层既不是NSArray也不是NSDictionary，但必须是有效的JSON Fragment。例如使用这个选项可以解析 @“123” 这样的字符串。
    NSJSONReadingAllowFragments = (1UL << 2)
} NS_ENUM_AVAILABLE(10_7, 5_0);
```

 [传送门- JSON解析 NSJSONReadingMutableContainers的作用](http://blog.csdn.net/agonie201218/article/details/52350132)

 4.是否要从响应的JSON数据中删除带有“NSNull”值的键
用到的函数：主要通过递归的手段来实现的。
 
 ```objective-c
//从响应的JSON数据中删除带有“NSNull”值的键
static id AFJSONObjectByRemovingKeysWithNullValues(id JSONObject, NSJSONReadingOptions readingOptions) {
    //数组
    if ([JSONObject isKindOfClass:[NSArray class]]) {
        NSMutableArray *mutableArray = [NSMutableArray arrayWithCapacity:[(NSArray *)JSONObject count]];
        //遍历数组，通过递归的手段清空数组内的null
        for (id value in (NSArray *)JSONObject) {
            [mutableArray addObject:AFJSONObjectByRemovingKeysWithNullValues(value, readingOptions)];
        }
        //按位与操作，解析类型是否NSJSONReadingMutableContainers（mutableArray或者mutabledictionary）
        return (readingOptions & NSJSONReadingMutableContainers) ? mutableArray : [NSArray arrayWithArray:mutableArray];
    }
    //字典
    else if ([JSONObject isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *mutableDictionary = [NSMutableDictionary dictionaryWithDictionary:JSONObject];
        for (id <NSCopying> key in [(NSDictionary *)JSONObject allKeys]) {
            id value = (NSDictionary *)JSONObject[key];
            if (!value || [value isEqual:[NSNull null]]) {
                [mutableDictionary removeObjectForKey:key];
            } else if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]]) {
                mutableDictionary[key] = AFJSONObjectByRemovingKeysWithNullValues(value, readingOptions);
            }
        }

        return (readingOptions & NSJSONReadingMutableContainers) ? mutableDictionary : [NSDictionary dictionaryWithDictionary:mutableDictionary];
    }

    return JSONObject;
}
```

# 4.AFXMLParserResponseSerializer、AFXMLDocumentResponseSerializer、AFPropertyListResponseSerializer
`AFXMLParserResponseSerializer`用来解析XML数据，支持的ContentType：application/xml、text/xml。

`AFXMLDocumentResponseSerializer `同上，但这个类只能在mac os x上使用。
`AFPropertyListResponseSerializer `用来解析plist数据，支持的ContentType：application/x-plist。

这三个子类的实现和上面JSON子类的实现差不多，就不具体展开了。

# 5.AFImageResponseSerializer
用于验证和解码图像响应。
 
```objective-c
- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing *)error
{
    //验证MIME type和status code
    if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
        if (!error || AFErrorOrUnderlyingErrorHasCodeInDomain(*error, NSURLErrorCannotDecodeContentData, AFURLResponseSerializationErrorDomain)) {
            return nil;
        }
    }
    //图片解压。宏判断是那种设备，进行对应的图片解压处理
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH
    if (self.automaticallyInflatesResponseImage) {//是否对响应的图片进行自动处理
        return AFInflatedImageFromResponseWithDataAtScale((NSHTTPURLResponse *)response, data, self.imageScale);
    } else {
        return AFImageWithDataAtScale(data, self.imageScale);
    }
#else
    // Ensure that the image is set to it's correct pixel width and height
    NSBitmapImageRep *bitimage = [[NSBitmapImageRep alloc] initWithData:data];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize([bitimage pixelsWide], [bitimage pixelsHigh])];
    [image addRepresentation:bitimage];

    return image;
#endif

    return nil;
}
```

在这里用到了几个方法，写在了UIImage分类`UIImage (AFNetworkingSafeImageLoading)`里面。下面来看一下分类中的这几个方法：

1.把NSData安全地转换为UIImage。

```objective-c
+ (UIImage *)af_safeImageWithData:(NSData *)data {
    UIImage* image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageLock = [[NSLock alloc] init];
    });
    
    [imageLock lock];//上锁
    image = [UIImage imageWithData:data];
    [imageLock unlock];//开锁
    return image;
}
```

当我们读写一个数据的时候，由于数据还可能被别人读写，这就有可能出现不安全的情况，为了解决这个问题，就使用了“锁”。如果对线程锁比较熟悉的话就容易理解了，简单说呢，就是在写数据前先上锁，那么别人就无法使用这块数据了，直到你执行完数据操作、解锁。

2.私有函数，按照scale对图片进行伸缩处理

```objective-c
//返回一个按照scale收缩的图片
static UIImage * AFImageWithDataAtScale(NSData *data, CGFloat scale) {
    UIImage *image = [UIImage af_safeImageWithData:data];
    if (image.images) {//gif图不需要伸缩
        return image;
    }    
    return [[UIImage alloc] initWithCGImage:[image CGImage] scale:scale orientation:image.imageOrientation];
}
```

关于image.images：这个属性第一次接触，大致看了一下，常见的应用是用来生成一个gif效果。在gif图中表示这个Gif包含了多少张图片。其余用法还没有深入研究。

3.根据响应结果和scale返回一张图片.完成图像解压工作

```objective-c
static UIImage * AFInflatedImageFromResponseWithDataAtScale(NSHTTPURLResponse *response, NSData *data, CGFloat scale)
```

这个函数实现很长，用到了CoreGraphics上的一些东西，主要完成iOS、TV、Watch设备下的图像解压工作。关于图像解压的目的，我在[这篇文章](http://blog.csdn.net/diamondld/article/details/46917741)中读到这么一段话：

> 当我们调用UIImage的方法imageWithData:方法把数据转成UIImage对象后，其实这时UIImage对象还没准备好需要渲染到屏幕的数据，现在的网络图像PNG和JPG都是压缩格式，需要把它们解压转成bitmap后才能渲染到屏幕上，如果不做任何处理，当你把UIImage赋给UIImageView，在渲染之前底层会判断到UIImage对象未解压，没有bitmap数据，这时会在主线程对图片进行解压操作，再渲染到屏幕上。这个解压操作是比较耗时的，如果任由它在主线程做，可能会导致速度慢UI卡顿的问题。
> 
> AFImageResponseSerializer除了把返回数据解析成UIImage外，还会把图像数据解压，这个处理是在子线程（AFNetworking专用的一条线程，详见AFURLConnectionOperation），处理后上层使用返回的UIImage在主线程渲染时就不需要做解压这步操作，主线程减轻了负担，减少了UI卡顿问题。
>
>  具体实现上在AFInflatedImageFromResponseWithDataAtScale里，创建一个画布，把UIImage画在画布上，再把这个画布保存成UIImage返回给上层。只有JPG和PNG才会尝试去做解压操作，期间如果解压失败，或者遇到CMKY颜色格式的jpg，或者图像太大(解压后的bitmap太占内存，一个像素3-4字节，搞不好内存就爆掉了)，就直接返回未解压的图像。
> 
> 另外在代码里看到iOS才需要这样手动解压，MacOS上已经有封装好的对象NSBitmapImageRep可以做这个事。

# 6.AFCompoundResponseSerializer
这是一个对复合类型的响应进行处理的子类。

```objective-c
- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing *)error
{
    //遍历数组，只要是属于AFHTTPResponseSerializer及其子类的类型，就执行相应的响应操作。
    for (id <AFURLResponseSerialization> serializer in self.responseSerializers) {
        if (![serializer isKindOfClass:[AFHTTPResponseSerializer class]]) {
            continue;
        }

        NSError *serializerError = nil;
        id responseObject = [serializer responseObjectForResponse:response data:data error:&serializerError];
        if (responseObject) {
            if (error) {
                *error = AFErrorWithUnderlyingError(serializerError, *error);
            }

            return responseObject;
        }
    }
    //以上类型都不是，就执行默认响应操作。
    return [super responseObjectForResponse:response data:data error:error];//调用父类方法
}
```

`responseSerializers`属性，这个数组中装着多种序列化类型，比如上面讲到的JSON、XML等等。

遍历数组，只要是属于AFHTTPResponseSerializer及其子类的类型，就执行相应的响应操作。如果以上类型都不是，就执行默认的响应。

详细源码注释[请戳github](https://github.com/huixinHu/AFNetworking-)

参考文章

[AFNetworking源码阅读（五）](http://www.cnblogs.com/polobymulberry/p/5170093.html)

[AFNetworking2.0源码解析AFURLResponseSerialization](http://blog.csdn.net/diamondld/article/details/46917741)