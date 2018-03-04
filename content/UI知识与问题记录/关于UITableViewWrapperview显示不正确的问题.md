问题描述：在使用了navigationController的情况下对子视图手动添加了64的偏移。

![](http://upload-images.jianshu.io/upload_images/1727123-bbcaa5af210bb2c1.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

![](http://upload-images.jianshu.io/upload_images/1727123-33d8b7e50e5c8a5c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

系统对于作为UINavigationViewController的**第一个subView的全屏UIScrollView**(即第一个subview是scrollview)，会自动处理其contentInset，使其头部和尾部的内容起始和末尾时不会被UINavigationBar和UITabBar挡住。

navigationController的automaticallyAdjustsScrollViewInsets属性为yes时会自动对contentview上的第一个uiscrollview自动加bar的insets（一般为64，下面都以64来说，但有些情况下不是64，比如接电话时，是84）。

如果要想scrollview的内容从（0，0）位置开始，只要把viewController的automaticallyAdjustsScrollViewInsets属性设为NO就可以了。

如果设置了automaticallyAdjustsScrollViewInsets = NO;但又想内容从navigationBar下面开始，对于scrollview,可以设置contentInset，或者手动设置64的偏移量了，但是除非另外加上一些代码判断，当遇到接电话、录音、连接个人热点等通知栏高度改变时界面会错位。而对于非scrollview，automaticallyAdjustsScrollViewInsets对他们不起作用

更方便的方法就是设置其edgesForExtendedLayout属性，该属性默认为UIRectEdgeAll，意为view会充分扩展至屏幕边缘包括上下左右，而不管有没有遮挡，此时就是view的frame即为整个屏幕。
> 好的方法是用autolayout，并且不设置偏移（顶部到顶），然后在viewDidLoad中设置self.edgesForExtendedLayout=UIRectEdgeNone
这样设置的作用是让controller绘制视图时不要将顶部通知栏、导航栏和底部toolbar等的高度计算在contentview中，所以这样设置之后就可以不设置tableview的偏移也可以显示正常，然后使用autolayout的目的是为了界面重载时（如切换打电话状态）也能重新调整界面

解决：

![](http://upload-images.jianshu.io/upload_images/1727123-59c3cfbbfb8ce416.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

相关链接：

[见12楼解释](http://bbs.csdn.net/topics/391833162) 

[automaticallyAdjustsScrollViewInsets以及edgesForExtendedLayout属性对布局的影响](http://www.jianshu.com/p/c0b8c5f131a0)