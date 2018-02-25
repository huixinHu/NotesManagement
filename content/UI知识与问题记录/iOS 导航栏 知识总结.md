一点说明：本文中“导航控制器”区别于“视图控制器”存在

***

# 1.UINavigationController
[UINavigationController官方文档](https://developer.apple.com/library/ios/documentation/UIKit/Reference/UINavigationController_Class/)

`UINavigationController`是一个**导航控制器**，它用来组织有层次关系的视图。导航控制器维护着一个**视图控制器**栈。在设计导航控制器时，UINavigationController默认也不会显示任何视图（这个控制器自身的UIView不会显示），需要指定用户看到的第一个视图，该视图控制器即是**根控制器rootViewController**，而且这个根控制器不会像其他子控制器一样被销毁，它是导航控制器栈中所有视图控制器的栈底。在UINavigationController中子控制器以栈的形式存储，只有在栈顶的控制器能够显示在界面中，一旦一个子控制器出栈则会被销毁。

**子控制器入栈出栈相关方法**
> 官方文档：You add and remove view controllers from the stack using segues or using the methods of this class. The user can also remove the topmost view controller using the back button in the navigation bar or using a left-edge swipe gesture.出栈：segue、method,移除栈顶：back button、left-edge swipe gesture
 
![](http://upload-images.jianshu.io/upload_images/1727123-37afbad259926b49.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

*子控制器通过pop方法移除栈顶，先销毁的是子控制器自己本身，然后子控制器里面的View才被销毁，因为子控制器是持有View的。* [导航控制下面的子控制器什么时候会被销毁](http://www.cocoachina.com/bbs/read.php?tid=298109)

- pop控制器,不会马上销毁栈顶控制器,而是告诉导航控制器需要把栈顶控制器出栈,等到恰当的时间就会把栈顶控制器出栈,并且销毁。
- `initWithRootViewController:`实际上是调用导航控制器的push方法。
 > Convenience method pushes the root view controller without animation.
 
- 在子视图中可以通过navigationController访问导航控制器，同时可以通过navigationController的childViewControllers获得当前栈中所有的子视图（注意每一个出栈的子视图都会被销毁）

# 2.UINavigationBar与UINavigationItem的关系

[UINavigationBar文档](https://developer.apple.com/library/ios/documentation/UIKit/Reference/UINavigationBar_Class/index.html#//apple_ref/occ/instm/UINavigationBar/pushNavigationItem:animated:)
[UINavigationItem文档](https://developer.apple.com/library/ios/documentation/UIKit/Reference/UINavigationItem_Class/index.html#//apple_ref/occ/cl/UINavigationItem)

### UINavigationBar导航栏:继承自UIView

![](http://upload-images.jianshu.io/upload_images/1727123-a474e9ddda7f0cf2.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
> 它最典型的用法就是放在屏幕顶端，包含着各级视图的导航按钮。它最首要的属性是左按钮（返回按钮）、中心标题，还有可选的右按钮（不过实际上UINavigationBar好像并没有这些属性，应该是存在于UINavigationItem类中的）。你可以单独用导航栏，或者和导航控制器一起使用（后者最普遍）。
> 
> 如果你使用导航控制器去管理不同屏幕内容之间的导航，导航控制器会自动创建NavigationBar，以及在合适的时候push\pop navigation items


### UINavigationItem导航项:继承自NSObject

![](http://upload-images.jianshu.io/upload_images/1727123-287a90e5ec8e5e13.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
> 一个UINavigationItem对象管理展示在导航栏上的按钮和视图。当创建一个导航界面的时候，每个压入导航栈中的视图控制器都需要一个navigation item,它包含了展示在导航栏上的按钮和视图。导航控制器利用最顶层的两个视图控制器的navigation item来提供导航栏的内容。(可以通过子视图控制器（包括根视图控制器）的navigationItem属性访问这个导航项，修改其左右两边的按钮和标题的内容。)

### 关系
navigationcontroller直接控制viewcontrollers集合，然后它包含的navigationbar是整个工程的导航栏，bar有一个用来管理navigationItem的栈。`@property(nonatomic, copy) NSArray <UINavigationItem *> *items`
navigationItem包含了navigationbar视图的全部元素（如title,tileview,backBarButtonItem等），每个视图控制器的导航项元素由所在视图控制器的navigationItem管理。即设置当前页面的左右barbutton，用 self.navigationItem.leftBarButtonItem等。

**总结**

来说：navigationcontroller和navigationbar是一对一的关系，而navigationbar和navigationItem则是一对多的关系。


**记录一些需要注意的地方：**

- 默认情况下除了根视图控制器之外的其他子视图控制器左侧都会在导航栏左侧显示返回按钮，点击可以返回上一级视图，同时按钮标题默认为上一级视图的标题,可以通过navigationItem的backBarButtonItem属性修改。
 - leftBarButtonItem显示原则：
 
 1. 如果当前的视图控制器设置了leftBarButtonItem，则显示当前VC所自带的leftBarButtonItem。
 2. 如果没有设置leftBarButtonItem，且不是根视图控制器的时候，则显示前一层的backBarButtonItem。如果前一层没有指定backBarButtonItem的话，系统将会根据前一层的title属性自动生成一个back按钮，并显示出来。
 3. 如果没有设置leftBarButtonItem，且已是根视图控制器的时候，左边不显示任何东西。
 
 - 下一级子视图**返回按钮**上的标题的显示优先级为：前一层的backBarButtonItem的标题（注意不能直接给backBarButtonItem的标题赋值：即直接更改backBarButtonItem.title，只能重新给backBarButtonItem赋值），前一层navigationItem的标题，前一层视图控制器标题。

- UINavigationController没有navigationItem这样一个直接的属性，但由于UINavigationController继承于UIViewController,它有navigationItem这个属性
 
 ![](http://upload-images.jianshu.io/upload_images/1727123-ae2f0a8dcf1e96b0.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 因此在视图控制器中这样写`self.navigationController.navigationItem.title = @"friend";`是没问题的，但是实际上并不能这样设置标题（self.navigationController.navigationItem 是应该被忽视的属性）。由于UINavigationController是视图控制器的容器，虽然它是特殊的视图控制器，但不应该把它当一般的UIViewController来使用.如果要设置视图控制器标题，应该这样写：``self.navigationItem.title = @"friend";``

- navigationItem是UIViewController的属性，当第一次访问视图控制器的这个属性的时候，它会被创建。（不太明白）

- 设置标题：`self.navigationItem.title = @"friend";`改变的是当前视图控制器的标题。（备注：self.navigationItem.title和self.title的效果是一样的）
设置导航栏颜色：`self.navigationController.navigationBar.barTintColor = [UIColor redColor];`改变的是所有视图控制器的导航栏颜色

**单独用导航栏UINavigationBar，(不是采用UINavigationController)**

```objective-c
- (void)viewDidLoad{
    UINavigationBar *navBar = [[UINavigationBar alloc]initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 44)];
    //添加NavigationBar到视图上
    [self.view addSubview:navBar];
    UINavigationItem *navItem = [[UINavigationItem alloc]initWithTitle:@"welcome page"];
    
    UIBarButtonItem *btnlogin = [[UIBarButtonItem alloc]initWithTitle:@"login" style:UIBarButtonItemStyleDone target:self action:@selector(login)];
    navItem.leftBarButtonItem = btnlogin;
    //把NavigationItem添加到导航栏上（进栈）
    [navBar pushNavigationItem:navItem animated:NO];
}
```

# 3.UIBarButtonItem
[UIBarButtonItem文档](https://developer.apple.com/library/ios/documentation/UIKit/Reference/UIBarButtonItem_Class/index.html#//apple_ref/occ/instm/UIBarButtonItem/initWithBarButtonSystemItem:target:action:)

继承自UIBarItem，再往上的继承NSObject。
![](http://upload-images.jianshu.io/upload_images/1727123-8644a69d41309d0d.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


是专门放在UIToolbar or UINavigationBar上的控件，具有按钮的行为。它分左、右、返回UIBarButtonItem，可以添加到UINavigationItem上去

```objective-c
UINavigationItem *navItem = [[UINavigationItem alloc]initWithTitle:@"welcome page"];
UIBarButtonItem *btnlogin = [[UIBarButtonItem alloc]initWithTitle:@"login" style:UIBarButtonItemStyleDone target:self action:@selector(login)];
navItem.leftBarButtonItem = btnlogin;
```

UIBarButtonItem有如下初始化方法：
![](http://upload-images.jianshu.io/upload_images/1727123-90abba8774e989d7.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

# 4.使用代码方式创建导航
步骤：

- 初始化UINavigationController
- 设置UIWindow的rootViewController为UINavigationController
- 通过push添加对应子控制器

1.friend视图控制器，设置左右导航栏按钮

```objective-c
#import <UIKit/UIKit.h>
@interface FriendViewController : UIViewController
@end

#import "FriendViewController.h"
#import "ContactViewController.h"
@interface FriendViewController ()

@end

@implementation FriendViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    //根据实际运行结果看来（视图不断切换，但下面这句话只会打印一次）：
    //因为是根视图控制器，永远不会被销毁，所以viewdidload只会执行一次。
    NSLog(@"childviewcontroller:%@",self.navigationController.childViewControllers);
    
    NSLog(@"%i",self.navigationController == self.parentViewController);//true
    
    self.navigationItem.title = @"friend";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"edit" style:UIBarButtonItemStyleDone target:nil action:nil];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"User_normal"] style:UIBarButtonItemStyleDone target:self action:@selector(addPeople)];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)addPeople{
    ContactViewController *contactVC = [[ContactViewController alloc]init];
    [self.navigationController pushViewController:contactVC animated:YES];
}
@end
```
- 不设置渲染模式，默认情况下系统会把导航栏上按钮的图片渲染成蓝色

2.contact视图控制器，添加右导航按钮，左导航按钮不设置默认显示上级视图控制器名称作为返回按钮

```objective-c
#import <UIKit/UIKit.h>
@interface ContactViewController : UIViewController
@end

#import "ContactViewController.h"
#import "AccountViewController.h"
@interface ContactViewController ()

@end

@implementation ContactViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // 是子控制器，在视图不断切换的过程中，反复被创建和销毁；下面这句话多次打印出来。
    NSLog(@"childviewcontroller:%@",self.navigationController.childViewControllers);
    
    NSLog(@"%i",self.navigationController == self.parentViewController);
    
    self.view.backgroundColor = [UIColor whiteColor];／／＊＊＊注意＊＊＊不设置切换会有卡顿
    [self setTitle:@"contact"];
    
    //设置下一级视图控制器导航返回按钮
    UIBarButtonItem *back = [[UIBarButtonItem alloc]initWithTitle:@"my contact" style:UIBarButtonItemStyleDone target:nil action:nil];
    self.navigationItem.backBarButtonItem = back;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"account" style:UIBarButtonItemStyleDone target:self action:@selector(goToAccount)];
}

- (void)goToAccount{
    AccountViewController *accountVC = [[AccountViewController alloc]init];
    [self.navigationController pushViewController:accountVC animated:YES];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
@end
```

3.

```objective-c
#import <UIKit/UIKit.h>
@interface AccountViewController : UIViewController
@end

#import "AccountViewController.h"
#import "FriendViewController.h"
@interface AccountViewController ()

@end

@implementation AccountViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"account";
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"toFriend" style:UIBarButtonItemStyleDone target:self action:@selector(goToFriend)];
}

- (void)goToFriend{
    //直接跳转到根控制器
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
@end
```

4.初始化导航控制器并设置根视图控制器

```objective-c
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc]initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];
    [[UINavigationBar appearance]setBarTintColor:[UIColor yellowColor]];
    [[UINavigationBar appearance]setBarStyle:UIBarStyleBlack];    
    FriendViewController *friendVC = [[FriendViewController alloc]init];
    UINavigationController *navController = [[UINavigationController alloc]initWithRootViewController:friendVC];
    self.window.rootViewController = navController;
    [self.window makeKeyAndVisible];
    return YES;
}
```
![](http://upload-images.jianshu.io/upload_images/1727123-c3cfb778f18938e5.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
![](http://upload-images.jianshu.io/upload_images/1727123-318af65986135a4a.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
![](http://upload-images.jianshu.io/upload_images/1727123-f29a069a81ed8e4d.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

**需要注意的地方**：

- 在使用UINavigationController的pushViewController:animated:执行入栈一个子控制器操作时，会出现"卡顿"现象。
原因：这是因为从iOS7开始， UIViewController的根view的背景颜色默认为透明色(即clearColor)，所谓"卡顿"其实就是由于透明色重叠后，造成视觉上的错觉，所以这并不是真正的"卡顿"。

 解决方法：只要在该UINavigationController所push的那个子控制器中设置背景颜色，即取缔默认的透明色  (即clearColor)

 如：在viewDidLoad中写上 `self.view.backgroundColor = [UIColor whiteColor];`

- 跳转到指定控制器:

 ```objective-c
// 注意：跳转到指定控制器的时候，要跳转到的目标控制器必须是在当前导航控制器的栈内的，不能是新创建的控制器
    NSArray *vcs = self.navigationController.childViewControllers;
    OneViewController *oneVc = (OneViewController *)vcs[1];
    [self.navigationController popToViewController:oneVc animated:YES];
}
```

 **注意：返回到指定控制器的时候，要跳转到的目标控制器必须是在当前导航控制器的栈内的，不能是新创建的控制器**

## 5.使用storyboard创建导航

1.在storyboard中拖拽一个UINavigationController。UINavigationController默认会带一个UITableViewController作为其根控制器。设置UITableViewController的标题为“Testing”，同时设置为静态表格并且包含两行，分别在单元格中放置一个UILabel命名为“A”和“B”

2.新建两个UITableViewController，标题分别设置为“A”、“B”
按住Ctrl拖拽“ Testing”的第一个表单元格到视图控制器“A”，同时选择segue为“show”,拖拽第二个表单元格到视图控制器“B”，同时选择segue为“show”。
![](http://upload-images.jianshu.io/upload_images/1727123-92e0b7819f655aba.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

到这里为止，可以通过点击两个单元格导航到A、B视图。

**这里通过storyboard创建导航的关键是"segue"**

Segue的工作方式分为以下几个步骤：

1. 创建目标视图控制器（即A、B视图控制器）
2. 创建Segue对象
3. 调用源视图对象的prepareForSegue:sender:方法
4. 调用Segue对象的perform方法将目标视图控制器推送到屏幕
5. 释放Segue对象

先给Testing控制器绑定一个控制器文件（继承于UITableViewController）。然后选中连接A控制器的segue，设置它的identifier为"ASegue",B同理

![](http://upload-images.jianshu.io/upload_images/1727123-4f520f2b9ea15749.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

在Testing控制器对应文件中添加：

```objective-c
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender{
  //  获得源视图控制器
    UITableViewController *testingVC = segue.sourceViewController;
  //获得目标视图控制器
    UITableViewController *desVC = segue.destinationViewController;
    NSLog(@"sourceController:%@,destinationController:%@",testingVC.navigationItem.title,desVC.navigationItem.title);
}
```
点击两个单元格，出现打印结果如下：对应上述第3步

![](http://upload-images.jianshu.io/upload_images/1727123-ed3b95f21b99b77b.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

在Testing视图控制器中放上左右导航按钮，并添加对应点击事件

```objective-c
- (IBAction)toA:(id)sender {
    [self performSegueWithIdentifier:@"ASegue" sender:self];
}
- (IBAction)toB:(id)sender {
    [self performSegueWithIdentifier:@"BSegue" sender:self];

}
```
运行程序，点击左右两个导航按钮，同样可以跳转到对应的A、B视图控制器，对应上述第4步。

**什么是Segue(延伸)**

Storyboard上每一根用来界面跳转的线，都是一个UIStoryboardSegue对象（简称Segue）

- segue的类型

 根据Segue的执行（跳转）时刻，可分为2大类型:
 
 1. 自动型：点击某个控件后（比如按钮），**自动**执行Segue，自动完成界面跳转（按住Control键，直接从控件拖线到目标控制器）
 2. 手动型：需要通过写代码**手动**执行Segue，才能完成界面跳转（按住Control键，从来源控制器拖线到目标控制器）
 
 ![创建手动型segue](http://upload-images.jianshu.io/upload_images/1727123-7623f598d154f205.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 手动型的Segue需设置标识identifier,在需要的时刻，由来源控制器执行perform方法调用对应的Segue`[self performSegueWithIdentifier:@"填入segue的标识" sender:nil];`

- `performSegueWithIdentifier:sender:`的执行过程  
             
1. self是来源控制器，只能通过来源控制器来调该方法。
2. 根据identifier去storyboard中找到对应的线，新建UIStoryboardSegue对象
3. 设置Segue对象的sourceViewController（来源控制器）
4. 新建并且设置Segue对象的destinationViewController（目标控制器）
5. 调用`- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender`方法。（prepare方法里的sender参数是调用perform方法时sender传入的对象）
6. 执行跳转。