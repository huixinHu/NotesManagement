iOS中有三类事件：UIEventTypeTouches触摸事件、 UIEventTypeMotion “动作”事件,比如摇晃手机设备、UIEventTypeRemoteControl远程控制事件。还有一种在iOS9.0之后出现的UIEventTypePresses事件，和触按物理按钮有关。
三大类事件分别有一些子事件：

![](http://upload-images.jianshu.io/upload_images/1727123-142d64ca64334c86.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

响应者对象：不过在ios中不是任何对象都可以处理事件，只有继承了UIResponder的对象才能**接收**、**处理**事件，比如UIApplication、UIViewController、UIView、UIWindow。

#触摸事件
UIView是UIResponder的子类。UIResponder有以下四个方法处理触摸事件，UIView可以重写这些方法去自定义事件处理。

```objective-c
一根或者多根手指开始触摸view（手指按下）
-(void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event

一根或者多根手指在view上移动（随着手指的移动，会持续调用该方法）
-(void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event

一根或者多根手指离开view（手指抬起）
-(void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event

某个系统事件(例如电话呼入)打断触摸过程
-(void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event
```

对于这四个触摸事件处理方法的参数的说明：

- **第一个参数：(NSSet *)touches**

NSSet和 NSArray类似,但NSSet的区别在：

1.无序不重复(哈希)。与添加顺序也没有关系，也不能通过序号来取出某个元素；即使多次重复添加相同的元素，储存的都只有一个。
2.通过 anyObject方法来随机访问单个元素。
3.如果要访问NSSet 中的每个元素，通过for in循环遍历。
4.好处: 效率高。比如重用 Cell 的时候, 从缓存池中随便获取一个就可以了, 无需按照指定顺序来获取； 当需要把数据存放到一个集合中, 然后判断集合中是否有某个对象的时候

touches参数中存放的都是UITouch对象。

**UITouch**
 
当用**一根手指**触摸屏幕时，会创建**一个**与手指相关联的UITouch对象。如果两根手指**同时**触摸屏幕，则会调用一次touchesBegan方法，创建两个UITouch对象（如果不是同时触摸，调用两次方法，每次的touches参数都只有一个UITouch对象）。
判断是否多点触摸：NSSet有多少个UITouch对象元素。

UITouch保存着跟本次手指触摸相关的信息，比如触摸的位置、时间。当手指移动时，系统会更新同一个UITouch对象，使之能够一直保存该手指的触摸位置。当手指离开屏幕时，系统会销毁相应的UITouch对象。

比如，判断单击、双击或者多击：tapCount属性

```objective-c
 - (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    UITouch * touch = touches.anyObject;//获取触摸对象    
    NSLog(@"%@",@(touch.tapCount));//短时间内的点击次数
}
```

 UITouch常用方法：
 
```-(CGPoint)locationInView:(UIView*)view;```返回触摸在参数view上的位置，该位置基于view的坐标系（以view的左上角为原点(0, 0)）；如果调用时传入的view参数为nil的话，返回的是触摸点在UIWindow的位置

```-(CGPoint)previousLocationInView:(UIView*)view;```前一个触摸点的位置,参数同上

- **第二个参数(UIEvent*)event**

每产生一个事件，就会产生一个UIEvent对象，UIEvent保存事件产生的事件和类型。UIEvent还提供了相应的方法可以获得在某个view上面的UITouch触摸对象。

一次完整的触摸过程中，只会产生一个事件对象，4个触摸方法都是同一个event参数.

### UIView无法与用户交互的情况
1. userInteractionEnabled= NO 如果父视图不能与用户交互, 那么所有子控件也不能与用户交互
2. hidden = YES
3. alpha= 0.0 ~ 0.01
4. 子视图的位置超出了父视图的有效范围, 那么子视图超出部分无法与用户交互的
5. UIImageView的userInteractionEnabled默认是NO，因此UIImageView以及它的子控件默认是不能接收触摸事件的

# 事件的传递&响应
> 事件传递中UIWindow会根据不同的事件类型（3种），用不同的方式寻找initial object。比如Touch Event，UIWindow会首先试着把事件传递给事件发生的那个view，就是下文要说的hit-testview。对于Motion和Remote Event，UIWindow会把例如震动或者远程控制的事件传递给当前的firstResponder

### 寻找响应者Hit-Test&Hit-Test View
![寻找响应消息.png](http://upload-images.jianshu.io/upload_images/1727123-a01de13b741ac8c8.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

Hit-Test的目的就是找到手指点击到的最外层的那个view。它进行类似于探测的工作，判断是否点击在某个视图上。

> Returns the farthest descendant of the receiver in the view hierarchy (including itself) that contains a specified point.

- **什么时候Hit-Test**
与Hit-Test 相关有两个方法：

```
 - (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event; 
 - (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event;
```

runloop

发生触摸事件后，系统会将该事件加入到一个由UIApplication管理的事件队列中；UIApplication会从事件队列中取出最前面的事件并将其分发处理，通常，先发送事件给应用程序的主窗口UIWindow。**UIWindow会调`hitTest:withEvent:`方法**，(从后往前遍历subviews数组)找到点击的点在哪个subview，然后继续调用subView的hitTest:withEvent:方法，直到在视图继承树中找到一个最合适的子视图来处理触摸事件，该子视图即为hit-test view。

 这个view和它上面依附的手势，都会和一个UITouch的对象关联起来，这个UITouch会作为事件传递的参数之一。我们可以看到UITouch.h里有一个view和gestureRecognizers的属性，就是Hit-Test view和它的手势。

- ** hitTest:withEvent：如何找到最合适的控件来处理事件**

1. 判断自己是否能接收触摸事件（能否与用户交互）
2. 触摸点是否在自己身上？ 调用`pointInside:withEvent:`
3. **从后往前**遍历子控件数组，重复前面的两个步骤 (从后往前：按照addsubview的顺序，越晚添加的越先访问)
4. 如果没有符合条件的子控件，那么就自己最适合处理
找到合适的视图控件后，就会调用视图控件的touches方法来作具体的事件处理。

要**拦截事件传递**，可以使用`pointInside:withEvent:`方法，在实现里面直接`return NO;`即可，那么hitTest:withEvent:方法返回nil。又或者在`hitTest:withEvent:`直接return self;不传递给子视图。

> 摘自网络：hitTest:方法内部的参考实现

```objective-c
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    NSLog(@"%@----hitTest:", [self class]);
    // 如果控件不允许与用户交互那么返回 nil
    if (self.userInteractionEnabled == NO || self.alpha <= 0.01 || self.hidden == YES) {
        return nil;
    }
    // 如果这个点不在当前控件中那么返回 nil
    if (![self pointInside:point withEvent:event]) {
        return nil;
    }
    // 从后向前遍历每一个子控件
    for (int i = (int)self.subviews.count - 1; i >= 0; i--) {
        // 获取一个子控件
        UIView *lastVw = self.subviews[i];
        // 把当前触摸点坐标转换为相对于子控件的触摸点坐标
        CGPoint subPoint = [self convertPoint:point toView:lastVw];
        // 判断是否在子控件中找到了更合适的子控件
        UIView *nextVw = [lastVw hitTest:subPoint withEvent:event];
        // 如果找到了返回
        if (nextVw) {
            return nextVw;
        }
    }
    // 如果以上都没有执行 return, 那么返回自己(表示子控件中没有"更合适"的了)
    return  self;
}
```

要扩大view的点击区域，比如要扩大按钮的点击区域(按钮四周之外的10pt也可以响应按钮的事件)，可以怎么做呢？或许重写hitTest:withEvent:是个好办法，hitTest就是返回可以响应事件的view，在button的子类里面重写它，判断如果point在button的frame之外的10pt内，就返回button自己。

### 事件响应
什么是第一响应者？简单的讲，第一响应者是一个UIWindow对象接收到一个事件后，第一个来响应的该事件的对象。

如果hit-test视图不处理收到的事件消息，UIKit则将事件转发到响应者链中的下一个响应者，看其是否能对该消息进行处理。

**响应链**：

![](http://upload-images.jianshu.io/upload_images/1727123-8b9c53f54030cbc2.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

所有的视图按照树状层次结构组织，每个view都有自己的superView，包括vc的self.view：

1. 当一个view被添加到superView上的时候，它的nextResponder就会被指向它的superView；
2. 当vc被初始化的时候，self.view(topmost view)的nextResponder会被指向所在的controller；
 (概括前两者就是：如果当前这个view是控制器的self.view,那么控制器就是上一个响应者 如果当前这个view不是控制器的view,那么父控件就是上一个响应者)
3. vc的nextResponder会被指向self.view的superView。
4. 最顶级的vc的nextResponder指向UIWindow。
5. UIWindow的nextResponder指向UIApplication
6. 
这就形成了响应链。并没有一个对象来专门存储这样的一条链，而是通过UIResponder的串连起来的。

对于touches方法的描述：
> The default implementation of this method does nothing. However immediate UIKit subclasses of UIResponder, particularly UIView, forward the message up the responder chain. To forward the message to the next responder, send the message to super (the superclass implementation); do not send the message directly to the next responder. For example,
[super touchesBegan:touches withEvent:event];
If you override this method without calling super (a common use pattern), you must also override the other methods for handling touch events, if only as stub (empty) implementations.

touches方法实际上什么事都没做，UIView继承了它进行重写，就是把事件传递给nextResponder，相当于`[self.nextResponder touchesBegan:touches withEvent:event]`。所以当一个view没有重写touch事件，那么这个事件就会一直传递下去，直到UIApplication。如果重写了touch方法，这个view响应了事件之后，事件就被拦截了，它的nextResponder不会收到这个事件。这个时候如果想事件继续传递下去，可以调用`[super touchesBegan:touches withEvent:event]`，不建议直接调`[self.nextResponder touchesBegan:touches withEvent:event]`。
调用`[super touches...]`

（实际运行打断点查看：之后父类响应touches，一直传递下去，最后UIResponse来响应touches，然后再由下一个响应者响应touches；前提是它们都重写了touches方法，以及调用```[super touches...]```）

附上一个[响应链传送门](http://blog.csdn.net/mobanchengshuang/article/details/11858217)

不过UIScrollview的touches响应又是另一回事。

**响应链事件传递（向上传递）**：

1. 如果view的控制器存在，就传递给控制器；如果控制器不存在，则将其传递给它的父视图
2. 在视图层次结构的最顶级视图，如果也不能处理收到的事件或消息，则其将事件或消息传递给window对象进行处理
3. 如果window对象也不处理，则其将事件或消息传递给UIApplication对象
4. 如果UIApplication也不能处理该事件或消息，则将其丢弃

总结：

**监听事件的基本流程**:

1. 当应用程序启动以后创建 UIApplication 对象
2. 然后启动“消息循环”监听所有的事件
3. 当用户触摸屏幕的时候, "消息循环"监听到这个触摸事件
4. "消息循环" 首先把监听到的触摸事件传递了 UIApplication 对象
5. UIApplication 对象再传递给 UIWindow 对象
6. UIWindow 对象再传递给 UIWindow 的根控制器(rootViewController)
7. 控制器再传递给控制器所管理的 view
8. 控制器所管理的 View 在其内部搜索看本次触摸的点在哪个控件的范围内
9. 找到某个控件以后(调用这个控件的 touchesXxx 方法), 再一次向上返回, 最终返回给"消息循环"
10. "消息循环"知道哪个按钮被点击后, 在搜索这个按钮是否注册了对应的事件, 如果注册了, 那么就调用这个"事件处理"程序。（一般就是执行控制器中的"事件处理"方法）

# 手势
手势识别和触摸事件是两个独立的事，不要混淆。

通过touches方法监听view触摸事件，有很明显的几个缺点：必须得自定义view、由于是在view内部的touches方法中监听触摸事件，因此默认情况下，无法让其他外界对象监听view的触摸事件、不容易区分用户的具体手势行为。

iOS3.2之后, 把触摸事件做了封装, 对常用的手势进行了处理, 封装了6种常见的手势

- UITapGestureRecognizer(敲击)
- UILongPressGestureRecognizer(长按)
- UISwipeGestureRecognizer(轻扫)
- UIRotationGestureRecognizer(旋转)
- UIPinchGestureRecognizer(捏合，用于缩放)
- UIPanGestureRecognizer(拖拽)

下面谈几个在项目中遇到的问题:

关于手势和touch的相互影响

#### tap的cancelsTouchesInView方法
“A Boolean value affecting whether touches are delivered to a view when a gesture is recognized.”也就是说，可以通过设置这个布尔值，来设置手势被识别时触摸事件是否被传送到视图。
 
当值为YES（默认值）的时候，系统会识别手势，并取消触摸事件；为NO的时候，手势识别之后，系统将触发触摸事件。

- 把手势添加到btn上

 ```objective-c
 - (void)viewDidLoad { 
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
    button.backgroundColor = [UIColor redColor];
    [self.view addSubview:button];
    [button addTarget:self action:@selector(btnAction:) forControlEvents:UIControlEventTouchUpInside];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapAction:)];
    tap.cancelsTouchesInView = NO;
    [button addGestureRecognizer:tap];
}
 
 - (void)tapAction:(UITapGestureRecognizer *)sender {
    NSLog(@"tapAction");
}

 - (void)btnAction:(UIButton *)btn {
    NSLog(@"btnAction");
}
```

当cancelsTouchesInView为NO的时候，点击按钮，会先后触发“tapAction:”和“btnAction:”方法；而当cancelsTouchesInView为YES的时候，只会触发“tapAction:”方法。

- 把手势添加到btn的父view上即`[self.view addGestureRecognizer:tap];`

cancelsTouchesInView=NO，点击按钮，会先后触发“tapAction:”和“btnAction:”方法；cancelsTouchesInView=YES，只会触发按钮方法不会触发手势。

- 但如果不是btn而是别的控件，把手势添加到控件的父view上

项目中用到的是collectionView，cancelsTouchesInView=NO，点击collectionViewCell，先后触发手势和Cell，cancelsTouchesInView=YES只会触发手势。

对于UIButton,UISlider等继承自UIControl的控件，都会先响应触摸事件，从而阻止手势事件。手势可以理解为是“特殊的层”。对于TableView，CollectionView这种弱点击事件，系统优先响应手势，如果要响应Cell点击事件就要实现代理方法

### 实现手势的代理方法对手势进行拦截。
> called before touchesBegan:withEvent: is called on the gesture recognizer for a new touch. return NO to prevent the gesture recognizer from seeing this touch

判断，手势的触击方法是否在控件区域，如果是，则返回NO，禁用手势。否则返回YES.

```objective-c
 - (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch{
//    NSLog(@"%d",[touch.view isKindOfClass:[UIButton class]]);
    if ([touch.view.superview isKindOfClass:[UICollectionViewCell class]]) {//如果点击的是UICollectionViewCell，touch.view是collectionViewCell的contentView，contentView的父view才是collectionCell
        return NO;
    }else if ([touch.view isKindOfClass:[UIButton class]]) {
        return NO;
    }
    return YES;
}
```

其他：

项目上没遇到且目前还没有深入了解，先po链接方便以后查：

丢一个传送门讲Gesture Recognizers与事件分发路径的关系：
http://blog.csdn.net/chun799/article/details/8194893

手势的3个混淆属性 cancelsTouchesInView/delaysTouchesBegan/

delaysTouchesEnded： http://www.mamicode.com/info-detail-868542.html


### 补充

对于UIControl类型的控件，一个给定的事件，UIControl会调用`- (void)sendAction:(SEL)action to:(nullable id)target forEvent:(nullable UIEvent *)event`来将action message转发到UIApplication对象，再由UIApplication对象调用其`sendAction:to:fromSender:forEvent:`方法来将消息分发到指定的target上，如果没有指定target(即nil)，则会将事件分发到响应链上第一个想处理消息的对象上。而如果UIControl子类想监控或修改这种行为的话，则可以重写`sendAction: to: forEvent:`。

将外部添加的Target-Action放在控件内部来处理事件,实现如下：
```
// Btn.m
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
  // 将事件传递到对象本身来处理
    [super sendAction:@selector(handleAction:) to:self forEvent:event];
}
 
- (void)handleAction:(id)sender { 
    NSLog(@"handle Action");
}
 
// ViewController.m
- (void)viewDidLoad {
    [super viewDidLoad]; 
    self.view.backgroundColor = [UIColor whiteColor]; 
    Btn *btn = [[Btn alloc]initWithFrame:CGRectMake(30, 30, 100, 100)];
    btn.backgroundColor = [UIColor yellowColor];
    [btn addTarget:self action:@selector(btnclick:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
}
- (IBAction)btnclick:(id)sender {
    NSLog(@"click");
}
```

最后处理事件的Selector是Btn的handleAction:方法，而不是ViewController的btnclick:方法。

另外，sendAction:to:forEvent:实际上也被UIControl的另一个方法所调用，即sendActionsForControlEvents:。这个方法的作用是发送与指定类型相关的所有行为消息。我们可以在任意位置(包括控件内部和外部)调用控件的这个方法来发送参数controlEvents指定的消息。在我们的示例中，在ViewController.m中作了如下测试：

```
- (void)viewDidLoad {
    // ...
    [btn addTarget:self action:@selector(btnclick:) forControlEvents:UIControlEventTouchUpInside];
    [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
}
```
没有点击btn，触发了UIControlEventTouchUpInside事件，并执行handleAction:方法。