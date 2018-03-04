view A添加到vc.view ，view B添加到view A。

```objective-c
vc.m
@property (nonatomic,strong)ViewA *aView;
@property (nonatomic,strong)ViewB *bView;

ViewA.m ViewB.m类似
@implementation ViewA
- (instancetype)initWithFrame:(CGRect)frame{
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor greenColor];
    }
    return self;
}

- (void)layoutSubviews{
    [super layoutSubviews];
    NSLog(@"viewA 调用layoutSubviews");
}
@end
```

## 1.初始化不会触发layoutSubviews
对A仅初始化，没addSubview:到vc.view。不触发A的layoutSubviews

## 2.addSubview
- addSubview会让B，以及A（view 和它的父view）都调用自己的layoutSubviews。而且先调用父view的
- 如果B的frame 为CGRectZero.即使调用了addSubView也不会调用B的layoutSubviews，A仍然调用。
- 如果A的frame为CGRectZero，B的frame不是CGRectZero。A B都调用

```objective-c
 - (void)viewDidLoad{
  //    不调用
  //    ViewA *aView = [[ViewA alloc]init];
  //    [self.view addSubview:aView];
    
  //    调用
  //    ViewA *aView = [[ViewA alloc]initWithFrame:CGRectMake(100, 100, 100, 100)];
//    [self.view addSubview:aView];
    
  //    viewA viewB都会调用，而且先调用a
  //    ViewA *aView = [[ViewA alloc]init];
  ////    ViewA *aView = [[ViewA alloc]initWithFrame:CGRectMake(100, 100, 100, 100)];
  //    [self.view addSubview:aView];
  //    ViewB *bView = [[ViewB alloc]initWithFrame:CGRectMake(0, 0, 50, 50)];
  //    [aView addSubview:bView];

    self.aView = [[ViewA alloc]initWithFrame:CGRectMake(150, 100, 100, 100)];
    [self.view addSubview:self.aView];
    self.bView = [[ViewB alloc]initWithFrame:CGRectMake(0, 0, 50, 50)];
    [self.aView addSubview:self.bView];
}

 - (IBAction)clicked:(id)sender {    
    ViewB *b2 = [[ViewB alloc]initWithFrame:CGRectMake(0, 0, 30, 30)];
    b2.backgroundColor = [UIColor purpleColor];
    [self.bView addSubview:b2];
}
```

## 3.setFrame
- 改变一个UIView size的时候也会触发父UIView上的layoutSubviews事件。B改变size，A B 都会调layoutSubviews。
- 改变view的size会触发layoutSubviews。A改变size，只有A调layoutSubviews

```objective-c
 - (void)viewDidLoad{
    self.aView = [[ViewA alloc]initWithFrame:CGRectMake(150, 100, 100, 100)];
    [self.view addSubview:self.aView];
    self.bView = [[ViewB alloc]initWithFrame:CGRectMake(0, 0, 50, 50)];
    [self.aView addSubview:self.bView];
}

 - (IBAction)clicked:(id)sender {
 //    self.view.frame = CGRectMake(1, 0, 300, 730);//一个都没调,调了viewDidLayoutSubviews

  //    self.aView.frame = CGRectMake(101, 101, 100, 101);//如果不改变size只改变位置，什么也没调用。如果改变size，只调A的。
 //    self.bView.frame = CGRectMake(1, 1, 50, 50);//如果不改变size只改变位置，什么也没调用。如果改变size，先调A，再调B.
}
```

## 4.滚动一个UIScrollView会触发scrollview 的layoutSubviews
## 5.旋转Screen会触发vc上的layoutSubviews事件

## 其他
> layoutSubview不是在调用完比如addSubview等方法之后就马上调用,而是会在调用addSubview方法所在的作用域结束之后之后才调用,因此即使你在同一个方法中既使用了addSubViews又更改了frame，也是只会调用一次layoutSubview而已

另外，重写layoutSubviews,也需要调用它的父类方法,即 [super layoutSubviews]