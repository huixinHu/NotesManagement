Quartz 2D是一个二维绘图引擎，同时支持iOS和Mac OSX系统（跨平台，纯C 语言的）。包含在Core Graphics框架中。

Quartz 2D绘图步骤：

1. 获取 **图形上下文 **对象
2. 向**图形上下文**对象中添加**路径**
3. 渲染，把**图形上下文**中的图形绘制到对应的设备上

### 图形上下文GraphicsContext
是一个CGContextRef类型的数据。图形上下文中主要包含如下信息：

1. 绘图路径
2. 绘图状态（颜色、线宽、样式、旋转、缩放、平移、图片裁剪区域等）
3. 输出目标（绘制到什么地方去？UIView、图片、pdf、打印机、Bitmap或者显示器的窗口上等）

Quartz2D提供了以下几种类型的图形上下文：Bitmap Graphics Context、PDF Graphics Context、Window Graphics Context、Layer Graphics Context(UI控件)、Printer Graphics Context

### 用quartz2D自定义View
新建一个继承自UIView的类。然后实现```-(void)drawRect:(CGRect)rect```方法，在这个方法中:1.取得跟当前view相关联的图形上下文,2.绘制相应的图形内容,3.渲染显示到view上面

#### 关于drawRect:
- 当要向UIView上绘图的时候, 必须重写UIView的drawRect:方法, 然后在这个方法中进行绘图
- 参数rect就是绘图区域（当前view）的bounds
- 为什么向当前view中绘制图形, 必须在drawRect:方法中进行?
因为在drawRect:方法中才能取得跟view相关联的图形上下文
- 为什么只有在drawRect:方法中才能获取当前view的图形上下文呢？
系统在调用drawRect:方法之前已经帮我们创建好了一个与当前view相关的图形上下文了, 然后才调用的drawRect:方法, 所以在drawRect:方法中, 我们就可以成功获取当前view的图形上下文了。
- drawRect:方法在什么时候被调用？
 1. 当view第一次显示到屏幕上时（加到UIWindow上显示出来）（系统调用，调用一次），另外它是在Controller的loadView,viewDidLoad 两方法之后掉用的.所以不用担心在控制器中,这些View的drawRect就开始画了.
 2. 重绘的时候:调用view的setNeedsDisplay（重绘指定区域）或者setNeedsDisplayInRect:（重绘某一块区域）时
 3. 不能手动去调用这个方法, 因为可能无法正确的获取绘图上下文（无法保证系统已经帮我们创建好了图形上下文）
- 获取图形上下文：```CGContextRef ctx = UIGraphicsGetCurrentContext();```

那如果要在drawRect以外的地方获取图形上下文怎么办？那就只能自己创建位图上下文了。`UIGraphicsBeginImageContextWithOptions`

### 绘制基本图形
两种绘图方式：

- 方式一：直接调用Quartz2D 的 API 
代码量稍大，但功能全面
- 方式二：调用 UIKit 框架封装好的 API 
代码相对简单，但只对部分 Quartz2D 的 API 做了封装（没封装的调用Quartz2D 原生 API）

```objective-c
#pragma mark 调用 UIKit 框架封装好的 API 进行绘图
- (void)demo3{
    //1.绘制矩形
    CGContextRef ctx = UIGraphicsGetCurrentContext();    
    UIBezierPath *bezierPath = [UIBezierPath bezierPathWithRect:CGRectMake(30, 30, 200, 200)];    
    //添加路径
    CGContextAddPath(ctx, bezierPath.CGPath);//第二个参数是CGPathRef类型
    CGContextDrawPath(ctx, kCGPathStroke);
    
    //不使用图形上下文对象
    UIBezierPath *path2 = [UIBezierPath bezierPathWithRect:CGRectMake(30, 250, 100, 100)];
    [path2 stroke];
    //    [path2 fill];
    
    //2.绘制线段
    UIBezierPath *path3 = [UIBezierPath bezierPath];
    //添加子路径
    [path3 moveToPoint:CGPointMake(300 , 30)];
    [path3 addLineToPoint:CGPointMake(300 , 130)];
    [path3 stroke];
}

#pragma mark 调用 Quartz2D 的 API 进行绘图
//绘制线段、三角形
- (void)demo1{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    //画一条线
    CGContextMoveToPoint(ctx, 50, 50);    
    CGContextAddLineToPoint(ctx, 160, 160);
    
    //绘制三角形，封闭路径
    CGContextMoveToPoint(ctx, 50, 200);
    CGContextAddLineToPoint(ctx, 110, 200);
    CGContextAddLineToPoint(ctx, 80, 250);
    CGContextClosePath(ctx);//关闭路径、起点终点连线
    //或者：    CGContextAddLineToPoint(ctx, 50, 200);

    //绘制矩形
    CGContextAddRect(ctx, CGRectMake(30, 30, 200, 200));
    
    CGContextStrokePath(ctx);//不填充路径
}
```
可以看出，使用UIKit框架-UIBezierPath对象，更为简单。UIKit框架是对Quartz2D的部分封装，在api命名上也有部分相似之处。UIBezierPath对象可以独立使用,  无需手动获取“图形上下文”对象。当然要获取上下文来使用也是可以的，使用方式会有所不同，步骤：

1. 获取“图形上下文”对象
2. 创建 UIBezierPath对象
3. 向 UIBezierPath对象中绘制图形
4. 把 UIBezierPath对象添加到上下文中```CGContextAddPath(ctx, bezierPath.CGPath);```
5. 把上下文对象渲染到设备上

```objective-c
其他图形：
//弧线    
    //参数 ：圆心 半径 起始弧度 结束弧度（画到，而不是画了） 顺逆时针,顺yes逆no。三点钟方向为0弧度
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(150, 150) radius:50 startAngle:0 endAngle:M_PI_4 clockwise:YES];    
    [path stroke];
    //如果是扇形，弧线+一个点 闭合路径实现

//椭圆    
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(50, 50, 200, 100)];
    [path stroke];

//带圆角的矩形
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(100, 100, 100, 100) cornerRadius:15];//如果圆角半径 = 正方形边长的一半，画出来的是圆形
    [path fill];
```

### 绘图状态
举两个例子，其余看api。颜色、线宽、转折点样式、头尾部样式

- 图形颜色

```objective-c
 //C 语言的方式设置颜色      
     CGContextSetRGBFillColor(ctx, 200/255.0, 100/255.0, 50/255.0, 1.0);
     //CGContextSetRGBStrokeColor(CGContextRef __nullable c,CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha)
 
 //OC 的方式设置颜色
     // 设置空心图形的线条颜色
      [[UIColor redColor] setStroke];     
     // 设置实心图形的填充颜色
     [[UIColor redColor] setFill];     
     // 统一设置"空心图形" 和 "实心图形"的颜色
     [[UIColor redColor] set];
```

- 线宽

```objective-c
//C语言方式
    CGContextSetLineWidth(ctx, 20);
//OC方式
lineWidth属性
```

**矩阵操作**旋转、缩放、平移。让绘制到上下文中的所有路径一起发生变化

缩放```void CGContextScaleCTM(CGContextRef c, CGFloat sx, CGFloat sy)```

旋转```void CGContextRotateCTM(CGContextRef c, CGFloat angle)```

平移```void CGContextTranslateCTM(CGContextRef c, CGFloat tx, CGFloat ty)```

获取图形上下文之后，先进行矩阵操作，然后再绘制路径。view能够显示图形是因为它上面的图层（layer）。矩阵操作是对整个layer来进行的（？）

### 渲染方式
- 空心

```objective-c
CGContextStrokePath(ctx);//c语言
[path stroke];//oc
```

- 实心填充

```objective-c
CGContextFillPath(ctx);
[path fill];
```

另外，CGContextDrawPath通过指定绘图模式来绘制路径

```objective-c
void CGContextDrawPath(CGContextRef __nullable c,
    CGPathDrawingMode mode)
Draws the current path using the provided drawing mode.:
kCGPathFill, kCGPathEOFill, kCGPathStroke, kCGPathFillStroke, or kCGPathEOFillStroke.
```

填充一个路径的时候，路径里面的子路径都是独立填充的。假如是重叠的路径，决定一个点是否被填充，有两种规则：(UIKit BezierPath好像没有)

1. nonzero winding number rule（非零绕数规则），假如一个点被从左到右跨过，计数器+1，从右到左跨过，计数器-1，最后，如果结果是0，那么不填充，如果是非零，那么填充。
CGContextDrawPath默认非零绕数填充模式。所以画一个圆环可以这样：

 ```objective-c
    CGContextRefctx= UIGraphicsGetCurrentContext();
    UIBezierPath*path = [UIBezierPathbezierPathWithArcCenter:CGPointMake(150, 150) radius:100 startAngle:0 endAngle:M_PI* 2 clockwise:1];
    UIBezierPath*path1 = [UIBezierPathbezierPathWithArcCenter:CGPointMake(150, 150) radius:50 startAngle:0 endAngle:M_PI* 2 clockwise:0];
    CGContextAddPath(ctx, path1.CGPath);
    CGContextAddPath(ctx, path.CGPath);    
    CGContextDrawPath(ctx, kCGPathFill);
```

2. even-odd rule（奇偶规则），假如一个点被覆盖过了奇数次，那么要被填充，被覆盖过偶数次则不填充，和方向没有关系
```CGContextDrawPath(ctx, kCGPathEOFill);```

### 图形上下文栈
每一个“图形上下文”对象都包含一个“栈”结构，这个栈结构用来存储当前图形上下文的**状态**信息。（每个图形上下文对象中都包含：1>“图形状态”; 2> 路径信息; 3> 输出目标）
前面绘图的时候修改了上下文，后面绘图的时候要再次使用被修改前的上下文对象。这时需要图形上下文栈。

[这里有篇讲得比较详细的博文](http://www.cnblogs.com/wendingding/p/3782489.html)

```objective-c
将当前 图形上下文 中的“绘图状态”信息保存到“栈”中
void CGContextSaveGState(CGContextRef c)

将栈顶的“绘图状态”出栈, 替换掉当前的“图形上下文”中的“绘图状态”
void CGContextRestoreGState(CGContextRef c)
```

### CGMutablePathRef绘图路径
使用步骤：1.获取图形上下文 2.创建路径 3.把绘图信息添加到路径里边（CGMutablePathRef这个路径用来保存绘图信息） 4.把路径添加到上下文中。

下面使用CGMutablePathRef来绘制线段的代码和上面绘制线段的代码是等价的：

```objective-c
- (void)drawRect:(CGRect)rect {
    // Drawing code
    //1.获取上下文对象
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    //2.创建路径
    CGMutablePathRef pathM = CGPathCreateMutable();

    CGPathMoveToPoint(pathM, NULL, 100, 100);
    CGPathAddLineToPoint(pathM, NULL, 50, 200);    
    //3.把路径添加到上下文对象中
    CGContextAddPath(ctx, pathM);
    //4.渲染
    CGContextStrokePath(ctx);
    //释放内存
//    CGPathRelease(pathM);    
    CFRelease(pathM);
```
直接使用绘图路径的好处，一个path代表一个路径。在绘制多个图形时使用path就易于区分了。

**内存管理**

凡是遇到retain 、copy 、create 创建出的对象,都需要进行release。但CGPathCreateMutable()不是OC 方法, 所以不是调用某个对象的release方法。

```CGPathCreateMutable();``` 释放这个路径对象，可以通过：

1. CGPathRelease(path);   （CGXxxxxCreate方法对应的就有CGXxxxxRelease。）
2. CFRelease(任何类型);可以释放任何类型。

### 绘制文字&图片
drawAtPoint:、drawInRect: 直接绘制到图形上下文中。

- 绘制文字
 通过 UIKit 框架来绘制

 ```objective-c
 - (void)drawRect:(CGRect)rect {
     NSString *str = @"hello"; 
     NSDictionary *attrs = @{NSForegroundColorAttributeName :[UIColor redColor],NSFontAttributeName : [UIFont systemFontOfSize:20] }; 
     //1.绘制到指定的点
     [str drawAtPoint:CGPointMake(30, 50) withAttributes:attrs];
     //2.绘制到一个指定区域
     [str drawInRect:CGRectMake(100, 200, 50, 250) withAttributes:attrs];
}
```

- 绘制图片

```objective-c
 - (void)drawRect:(CGRect)rect {
UIImage *img = [UIImage imageNamed:@"table"];
[img drawAtPoint:CGPointMake(50, 50)];//绘制到指定点
[img drawInRect:rect];//绘制到指定区域，以拉伸方式
[img drawAsPatternInRect:rect];//绘制到指定区域，平铺方式
}
```

### 裁剪图片
#### 在自定义view中绘制裁剪后的图片
```void CGContextClip(CGContextRef c)```将当前上下所绘制的路径裁剪出来（超出这个裁剪区域的都不能显示）

步骤：

1.获取上下文对象 2.创建要裁剪的路径 3.把路径添加到图形上下文对象中 4.执行裁剪 5.加载图片 绘制图片

**指定范围执行裁剪的方法一定要在绘制之前调用。**

```objective-c
- (void)drawRect:(CGRect)rect {
    //1.获取上下文对象
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    //2.创建要裁剪的路径
    UIBezierPath * path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(50, 50) radius:50 startAngle:0 endAngle:2*M_PI clockwise:YES];    
    //3.把路径添加到图形上下文对象中
    CGContextAddPath(ctx, path.CGPath);    
    //4.执行裁剪
    CGContextClip(ctx);   
    //5.加载图片 绘制图片
    UIImage * image = [UIImage imageNamed:@"me"];    
    [image drawAtPoint:CGPointZero];   
}
```

#### 直接在vc中裁剪图片
```objective-c
@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *imageView;//sb中设置了约束，是个正方形
@end

@implementation ViewController
- (IBAction)clipBtnClick:(id)sender
{
    //1.加载要裁剪的图片
    UIImage * image = [UIImage imageNamed:@"table"];    
    //2.开启一个图形上下文 (bitmap  大小和要裁剪的图片大小一样)
    UIGraphicsBeginImageContextWithOptions(image.size, NO, 0.0);    
    //3.获取图形上下文
    CGContextRef ctx = UIGraphicsGetCurrentContext();    
    //4.创建路径
    CGPoint centerP = CGPointMake(image.size.width/2, image.size.height/2);
    CGFloat radius = MIN(image.size.width, image.size.height)/2;    
    UIBezierPath * path = [UIBezierPath bezierPathWithArcCenter:centerP radius:radius startAngle:0 endAngle:2 * M_PI clockwise:YES];    
    //5.把路径添加到图形上下文中
    CGContextAddPath(ctx, path.CGPath);    
    //6.执行裁剪
    CGContextClip(ctx);    
    //7.绘制图片
    [image drawAtPoint:CGPointZero];    
    //8.获取图片
    UIImage * getImage = UIGraphicsGetImageFromCurrentImageContext();    
    //8.1 结束图形上下文
    UIGraphicsEndImageContext();
    
    //8.2 裁剪图片(要裁剪的原始图片不是正方形，bitmap图形上下文和原始图片大小一样，即第8步获得的图片大小（矩形）。后面当它被赋值到正方形ImageView时就会变形)    
    CGFloat x = 0;
    CGFloat y = (image.size.height - 2 * radius)/2;    
    CGFloat w = 2 * radius;
    CGFloat h = w;
    
    //获取屏幕的缩放比
    CGFloat scale = [UIScreen mainScreen].scale;
    x *= scale;
    y *= scale;    
    w *= scale;
    h *= scale;
    
    CGImageRef imageRef = CGImageCreateWithImageInRect(getImage.CGImage, CGRectMake(x, y, w, h));
    //获取裁剪后的图片
    getImage = [UIImage imageWithCGImage:imageRef];   
    CGImageRelease(imageRef);//create创建的要release 
    self.imageView.image = getImage;
    
    //9.保存    
    //9.1 保存到相册
    UIImageWriteToSavedPhotosAlbum(getImage, self, @selector(image:didFinishSavingWithError:contextInfo:), @"hello word");
    //9.2 保存到沙盒
    NSString * documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString * fileName = [documents stringByAppendingPathComponent:@"001.png"];    
    //把UIimage--->NSData
    NSData * imageData = UIImagePNGRepresentation(getImage);    
    [imageData writeToFile:fileName atomically:YES];    
    NSLog(@"%@",fileName);
}
//保存相册方法
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    NSLog(@"保存完毕 %@",contextInfo);
}
```

- 执行裁剪CGContextClip(ctx);需要获得图形上下文，因为vc中没有drawRect: ，要获得图形上下文，要先用 ```void     UIGraphicsBeginImageContextWithOptions(CGSize size, BOOL opaque, CGFloat scale)```函数开启一个bitmap图形上下文。然后再用```UIGraphicsGetCurrentContext();```获取
- ```UIGraphicsGetImageFromCurrentImageContext();```从当前bitmap图形上下文的的内容中获取图片
- 用完图形上下文要关上```UIGraphicsEndImageContext();```
- 函数```void UIImageWriteToSavedPhotosAlbum(UIImage *image, __nullable id completionTarget, __nullable SEL completionSelector, void * __nullable contextInfo) ```用来把图片保存到手机相册。
第三个参数必须使用```- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;```这个方法。
第四个参数 传递给第三个参数的那个方法的数据
