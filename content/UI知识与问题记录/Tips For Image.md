## imageNamed & imageWithContentsOfFile

有无缓存这点区别应该基本是个人都知道的。。。

通过time profile。这两者在第一次加载时，imageNamed的耗时是imageWithContentsOfFile的10倍..但是之后再次调用由imageNamed加载的资源，耗时就相当短了..

## 判断图片的格式类型

根据图片的后缀名去判断图片的类型是不严谨的。要通过判断文件或数据的**头几个字节**，和对应的图片格式标准进行对比。[通过文件头标识判断图片格式](https://www.cnblogs.com/mamamia/p/8608848.html)

SDWebImage中判断图片格式的方法：

```objective-c
+ (SDImageFormat)sd_imageFormatForImageData:(nullable NSData *)data {
    if (!data) {
        return SDImageFormatUndefined;
    }

    uint8_t c;
    [data getBytes:&c length:1];
    switch (c) {
        case 0xFF:
            return SDImageFormatJPEG;
        case 0x89:
            return SDImageFormatPNG;
        case 0x47:
            return SDImageFormatGIF;
        case 0x49:
        case 0x4D:
            return SDImageFormatTIFF;
        case 0x52:
            // R as RIFF for WEBP
            if (data.length < 12) {
                return SDImageFormatUndefined;
            }

            NSString *testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 12)] encoding:NSASCIIStringEncoding];
            if ([testString hasPrefix:@"RIFF"] && [testString hasSuffix:@"WEBP"]) {
                return SDImageFormatWebP;
            }
    }
    return SDImageFormatUndefined;
}
```

YYImage中判断的原理大致上差不多，只不过类型更加细分。

## 加载逻辑路径@2x、@3x图

![](../image/Snip20180531_3.png)

ps:XCode9之后，黄色文件夹(group)就不是逻辑路径了。

- 用`imageNamed:`方法。

 ```objective-c
[UIImage imageNamed:@"personal_data_top_animation_1"];//不需要指明是@2x还是@3x图
```
可以加载到逻辑路径中的资源，也可以加载到Assets.xcassets中的资源，而且会根据设备自动匹配@2x和@3x图片。

- 用`imageWithContentsOfFile:`方法。

```objective-c
NSString *path = [[NSBundle mainBundle] pathForResource:@"personal_data_top_animation_1@2x" ofType:@"png"];
[UIImage imageWithContentsOfFile:path];
```
从mainBundle获取图片路径时，要把'@2x'、'@3x'带上，不然获取不到路径。

除了黄色文件夹，还有一种蓝色文件夹（folder），它不参与编译，要引用其中的文件需要全路径。比如如果截图中的top文件夹是蓝色的，那么应该这样获取资源：

```objective-c
NSString *path = [[NSBundle mainBundle] pathForResource:@"top/personal_data_top_animation_1@2x" ofType:@"png"];
[UIImage imageWithContentsOfFile:path];
```