声明UI控件属性一般情况下形如`@property (weak, nonatomic) UIImageView *imgView;`property参数为weak。

```objective-c
 self.imgView = [[UIImageView alloc]init];
 [self.view addSubview:self.imgView];
```

 在ARC环境下是不允许的，因为没有强指针指向的对象，一创建出来马上就被释放掉。

那如果`@property (strong, nonatomic) UIImageView *imgView;`把UI控件的property参数改为strong呢？这种情况下，就不会出现一创建就被释放的问题，但为什么声明UI控件属性都要用weak参数呢？

### 使用weak参数的原因
1. viewController强引用self.view(UIView)的根视图`@property(null_resettable, nonatomic,strong) UIView *view;`

2. UIView 强引用NSArray subviews`@property(nonatomic,readonly,copy) NSArray<__kindof UIView *> *subviews;copy也是强引用`

3. subviews强引用子view（`-addSubview:`方法api文档里面说会对子view建立强引用）

4. 如果把UI控件的property参数设为strong，那么viewcontroller会对UI控件进行强引用。

 ![](http://upload-images.jianshu.io/upload_images/1727123-364c6d03f2752e16.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
 
UI控件的property参数如果设为strong，那么此时控件就被两个对象强引用了，如果其中一个对象忘记释放，那么控件对象就不能被释放掉。
(不过好像用strong问题也不大，如果控制器被销毁了，vc强引用释放，subviews的强引用也会被销毁。不过还是用strong就有点多余了)

### IBOutlet连出来的视图属性为什么可以被设置成weak
使用storyboard(xib不可以)创建的vc，会有一个叫`_topLevelObjectsToKeepAliveFromStoryboard`的私有数组强引用所有top level对象，top level对象强引用所有子对象，那么vc久没必要再强引用top level对象的子对象了，所以这时outlet声明成weak也可以。

苹果文档：
> The top-level objects typically include only the windows, menu bars, and custom controller objects that you add to the nib file.

### weak和assign
既然不能使用strong，那么如果UI控件的property参数使用assign的话又会怎样呢？

```objective-c
@property (nonatomic ,assign)UIButton *btn;

self.btn = [[UIButton alloc]initWithFrame:CGRectMake(100, 100, 100, 100)];
[self.btn setBackgroundColor:[UIColor yellowColor]];
[self.view addSubview:self.btn];
```

打开僵尸对象检测，运行代码会报僵尸对象的错误。在ARC环境下，这个按钮同样是一创建出来就被释放掉，但为什么会报错？

**原因：**

weak指针指向的对象（在堆内存）被销毁之后，weak指针就自动做清空操作（赋值为nil。指向0地址？）

assign指针指向的对象被销毁之后，指针指向原来堆内存中的那个地址，访问了一块坏的内存  造成野指针错误（僵尸对象）

如果是在MRC环境下，把weak换为assign则不会报错。

### UI控件的代理delegate属性要声明为weak
因为vc对控件强引用，如果delegate声明为strong，UI控件代理一般指向vc本身，那么就会造成循环引用。
不过非UI控件的delegate的属性声明是weak还是strong就要视情况而定。