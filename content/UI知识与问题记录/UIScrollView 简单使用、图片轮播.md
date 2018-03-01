scrollview中的内容要滚动就必须要设置 滚动范围。

## 常用属性
**contentsize**：子控件的大小，限定内容滚动范围。在设置size的时候一定要比scrollview的size要大，不然不能滚动。如果设置的size中的宽度为0，就表示在横向中不能滚动，纵向同理。

```objective-c
scrollview.contentSize = CGSizeMake( width , height )
```

**showsHorizontalScrollIndicator、showsVerticalScrollIndicator**：水平、垂直滚动指示器是否可见。

```objective-c
scrollview. showsHorizontalScrollIndicator = NO;//不可见
scrollview. showsVerticalScrollIndicator = NO;//不可见
```

**bounces**：弹簧效果，默认为YES不关闭

```objective-c
scrollview.bounces = YES;
```

**alwaysBounceVertical、alwaysBounceHorizontal**：没有设置content size的时候，依然有弹簧效果。

```objective-c
scrollview.alwaysBounceHorizontal = YES;
scrollview.alwaysBounceVertical = YES;
```

**contentInset**：内容的内边距。scrollview的内容拖动后，内容距离scrollview的内边距。变相的增加滚动范围

```objective-c
scrollview.contentInset = UIEdgeInsetsMake(10, 20, 30, 40);
```

**contentOffset**：偏移量，滚动到某个位置。

```objective-c
scrollview.contentOffset = CGPointMake(100, 100);
```

**minimumZoomScale、maximumZoomScale**：最小、最大缩放倍数

**scrollView 不能滚动的原因**：

```objective-c
1. contentSize 比 scrollView的size 小
2. _scrollView.userInteractionEnabled = NO;
3. _scrollView.scrollEnabled = NO;
```

对UIScrollView的构成理解：

UIScollView相当于由上下两层构成：上层 可视视图区域+ 下层 内容视图。UIScollView的frame控制着上层的大小，我们看到的UIScrollView的大小实际就是frame的大小，上层固定不动，显示的变化，由下层的滚动来控制。

下层是该UIScrollView的内容视图，UIScrollView使用该内容视图来对外展示内容，即这个内容视图即常说的UIScrollView的contentView；contentSize属性就决定着这个内容视图的大小.

当我们的手指在UIScrollView控件中上、下、左、右方向滑动时，真正滑动的是该UIScrollView的下层(内容视图)，而上层始终固定不动。

下层滚动的实现的理解：相当于设置contentOffset属性：它改变scroll view.bounds的origin。contentOffset甚至不是实际存在的。代码看起来像这样：

```objective-c
- (void)setContentOffset:(CGPoint)offset  
{  
    CGRect bounds = [self bounds];  
    bounds.origin = offset;  
    [self setBounds:bounds];  
}  
```

## 代理方法

- 当scrollView内容滚动的时候就会调用, 只要在滚动就会调用

```objective-c
 - (void)scrollViewDidScroll:(UIScrollView *)scrollView {    
    NSLog(@"滚动的时候调用 %@",NSStringFromCGPoint(scrollView.contentOffset));
}
```

- 开始拖拽的时候调用， 拖拽过程中只会调用一遍

```objective-c
 - (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    NSLog(@"开始拖拽的时候调用");
}
```

- 停止拖拽 , 调用一次

```objective-c
 - (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    NSLog(@"停止拖拽的时候调用");
```

- 用户捏合手势时调用。返回的view将被拉伸（缩放）

```objective-c
 - (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _imageView;//返回值为需要缩放的对象
}
```

- 正在缩放的过程中都会一直调用

```objective-c
 - (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    NSLog(@"scrollViewDidZoom");
}
```

- 开始缩放的时候调用

```objective-c
 - (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
    NSLog(@"scrollViewWillBeginZooming");
}
```

- 结束缩放的时候调用

```objective-c
// 参数：withView: 进行缩放的view  atScale: 缩放的倍数
 - (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
    NSLog(@"scrollViewDidEndZooming");
}
```

- 当scrollView停止减速的时候调用.*The scroll view calls this method when the scrolling movement comes to a halt.*

```objective-c
 - (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {  
    _pageControl.currentPage = scrollView.contentOffset.x / kScrollViewSize.width;
}
```


图片轮播Demo。使用UIScrollView和分页指示器UIPageControl，UI布局使用Masonry

```objective-c
@property (nonatomic ,weak)UIScrollView *scrollview;
@property (nonatomic ,weak)UIPageControl *pageControl; 

_scrollView.delegate = self;

- (void)setupScrollView{
    UIScrollView *scrollview = [[UIScrollView alloc]init];
    _scrollview = scrollview;
    [self.view addSubview:_scrollview];
    
    [self setupScrollViewFrame];
    //马上更新
    [self.view updateConstraintsIfNeeded];
    [self.view layoutIfNeeded];
    
    for (int i = 0; i < 4; i ++) {
        UIImage *img = [UIImage imageNamed:@"table.jpg"];
        //计算imageview的x值
        CGFloat imageViewX = i * _scrollview.frame.size.width;
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(imageViewX, _scrollview.frame.origin.y, _scrollview.frame.size.width, _scrollview.frame.size.height)];
        [_scrollview addSubview:imageView];
        imageView.image = img;
    }
    //设置scrollview的contentsize
    _scrollview.contentSize = CGSizeMake(4 * screenWidth, screenWidth);//因为纵向上不能滚动，所以height设置为0也可以
    //设置分页效果。按照UIScrollView自身的宽度来实现分页。UIScrollView的宽度就是每页的大小
    _scrollview.pagingEnabled = YES;
    _scrollview.showsHorizontalScrollIndicator = NO;
    _scrollview.showsVerticalScrollIndicator = NO;
    _scrollview.bounces = NO;
    
    _scrollview.delegate = self;
}

- (void)setupScrollViewFrame{
    __weak typeof(self)weakself = self;
    [_scrollview mas_makeConstraints:^(MASConstraintMaker *make) {
       make.size.mas_equalTo(CGSizeMake(weakself.view.frame.size.width, weakself.view.frame.size.width));
        make.centerX.equalTo(weakself.view.mas_centerX);
        make.top.equalTo(weakself.view.mas_top);
    }];
}

- (void)setupPageControl{
    UIPageControl *pageControl = [[UIPageControl alloc]init];
    _pageControl = pageControl;
    _pageControl.numberOfPages = 4;//总页数
    _pageControl.currentPage = 0;//当前页
    _pageControl.currentPageIndicatorTintColor = colorYellow;
    _pageControl.pageIndicatorTintColor = [UIColor colorWithRed:240.0/255 green:240.0/255 blue:240.0/255 alpha:1.0];
    [_pageControl addTarget:self action:@selector(changePage:) forControlEvents:UIControlEventValueChanged];//绑定事件
    //pagecontrol不要放到scrollview中，而应该放到控制器的view中，否则就会和scrollview一起滚动了。
    [self.view addSubview:_pageControl];
    [self setupPageControlFrame];
}

- (void)setupPageControlFrame{
    CGSize size = [_pageControl sizeForNumberOfPages:4];//pagecontrol的size
    [_pageControl mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(size);
        make.centerX.equalTo(_scrollview.mas_centerX);
        make.bottom.equalTo(_scrollview.mas_bottom);
    }];
}

//点击pagecontrol里面的“点”，页面切换
- (void)changePage:(UIPageControl*)pageControl{
    CGFloat offsetX = pageControl.currentPage * _scrollview.frame.size.width;
    [self.scrollview setContentOffset:CGPointMake(offsetX, 0) animated:YES];
}

#pragma mark UIScrollViewDelegate
//设置当前页
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    _pageControl.currentPage = scrollView.contentOffset.x / _scrollview.frame.size.width;
}
```
如果需要实现自动轮播。使用NSTimer实现

```objective-c
#pragma mark -  创建计时器
- (void)initImageTimer {
    // 一旦创建就会立即生效
    _timer = [NSTimer scheduledTimerWithTimeInterval:2  target:self selector:@selector(autoPlay)  userInfo:nil repeats:YES];
    NSRunLoop *mainLoop = [NSRunLoop mainRunLoop];   
    [mainLoop addTimer:_timer forMode:NSRunLoopCommonModes];    
}
//在开始拖拽的时候， 把计时器停止
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    // 让计时器无效. 如果调用了 invalidate方法， 那么这个计时器就不会再次生效,下次需要重新创建新的timer。
    [_timer invalidate];
}
// 当停止拖拽的时候， 让计时器开始工作
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {    
    [self initImageTimer];
}
//自动播放 切换页面
- (void)autoPlay{
    更改scrollview的contentoffset
    更改pagecontrol的currentpage
}
```