UITableView和UICollectionView都是由dataSoure和delegate驱动的。他们为其显示的子视图集扮演为愚蠢的容器，对他们真实的内容毫不知情。

## 如何展示数据
`UICollectionView`需要**layout**和**数据源(dataSource)** 来显示数据，`UICollecitonView`会向数据源查询一共有多少行数据以及每一个显示什么数据等,在查询每一个显示什么数据前要确定设置了`layout`而且`itemSize`不能小于{0，0}。

没有设置`layout`布局对象程序会崩溃。
没有设置数据源和布局对象的`UICollectionView`只是个空壳。

凡是遵守`UITableViewDataSource`协议的OC对象，都可以是`UICollectionView`的数据源。

## UICollectionView的常见属性
```objective-c
布局对象
@property (nonatomic, strong) UICollectionViewLayout *collectionViewLayout;

背景视图,会自动填充整个UICollectionView
@property (nonatomic, strong) UIView *backgroundView;

是否允许选中cell 默认允许选中
@property (nonatomic) BOOL allowsSelection;

是否可以多选 默认只是单选
@property (nonatomic) BOOL allowsMultipleSelection;
```

## UICollectionView常用数据源方法
调用数据源的下面方法得知一共有多少组数据

```objective-c
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView;
```

调用数据源的下面方法得知每一组有多少项数据

```
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section;
```

调用数据源的下面方法得知每一项显示什么内容

```
- (UICollectionViewCell *)collectionView:(UICollectionView *) collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath;
```

`UICollectionView`的数据源必须实现第二个方法和第三个方法,第一个方法不实现默认就是1组.

![](http://upload-images.jianshu.io/upload_images/1727123-f98126ac54f2a02b.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

collectionView 重用cell的时候, 不做为空判断, 做为空判断是由collcetionView来做。如上图，想要像`tableview`一样用类似的方法(initxx)创建一个新的`cell`是不行的，因为`collectionViewCell`没有对应的`init`方法，这里必须要注册`cell`才行。

注册cell的三种方式：xib、class、storyboard prototype。
比如：

```objective-c
[_collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:identifier];
```

**demo1：使用storyboard演示UICollectionView简单的使用**

collectionview背景色默认是黑色的？

```objective-c
#import "ViewController.h"
@interface ViewController ()<UICollectionViewDataSource,UICollectionViewDelegate>
@property (weak, nonatomic) IBOutlet UICollectionView *collectionView;
@end

// 重用标识符
static NSString *identifier = @"collectionCee";
@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];  
    // 设置控制器成为 collectionView的数据源代理
    _collectionView.dataSource = self;    
    // 设置控制器成为 collectionView 的代理
    _collectionView.delegate = self;    
    /**
     must register a nib or a class for the identifier or connect a prototype cell in a storyboard     
     注册cell的三种方式
     xib、class、storyboard prototype
     */
    
#warning 必须注册cell
    [_collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:identifier];    
    // collectionView 默认是黑色背景
    _collectionView.backgroundColor = [UIColor whiteColor];    
}

// 组, 如果不实现, 默认就是一组
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}
// 行数
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return 100;
}
// 每行要显示的内容
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {    
    // 到缓存池中去找
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];    
    // 判断是否为空
//    if (nil == cell) {
//        cell = [UICollectionViewCell alloc] init
//    }   
    cell.backgroundColor = [UIColor redColor];    
    return cell;
}
```

## UICollectionViewCell
和`tableviewCell`不一样，`CollectionViewCell`里面没有其他的子控件：

![](http://upload-images.jianshu.io/upload_images/1727123-0e4fa08d195eff8a.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

要往`CollectionViewCell`里面添加子控件就要添加到它的`contentView`上。cell的布局是由 flowlayout实现的。

## UICollectionViewFlowLayout简介

UICollectionView进一步抽象了。它将其子视图的位置，大小和外观的控制权委托给一个单独的布局对象。通过提供一个自定义布局对象，你几乎可以实现任何你能想象到的布局。布局继承自UICollectionViewLayout这个抽象基类。iOS6中以UICollectionViewFlowLayout类的形式提出了一个具体的布局实现。
 
flow layout可以被用来实现一个标准的grid view，这可能是在collection view中最常见的使用案例了。尽管大多数人都这么想，但是Apple很聪明，没有明确的命名这个类为UICollectionViewGridLayout。而使用了更为通用的术语flow layout，这更好的描述了该类的能力：它通过一个接一个的放置cell来建立自己的布局，当需要的时候，插入横排或竖排的分栏符。通过自定义滚动方向，大小和cell之间的间距，flow layout也可以在单行或单列中布局cell。

flowLayout-流水布局。cell一个个按顺序放置下去，当一行（一列）没位置放下一个cell就从下一行（一列）放起。

![纵向滑动时，的布局方式](http://upload-images.jianshu.io/upload_images/1727123-d56943ddb6ee2934.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

![横向滑动时，的布局方式](http://upload-images.jianshu.io/upload_images/1727123-ab2765233f71ab19.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

**demo2：用纯代码方式创建UICollectionView**

和demo1基本上差不多，下面只贴出不一样的部分。

```objective-c
- (void)viewDidLoad {
    [super viewDidLoad];    
    /**
     collectionView  必须有一个 layout
     在storyboard 上拖拽的时候, 已经自动添加一个 流水布局
     UICollectionView must be initialized with a non-nil layout parameter
     */
    
    /**
     实例化一个layout对象
     collectionView 如果要使用layout 必须在实例化的时候就进行设置

     UICollectionViewLayout      是流水布局的父类, 最纯净的layout
     UICollectionViewFlowLayout  是在父类上做了一些相应的扩展
     */    
    UICollectionViewFlowLayout *flowLayout = [[UICollectionViewFlowLayout alloc] init];    
    // 修改cell 的大小 , 默认是 50 , 50
    flowLayout.itemSize = CGSizeMake(100, 100);
    // 实例化一个collectionView    
    UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds  collectionViewLayout:flowLayout];
    
    collectionView.dataSource = self;    
    [self.view addSubview:collectionView];    
    collectionView.backgroundColor = [UIColor whiteColor];    
    // 注册一个cell
    [collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:identifier];
}
```

创建UICollectionView不可仅使用`UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds];`，会报如下的错误：它需要一个layout。在storyboard 上拖拽的时候, 已经自动添加一个flowlayout。

![](http://upload-images.jianshu.io/upload_images/1727123-e5aec33d93a8d7d1.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

collectionView 如果要使用layout 必须在实例化的时候就进行设置。 UICollectionViewLayout是流水布局的父类, 最纯净的layout，UICollectionViewFlowLayout 是在父类上做了一些相应的扩展(flowlayout扩展了一些外观上的东西，具体这两者的差别自己点开api来看)。因此如果使用的是UICollectionViewLayout，在这个demo中，界面上看起来还是“什么都没有”：

```objective-c
UICollectionViewLayout *layout = [[UICollectionViewLayout alloc] init]; 
UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds  collectionViewLayout:layout ];
```

### UICollectionViewFlowLayout常用属性

```objective-c
cell之间的最小行间距                                               
 @property (nonatomic) CGFloat minimumLineSpacing;

cell之间的最小列间距   
@property (nonatomic) CGFloat minimumInteritemSpacing;

cell的尺寸
@property (nonatomic) CGSize itemSize;

cell的预估尺寸
@property (nonatomic) CGSize estimatedItemSize;

UICollectionView的滚动方向,默认是垂直滚动
@property (nonatomic) UICollectionViewScrollDirection scrollDirection;

HeaderView的尺寸
@property (nonatomic) CGSize headerReferenceSize;

FooterView的尺寸
@property (nonatomic) CGSize footerReferenceSize;

分区的四边距
@property (nonatomic) UIEdgeInsets sectionInset;

设置是否当元素超出屏幕之后固定页眉视图位置，默认NO
@property (nonatomic) BOOL sectionHeadersPinToVisibleBounds;

设置是否当元素超出屏幕之后固定页脚视图位置，默认NO
@property (nonatomic) BOOL sectionFootersPinToVisibleBounds
```

这两个属性是跟滚动方向有关的：minimumInteritemSpacing、minimumLineSpacing

## 自定义cell及实现“应用管理”app
![](http://upload-images.jianshu.io/upload_images/1727123-d3511bc6a45bacba.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

1.数据模型

```objective-c
#import <Foundation/Foundation.h>
@interface AppModel : NSObject
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *name;
- (instancetype)initWithDict:(NSDictionary *)dict;
+ (instancetype)appModelWithDict:(NSDictionary *)dict;
@end

#import "AppModel.h"
@implementation AppModel
- (instancetype)initWithDict:(NSDictionary *)dict {
    if (self = [super init]) {
        [self setValuesForKeysWithDictionary:dict];
    }
    return self;
}

+ (instancetype)appModelWithDict:(NSDictionary *)dict {
    return [[self alloc] initWithDict:dict];
}
@end
```

2.自定义cell

```objective-c
#import <UIKit/UIKit.h>
@class  AppModel;
@interface AppCell : UICollectionViewCell
@property (nonatomic, strong) AppModel *appModel;
@end

//  AppCell.m
#import "AppCell.h"
#import "AppModel.h"
@interface AppCell()
@property (nonatomic, weak) UIImageView *iconImageView;
@property (nonatomic, weak) UILabel *nameLabel;
@end

@implementation AppCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        // 设置cell的背景色
        self.backgroundColor = [UIColor redColor]; 
       
        CGSize cellSize = self.contentView.frame.size;        
        // 添加imageView
        CGFloat iconWidth  = cellSize.width * 0.6;
        CGFloat iconX = (cellSize.width - iconWidth)/2;        
        UIImageView *iconImageView = [[UIImageView alloc] init];        
        self.iconImageView = iconImageView;        
        [self.contentView addSubview:iconImageView];        
        
        // 添加label
        UILabel *nameLabel = [[UILabel alloc] init];        
        self.nameLabel = nameLabel;        
        // 设置label的属性
        nameLabel.font = [UIFont systemFontOfSize:13];
        nameLabel.textAlignment = NSTextAlignmentCenter;
        nameLabel.textColor = [UIColor blackColor];        
        nameLabel.text = @"爸爸去哪";        
        [self.contentView addSubview:nameLabel];        
    }
    return self;
}

// 重写set方法
- (void)setAppModel:(AppModel *)appModel {
    _appModel = appModel;    
    // 对子控件赋值    
    _iconImageView.image = [UIImage imageNamed:appModel.icon];    
    _nameLabel.text = appModel.name;
}
@end
```

3.vc

```objective-c
#import "ViewController.h"
#import "AppCell.h"
#import "AppModel.h"

@interface ViewController ()<UICollectionViewDataSource>
@property (nonatomic, strong) NSArray *dataArray;
@property (nonatomic, strong) UICollectionViewFlowLayout *flowLayout;
@end

// 定义重用标识符
static NSString *identifier = @"collectionCell";
@implementation ViewController
#pragma mark -
#pragma mark - 懒加载数据
- (NSArray *)dataArray {
    if (nil == _dataArray) {        
        // 路径
        NSString *path = [[NSBundle mainBundle] pathForResource:@"app.plist" ofType:nil];     
        // 读取
        NSArray *tempArray = [NSArray arrayWithContentsOfFile:path];       
        // 可变       
        NSMutableArray *mutable = [NSMutableArray array];        
        // 转换
        for (NSDictionary *dict in tempArray) {
            AppModel *appModel = [AppModel appModelWithDict:dict];
            [mutable addObject:appModel];
        }        
        // 赋值
        _dataArray = mutable;
    }
    return _dataArray;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. 实例化一个 collectionViewFlowLayout
    _flowLayout = [[UICollectionViewFlowLayout alloc] init];    
    // 修改item的大小
    _flowLayout.itemSize = CGSizeMake(100, 100);    
    // 修改cell距离view的边距
    _flowLayout.sectionInset = UIEdgeInsetsMake(40, 10, 0, 10);
    
    // 修改滚动方向
//    _flowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    // 下面两个属性是和 滚动方向有关的    
    // 最小列之间的间距
    _flowLayout.minimumInteritemSpacing = 50;    
    // 设置最小行间距
//    flowLayout.minimumLineSpacing = 100;
       
    // 2. 实例化一个 collectionView
    UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:_flowLayout];    
    // 3. 注册一个cell
    [collectionView registerClass:[AppCell class] forCellWithReuseIdentifier:identifier];   
    // 4. 设置数据源代理
    collectionView.dataSource = self;    
    // 5. 添加到控制器的view上
    [self.view addSubview:collectionView];    
    collectionView.backgroundColor = [UIColor whiteColor];    
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.dataArray.count;
}

// 每一行显示的内容
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    // 直接到缓存池中去找cell
    AppCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
    // 取出appmodel
    AppModel *appModel = self.dataArray[indexPath.row];   
    cell.appModel = appModel;    
    return cell;
}
```

# 其他
UICollectionViewController中
self.view和self.collectionView 代表的是不同类型的, self.collectionView 才是 collectionView，self.view是wrapperView

其他相关：

http://www.jianshu.com/p/45ff718090a8

http://www.cocoachina.com/ios/20160211/15248.html