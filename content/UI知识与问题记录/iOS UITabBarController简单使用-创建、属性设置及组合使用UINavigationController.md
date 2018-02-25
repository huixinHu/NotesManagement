UITabBarController,在这个视图控制器中有一个UITabBar控件，用户通过点击tabBar进行视图切换。

![](http://upload-images.jianshu.io/upload_images/1727123-9e564d4026ef4cb5.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

我们知道在UIViewController内部有一个视图，一旦创建了UIViewController之后默认就会显示这个视图，但是UITabBarController本身并不会显示任何视图，如果要显示视图则必须设置其viewControllers属性（它默认显示viewControllers[0]）。这个属性是一个数组，它维护了所有UITabBarController的子控制器。为了尽可能减少视图之间的耦合，所有的UITabBarController的子控制器的相关标题、图标等信息均由子控制器自己控制，UITabBarController仅仅作为一个容器存在。

![](http://upload-images.jianshu.io/upload_images/1727123-e8a59ad04320c546.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

这个工具条称为UITabBar ，如果UITabBarController有N个子控制器,那么UITabBar内部就会有N 个UITabBarItem作为子控件与之对应。
UITabBarItem⾥面显⽰什么内容,由对应子控制器的tabBarItem属性来决定。

```
vc1.tabBarItem.title = @"首页";
vc1.tabBarItem.image = [[UIImage imageNamed:@"Home_normal"]  imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
```

## 1.使用storyboard混合代码创建、设置
看到网上很多代码都是使用纯代码创建UITabBarController组合使用UINavigationController的，不过个人觉得storyboard可以方便界面设计可视化，因为项目只有个人在负责，所以一开始使用的是这种混合的方法。

1）工程新建之后在storyboard中删掉ViewController，选择TabBarController拖到storyboard中，此时会看到一个TabBar Sense 对应两个初始场景Item1、Item2

![TabBarController](http://upload-images.jianshu.io/upload_images/1727123-ec049efe4b112db7.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

记得要把TabBarController设置为初始视图控制器并绑定ViewController文件

![设置为初始视图控制器](http://upload-images.jianshu.io/upload_images/1727123-b579b3396a589115.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

![绑定ViewController文件](http://upload-images.jianshu.io/upload_images/1727123-65cacfb5c234ca71.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

2）Delete删掉场景Item1、Item2。拖拽NavigationController控制器到storyboard。

![](http://upload-images.jianshu.io/upload_images/1727123-c457846f3556b2db.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

连接TabBarController和NavigationController。从TabBarController按住鼠标右键拖动到NavigationController上，释放鼠标弹出Segue对话框，选择Relationship Segue中的view controllers。完成连接。
这只是完成了第一个标签的设计，其余标签如法炮制。

3）设置TabBar item 标签栏的文字、图标

- 可以选中其中一个NavigationController的tabbar item，如图所示，设置item的内容，图片。但是这种设置方法都默认为系统的默认样式，如果需要对文字图片有特殊设置需求，需要使用代码进行设置。

![设置TabBar item 标签栏的文字、图标](http://upload-images.jianshu.io/upload_images/1727123-1da644ec3534525f.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

- 使用代码设置TabBar item 标签栏的文字、图标

 **在TabBarController绑定的对应ViewController.m文件中：**

 1.设置UITabBarItem字体颜色、大小(selected\normal状态下)
 ![改变UITabBarItem字体颜色、大小](http://upload-images.jianshu.io/upload_images/1727123-5849c99d6555b4bc.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 ```objective-c
    [[UITabBarItem appearance] setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor colorWithRed:102.0/255 green:102.0/255 blue:102.0/255 alpha:1.0],NSForegroundColorAttributeName, [UIFont systemFontOfSize:10.0],NSFontAttributeName,nil] forState:UIControlStateNormal];

    [[UITabBarItem appearance] setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor colorWithRed:255.0/255 green:73.0/255 blue:87.0/255 alpha:1.0],NSForegroundColorAttributeName, [UIFont fontWithName:@"Helvetica" size:12.0f],NSFontAttributeName,nil] forState:UIControlStateSelected];
```

 这是设置**全局所有**UITabBarItem字体的颜色、大小,如果要设置单个item字体的颜色大小（局部个性化，用当前tabbar item修改）：

 ```objective-c
UITabBarItem *item0 = [self.tabBar.items objectAtIndex:0];
[item0 setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor colorWithRed:102.0/255 green:102.0/255 blue:102.0/255 alpha:1.0],NSForegroundColorAttributeName, [UIFont systemFontOfSize:10.0],NSFontAttributeName,nil] forState:UIControlStateNormal];
```
 这里要注意，设置字体的话要选择支持中文的字体，不然修改字号是无效的。

 2.设置UITabBarItem文字内容、选中和非选中图片
 
 ![文字内容、选中和非选中图片](http://upload-images.jianshu.io/upload_images/1727123-0294e18d9201ebb6.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 ```objective-c   
  UITabBarItem *item0 = [self.tabBar.items objectAtIndex:0];
  //一开始这里使用[self.tabBarController.tabBar.items  objectAtIndex:0];出错，因为本身就是tabBarController其实直接获取tabBar就可以了
 //如果是在tabBarController的子控制器中通过self.tabBarController或者self.parentViewController，可以得到其父视图控制器，也就是tabBarController本身
  item0.image = [[UIImage imageNamed:@"Home_normal"]  imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
  item0.selectedImage = [[UIImage imageNamed:@"Home_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
  item0.title = @"首页";
    
  UITabBarItem *item1 = [self.tabBar.items objectAtIndex:1];
  item1.image = [[UIImage imageNamed:@"Shopping_normal"]  imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
  item1.selectedImage = [[UIImage imageNamed:@"Shopping_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
  item1.title = @"进货单";
 ```     
 - 每个视图控制器都有一个tabBarController属性，通过它可以访问所在的UITabBarController，而且对于UITabBarController的直接子视图其tabBarController等于parentViewController。
 - 每个视图控制器都有一个tabBarItem属性，通过它控制视图在UITabBarController的tabBar中的显示信息。

iOS7中新增了方法：
 
```objective-c
 - (instancetype)initWithTitle:(nullableNSString *)title image:(nullableUIImage *)image selectedImage:(nullableUIImage *)selectedImage
 NS_AVAILABLE_IOS(7_0);`
```

上面的代码可以改为：

```objective-c
    item0  = [[UITabBarItem alloc] initWithTitle:@"首页"
                                           image:[[UIImage imageNamed:@"Home_normal"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                                   selectedImage:[[UIImage imageNamed:@"Home_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]];
	vc1.tabBarItem = item;//创建完标签之后指定为某一个视图控制器的标签
```

同时在相同的API中，有这么一个注释：
>  /* The unselected image is autogenerated from the image argument. The selected image is autogenerated from the selectedImage if provided and the image argument otherwise.To prevent system coloring, provide images with UIImageRenderingModeAlwaysOriginal (see UIImage.h) */
意思是为了防止系统渲染，必须以UIImageRenderingModeAlwaysOriginal提供图片。若不以这种形式，那么提供的图片显示时会发生渲染错误的问题。

 **UIImageRenderingMode属性**
 
 - UIImageRenderingModeAutomatic // 根据图片的使用环境和所处的绘图上下文自动调整渲染模式。
 - UIImageRenderingModeAlwaysOriginal // 始终绘制图片原始状态，不使用Tint Color。
 - UIImageRenderingModeAlwaysTemplate // 始终根据Tint Color绘制图片，忽略图片的颜色信息。
UIImageRenderingMode属性的默认值是UIImageRenderingModeAutomatic，UIBarButtonitem图标在这种情况下被渲染为蓝色而不是图标本身的颜色。设置为UIImageRenderingModeAlwaysOriginal才会保持图片原始状态。

![](http://upload-images.jianshu.io/upload_images/1727123-20de4cb95d5903f3.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 3.设置UITabBarController“背景颜色”
 
 - 方法一
 
 ```
 self.tabBar.barTintColor = [UIColor greenColor];
 ```
 
 这里有一个要注意的是：在storyboard要勾掉TabBar 的Translucent，不然的话设置的背景颜色会有色差（navigation bar也有同样的问题存在）。
 ![](http://upload-images.jianshu.io/upload_images/1727123-d20789ed1ca2bdc4.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 ![要勾掉Translucent](http://upload-images.jianshu.io/upload_images/1727123-5437539d22ba1a1c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 ![产生色差](http://upload-images.jianshu.io/upload_images/1727123-2b780dc6c49455d2.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
 
 - 方法二 
 
 除了使用代码，设置背景颜色也可以在上图红线下面的Bar Tint进行设置,同样要去掉Translucent。
 
 - 方法三
 
 ```
 [[UITabBar appearance]setBackgroundColor:[UIColor blueColor]];
 [UITabBar appearance].translucent = NO;
 ```
 
 - 方法四

 在tabbar上添加一个有颜色的view
 
 ```
 UIView *view = [[UIView alloc]init];
 view.backgroundColor = [UIColor redColor];
 view.frame = self.tabBar.bounds;
 [[UITabBar appearance]insertSubview:view atIndex:0]
 ```
 
 - 方法五

 使用背景图片
 ```
 [[UITabBar appearance]setBackgroundImage:[UIImage imageNamed:@"xxx"]];
 [UITabBar appearance].translucent = NO;
 ```

关于barTintColor的一点扩展：[如何在iOS 7中设置barTintColor实现类似网易和 Facebook 的 navigationBar 效果](http://www.cocoachina.com/industry/20131024/7233.html)

所有的设置代码都是写在与UITabBarController绑定的ViewController.m文件里面，当然也可以在tabbar的各个子控制器中进行以上属性的设置。如果属性设置是写在子控制器的viewDidLoad里面的话，那么app加载之后就只有第一个页面的tabbar item的图标可以显示出来（因为其他页面还没有加载嘛..自然也就无法调用它们的viewdidload啦..），只有当切换到其他页面的时候，哪个页面的tabbar item的图标才会显示出来。

demo:

```objective-c
#import <UIKit/UIKit.h>
@interface ViewController : UITabBarController

@end

#import "ViewController.h"
@interface ViewController ()

@end
@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
//    NSArray *arr = [self childViewControllers];
//    UINavigationController *anav = [arr objectAtIndex:0];
//    UITabBarItem *item0 = [anav.tabBarController.tabBar.items objectAtIndex:0];
//    item0.image = [[UIImage imageNamed:@"Home_normal"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
//    item0.selectedImage = [[UIImage imageNamed:@"Home_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
//    item0.title = @"首页";
//    
//    UINavigationController *bnav = [arr objectAtIndex:1];
//    UITabBarItem *item1 = [bnav.tabBarController.tabBar.items objectAtIndex:1];
//    item1.image = [[UIImage imageNamed:@"Home_normal"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
//    item1.selectedImage = [[UIImage imageNamed:@"Home_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
//    item1.title = @"首页";
//    
//    UITabBarItem *item2 = [bnav.tabBarController.tabBar.items objectAtIndex:0];
//    item2.image = [[UIImage imageNamed:@"Shopping_normal"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
//    item2.selectedImage = [[UIImage imageNamed:@"Shopping_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
//    item2.title = @"进货";
    [[UITabBarItem appearance] setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor colorWithRed:102.0/255 green:102.0/255 blue:102.0/255 alpha:1.0],NSForegroundColorAttributeName, [UIFont systemFontOfSize:10.0],NSFontAttributeName,nil] forState:UIControlStateNormal];
    [[UITabBarItem appearance] setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor colorWithRed:255.0/255 green:73.0/255 blue:87.0/255 alpha:1.0],NSForegroundColorAttributeName, [UIFont systemFontOfSize:10.0],NSFontAttributeName,nil] forState:UIControlStateSelected];
    
    UITabBarItem *item0 = [self.tabBar.items objectAtIndex:0];
    item0.image = [[UIImage imageNamed:@"Home_normal"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    item0.selectedImage = [[UIImage imageNamed:@"Home_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    item0.title = @"首页";
    
    UITabBarItem *item1 = [self.tabBar.items objectAtIndex:1];
    item1.image = [[UIImage imageNamed:@"Shopping_normal"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    item1.selectedImage = [[UIImage imageNamed:@"Shopping_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    item1.title = @"进货单";

    item0  = [[UITabBarItem alloc] initWithTitle:@"首页"
                                           image:[[UIImage imageNamed:@"Home_normal"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                                   selectedImage:[[UIImage imageNamed:@"Home_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]];
//    self.tabBar.barTintColor = [UIColor blueColor];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
```

## 2.使用纯代码创建、设置

使用步骤：

1. 初始化UITabBarController
2. 设置UIWindow的rootViewController为UITabBarController
3. 创建相应的子控制器（viewcontrollers）(子视图，新建自己需要的UIViewController或者UITableViewController等等，如果需要组合使用UINavigationController，可以将这些视图作为UINavigationController的根视图，使用`initWithRootViewController:`) [戳这里](http://www.jianshu.com/p/11a66e1a3b10)
4. 把子控制器添加到UITabBarController

在Application的中编码

```objective-c
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.window = [[UIWindow alloc]initWithFrame:[[UIScreen mainScreen]bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    
    //初始化一个tabBar控制器
    UITabBarController *tb = [[UITabBarController alloc]init];
    //设置UIWindow的rootViewController为UITabBarController
    self.window.rootViewController = tb;
    
    //创建相应的子控制器
    UIViewController *vc1 = [[UIViewController alloc]init];
    vc1.view.backgroundColor = [UIColor greenColor];
    vc1.tabBarItem.title = @"首页";
    vc1.tabBarItem.image = [[UIImage imageNamed:@"Home_normal"]  imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    vc1.tabBarItem.selectedImage = [[UIImage imageNamed:@"Home_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    
    UIViewController *vc2 = [[UIViewController alloc]init];
    vc2.view.backgroundColor = [UIColor blueColor];
    vc2.tabBarItem.title = @"分类";
    vc2.tabBarItem.image = [[UIImage imageNamed:@"List_normal"]  imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    vc2.tabBarItem.selectedImage = [[UIImage imageNamed:@"List_selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    
    [[UITabBarItem appearance] setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor colorWithRed:102.0/255 green:102.0/255 blue:102.0/255 alpha:1.0],NSForegroundColorAttributeName, [UIFont systemFontOfSize:10.0],NSFontAttributeName,nil] forState:UIControlStateNormal];
    
    [[UITabBarItem appearance] setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor colorWithRed:255.0/255 green:73.0/255 blue:87.0/255 alpha:1.0],NSForegroundColorAttributeName, [UIFont systemFontOfSize:10.0],NSFontAttributeName,nil] forState:UIControlStateSelected];
    
    //把子控制器添加到UITabBarController
    //[tb addChildViewController:c1];
    //[tb addChildViewController:c2];
    //或者
    tb.viewControllers = @[vc1,vc2];
    [self.window makeKeyAndVisible];
    return YES;   
}
```

实现效果：

![](http://upload-images.jianshu.io/upload_images/1727123-9f9f4d06413394dd.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

![](http://upload-images.jianshu.io/upload_images/1727123-3fa5d12e35220212.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

[这里](http://www.cnblogs.com/kenshincui/p/3940746.html) 也有另一种创建方法可以参考，不过思路上都是相似的。

## 3.UITabBarController生命周期
[这里](http://www.cnblogs.com/wendingding/p/3775636.html) 有一篇讲UITabBarController生命周期的博文。总结一下大概就是：

1. 把子控制器都添加给TabBarController管理，当程序启动时它只会加载第一个添加的控制器的view
2. 切换到第二个界面。先把第一个界面的view移开，再把新的view添加上去，但是第一个view只是被移开没有被销毁
3. 重新切换到第一个界面，第一个的控制器直接viewWillAppear，没有执行viewDidLoad证明了第2点中第一个view移除后并没有被销毁（因为它的控制器还存在，有一个强引用引用着它），且第二个界面的view移除后也没有被销毁。无论怎么切换，控制器和view都不会被销毁。

**UINavigationController和UITabBarController一个通过栈来管理，一个通过普通的数组来进行管理。**

## 4.原生tabbar的隐藏

TabBar嵌套Nav时，主界面tabbar正常显示，进行Push的时候隐藏TabBar，pop回来又正常显示。

- 方法一：设置hidesBottomBarWhenPushed属性为YES

1. 在vc1 push到下一个vc2时,在vc1中：

 ```objective-c
//使用storyboard用identifier获取Controller
    UITableViewController *v2 = [self.storyboard instantiateViewControllerWithIdentifier:@"v2"];
//或者 UITableViewController *v2 =[[UITableViewController alloc]init];
    v2.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:v2 animated:YES];
```

2. storyboard中拖线push，在prepareForSegue函数中：

 ```objective-c
-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    [segue.destinationViewController setHidesBottomBarWhenPushed:YES];
}
```

 hidesBottomBarWhenPushed属性是对设置的该vc生效的（如果是对self设置就是本vc开始生效，对别的vc设置就是从该vc开始生效），并且会**一直传递到后面的vc也生效**。
 
 不过如果往下第N级需要显示tabbar，就不能用`hidesBottomBarWhenPushed = NO;`把他显示出来。但可以用这种方法单独处理每一级。

 ```objective-c
//使用storyboard用identifier获取Controller
    UITableViewController *v2 = [self.storyboard instantiateViewControllerWithIdentifier:@"v2"];
//或者 UITableViewController *v2 =[[UITableViewController alloc]init];
    v2.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:v2 animated:YES];
    v2.hidesBottomBarWhenPushed = NO;
```

- 方法二

 storyboard,在 ViewController 的设置面板中把 Hide Bottom Bar on Push 属性勾选上，从该vc开始生效。
 
 ![](http://upload-images.jianshu.io/upload_images/1727123-bf94aaebb24cdafe.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

- 方法三
 使用`self.tabBarController.tabBar.hidden = YES;`不过会有个很怪异的现象。在storyboard里对tabbar的translucent属性取消勾选，push的时候底部会有黑边。