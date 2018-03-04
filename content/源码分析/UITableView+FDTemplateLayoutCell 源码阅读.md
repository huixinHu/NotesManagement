# UITableViewCell 高度计算
**UITableView 询问 cell 高度有两种方式**：

1. ```rowHeight```属性。所有Cell都为固定高度，这种情况下最好不要使用下面第2种方法。

2. ```- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath```代理方法，它会使rowHeight属性的设置失效。

在自定义tableViewCell的时候，是否想过先在```cellForRow...```方法里设置了数据模型，然后获得cell准确高度，再在```heightForRow...```方法设置高度？但```heightForRow...```是比```cellForRow...```要先调用的，也就是调用```heightForRow...```时还不知道行高。

**实际加载tableView的过程中发现，tableView几个代理方法调用顺序如下**：

1. 调用```numberOfRow...```等询问有多少个cell
2. 调用```heightForRow...```n次，n=cell的总个数
3. 对当前一屏显示的x个cell，先调用```cellForRow...```绘制，再调用```heightForRow...```（依次交替调用x次）
4. 当屏幕滚动，有新的cell出现在屏幕上，同3，先调```cellForRow...```再调```heightForRow...```

tableView继承自scrollView ，它需要知道自己的contentSize。因此它在一开始加载的时候，对每个cell使用代理方法获得它的高度 方便得到contentSize，进而得到滚动进度条的位置。但是，如果cell太多，那么在首次加载的时候，会引发性能问题，浪费了多余的计算在屏幕外边的 cell 上。

iOS7以后出现了预估高度```estimatedRowHeight```
对应有：```tableView: estimatedHeightForRowAtIndexPath:```
如果设置了估算高度，避免了一开始调用n次```heightForRow```导致的一些不必要的计算，而是直接用预估高度*cell个数来计算contentSize。当在绘制一个单元格时，才去获取它的准确高度。（步骤1、3、4不变）

但是估算高度也有不足的地方：[优化UITableViewCell高度计算的那些事](http://blog.sunnyxx.com/2015/05/17/cell-height-calculation/)

> 1.设置估算高度后，contentSize.height 根据“cell估算值 x cell个数”计算，这就导致滚动条的大小处于不稳定的状态，contentSize 会随着滚动从估算高度慢慢替换成真实高度，肉眼可见滚动条突然变化甚至“跳跃”。
> 
> 2.若是有设计不好的下拉刷新或上拉加载控件，或是 KVO 了 contentSize 或 contentOffset 属性，有可能使表格滑动时跳动。
> 
> 3.估算高度设计初衷是好的，让加载速度更快，那凭啥要去侵害滑动的流畅性呢，用户可能对进入页面时多零点几秒加载时间感觉不大，但是滑动时实时计算高度带来的卡顿是明显能体验到的，个人觉得还不如一开始都算好了呢（iOS8更过分，即使都算好了也会边划边计算）

# UITableView+FDTemplateLayoutCell
iOS8 之前虽然采用 autoLayout 相比 frame layout 得手动计算已经简化了不少：设置 estimatedRowHeight 属性、对cell设置正确的约束、contentView 执行 systemLayoutSizeFittingSize: 方法。但需要维护专门为计算高度而生的模板cell，以及UILabel 折行问题等。

iOS8后出现self-sizing cell，设置好约束后，直接设置 estimatedRowHeight 就可以了。但是cell高度没有缓存机制，不论何时都会重新计算 cell 高度。这样就会导致滑动不流畅。

优化的方式：对于已经计算了高度的 Cell，就将这个高度缓存起来，下次调用```heightForRow...```方法时，返回高度缓存就行了。**UITableView+FDTemplateLayoutCell**这个第三方开源主要做的就是这个事。

### 高度缓存
#### 1.FDIndexPathHeightCache缓存策略
- 创建了一个类FDIndexPathHeightCache来进行高度缓存的创建、存取。

 针对横屏\竖屏分别声明了 2 个以 indexPath 为索引的二维数组来存储高度（section、row - 二维）。第一维定位到 Section，后一维定位到 Row，这样就可以同时管到 Sections 和 Rows 的数据变动。

 ```objective-c
 typedef NSMutableArray<NSMutableArray<NSNumber *> *> FDIndexPathHeightsBySection;

 @interface FDIndexPathHeightCache ()
 @property (nonatomic, strong) FDIndexPathHeightsBySection *heightsBySectionForPortrait;//竖屏时的基于indexPath高度缓存
 @property (nonatomic, strong) FDIndexPathHeightsBySection *heightsBySectionForLandscape;//横屏时的基于indexPath高度缓存
 @end
```

 使用indexPath 作为索引，在发生删除or插入单元格之后，缓存中的索引就需要进行相应的变动，使用NSMutableArray能很方便适应这种变动。

 如何创建高度缓存、分配空间、初始化高度为-1，以及赋高度值到缓存数组中储存和从缓存中取高度值，这些阅读源码都可以很好理解，这里不多说。

- 分类 UITableView (FDIndexPathHeightCache)

 ```objective-c
 @implementation UITableView (FDIndexPathHeightCache)
//懒加载？高度缓存
 - (FDIndexPathHeightCache *)fd_indexPathHeightCache {
    FDIndexPathHeightCache *cache = objc_getAssociatedObject(self, _cmd);
    if (!cache) {
        [self methodSignatureForSelector:nil];
        cache = [FDIndexPathHeightCache new];//执行init方法，初始化了两个横屏、竖屏时的高度数组
        objc_setAssociatedObject(self, _cmd, cache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return cache;
}
@end
```

 在UITableView+FDTemplateLayoutCell 框架中多处使用了runtime 的关联对象**Associated Object**来进行给类添加公有和私有变量。_cmd表示当前方法的Selector。

 OC 中可以通过 Category 给一个现有的类添加属性，但是却不能添加实例变量(即下划线变量，不过一般说法是不能添加属性)，这个“缺点”可以通过 Associated Objects 来弥补。Associated Objects的使用样例：1. 添加私有属性用于更好地去实现细节。2.添加public属性来增强category的功能。3.创建一个用于KVO的关联观察者。
 
 关联是可以保证被关联的对象在关联对象的整个生命周期都是可用的。

 **关联对象** 在这里的作用就相当于是懒加载，就是在用到相关的缓存策略时才会初始化（这里就初始化了横竖屏时的两个二维数组）。另外，它将内存的释放托管给了 UITableView 实例的生命周期，不用管释放内存的事情了。
 [Objective-C Associated Objects 的实现原理](http://blog.leichunfeng.com/blog/2015/06/26/objective-c-associated-objects-implementation-principle/#jtss-tsina)

 ps:```[self methodSignatureForSelector:nil];```这句runtime的没太懂什么作用。

- 分类 UITableView (FDIndexPathHeightCacheInvalidation)

 ```objective-c
// We just forward primary call, in crash report, top most method in stack maybe FD's,
// but it's really not our bug, you should check whether your table view's data source and
// displaying cells are not matched when reloading.
static void __FD_TEMPLATE_LAYOUT_CELL_PRIMARY_CALL_IF_CRASH_NOT_OUR_BUG__(void (^callout)(void)) {
    callout();
}
#define FDPrimaryCall(...) do {__FD_TEMPLATE_LAYOUT_CELL_PRIMARY_CALL_IF_CRASH_NOT_OUR_BUG__(^{__VA_ARGS__});} while(0)//宏定义.__VA_ARGS_ 就是直接将括号里的...转化为实际的字符
```

 调试时用的？看调用栈？没看太懂 。注释：“在崩溃报告中，调用栈顶的方法可能是FD的方法，要检查一下当reload时dataSource和正在显示的cell是否不对应。”

**更新处理**

```objective-c
  + (void)load {
    // All methods that trigger height cache's invalidation  9个方法
    SEL selectors[] = {
        @selector(reloadData),
        @selector(insertSections:withRowAnimation:),
        @selector(deleteSections:withRowAnimation:),
        @selector(reloadSections:withRowAnimation:),
        @selector(moveSection:toSection:),
        @selector(insertRowsAtIndexPaths:withRowAnimation:),
        @selector(deleteRowsAtIndexPaths:withRowAnimation:),
        @selector(reloadRowsAtIndexPaths:withRowAnimation:),
        @selector(moveRowAtIndexPath:toIndexPath:)
    };
    
    for (NSUInteger index = 0; index < sizeof(selectors) / sizeof(SEL); ++index) {
        SEL originalSelector = selectors[index];
        SEL swizzledSelector = NSSelectorFromString([@"fd_" stringByAppendingString:NSStringFromSelector(originalSelector)]);
        Method originalMethod = class_getInstanceMethod(self, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(self, swizzledSelector);
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}
```

```
 - (void)fd_reloadData {//重写的reload方法，替换tableView里的reload方法
    if (self.fd_indexPathHeightCache.automaticallyInvalidateEnabled) {
        [self.fd_indexPathHeightCache enumerateAllOrientationsUsingBlock:^(FDIndexPathHeightsBySection *heightsBySection) {
            [heightsBySection removeAllObjects];
        }];
    }
    FDPrimaryCall([self fd_reloadData];);//不是递归调用。是调用原来的方法？
}
```

IndexPathHeightCache 在实现上需要在插入、删除cell变动时更新高度缓存。
有种做法是：子类化uitableview,重写相关方法，然后使用这些子类。FDIndexPathHeightCache重写了UITableView的9个触发刷新的相关方法，并利用 runtime 的```method_exchangeImplementations```函数对这9个方法做了替换，对高度缓存进行更新。这种做法更加简单灵活。

这里在+load方法里，利用 Runtime 特性把一个方法的实现与另一个方法的实现进行替换，实现Method Swizzling 。

[Objective C类方法load和initialize的区别](http://www.cnblogs.com/ider/archive/2012/09/29/objective_c_load_vs_initialize.html)

[Method Swizzling 和 AOP 实践](http://tech.glowing.com/cn/method-swizzling-aop/)

[Objective-C Method Swizzling 的最佳实践](http://blog.leichunfeng.com/blog/2015/06/14/objective-c-method-swizzling-best-practice/)

```objective-c
//用于需要刷新数据但不想移除原有缓存数据（框架内对 reloadData 方法的处理是清空缓存）时调用，比如常见的“下拉加载更多数据”操作。
 - (void)fd_reloadDataWithoutInvalidateIndexPathHeightCache {
    FDPrimaryCall([self fd_reloadData];);
}
```

用于需要刷新数据但不想移除原有缓存数据（框架内对 reloadData 方法的处理是清空缓存）时调用，比如常见的“下拉加载更多数据”操作。

#### 2.FDKeyedHeightCache缓存策略
除了提供了indexPath作为索引的方式，还提供了另外一个 API：把数据模型的唯一标识key用作索引

```objective-c
- (CGFloat)fd_heightForCellWithIdentifier:(NSString *)identifier cacheByKey:(id<NSCopying>)key configuration:(void (^)(id cell))configuration;
```

FDKeyedHeightCache采用字典做缓存，没有复杂的数组构建、存取操作，源码实现上相比于FDIndexPathHeightCache要简单得多。当然，在删除、插入、刷新 相关的缓存操作并没有实现，因此需要开发者来自己完成。

> 一般来说 cacheByIndexPath: 方法最为“傻瓜”，可以直接搞定所用问题。cacheByKey: 方法稍显复杂（需要关注数据刷新），但在缓存机制上相比 cacheByIndexPath: 方法更为高效。因此，像类似微博、新闻这种会拥有唯一标识的 cell 数据模型，更建议使用cacheByKey: 方法。

如果cell高度发生变化（数据源改变），那么需要手动对高度缓存进行处理:

```objective-c
- (void)invalidateHeightForKey:(id<NSCopying>)key {
    [self.mutableHeightsByKeyForPortrait removeObjectForKey:key];
    [self.mutableHeightsByKeyForLandscape removeObjectForKey:key];
}

- (void)invalidateAllHeightCache {
    [self.mutableHeightsByKeyForPortrait removeAllObjects];
    [self.mutableHeightsByKeyForLandscape removeAllObjects];
}
```

### 高度获取 
- 获取高度的过程：以indexPath为例，key的实现大致相同。

 ```objective-c
 //FDSimulatedCacheModeCacheByIndexPath模式。建立基于indexpath的高度缓存数组（空间），返回高度
 - (CGFloat)fd_heightForCellWithIdentifier:(NSString *)identifier cacheByIndexPath:(NSIndexPath *)indexPath configuration:(void (^)(id cell))configuration {
    if (!identifier || !indexPath) {
        return 0;
    }
    
    // Hit cache 已经建立了高度缓存，命中缓存
    if ([self.fd_indexPathHeightCache existsHeightAtIndexPath:indexPath]) {
        //debug打印
        [self fd_debugLog:[NSString stringWithFormat:@"hit cache by index path[%@:%@] - %@", @(indexPath.section), @(indexPath.row), @([self.fd_indexPathHeightCache heightForIndexPath:indexPath])]];
        //返回缓存中的高度
        return [self.fd_indexPathHeightCache heightForIndexPath:indexPath];
    }
    //还没建立高度缓存。调用fd_heightForCellWithIdentifier: configuration: 方法计算获得 cell 高度
    CGFloat height = [self fd_heightForCellWithIdentifier:identifier configuration:configuration];//创建templateCell，计算高度
    [self.fd_indexPathHeightCache cacheHeight:height byIndexPath:indexPath];//插入缓存
    [self fd_debugLog:[NSString stringWithFormat: @"cached by index path[%@:%@] - %@", @(indexPath.section), @(indexPath.row), @(height)]];
    
    return height;
}
```

 这里```- (CGFloat)fd_heightForCellWithIdentifier:(NSString *)identifier configuration:(void (^)(id cell))configuration```方法对应FDSimulatedCacheModeNone模式（没有建立缓存）。用于创建、配置一个和tableview cell 布局相同的TemplateCell（模板cell），并计算它的高度。

- 创建模板cell

 ```objective-c
//返回一个template Cell
 - (__kindof UITableViewCell *)fd_templateCellForReuseIdentifier:(NSString *)identifier {
    NSAssert(identifier.length > 0, @"Expect a valid identifier - %@", identifier);
    //储存单元格的字典。一种identifier对应一个templateCell
    NSMutableDictionary<NSString *, UITableViewCell *> *templateCellsByIdentifiers = objc_getAssociatedObject(self, _cmd);
    if (!templateCellsByIdentifiers) {
        templateCellsByIdentifiers = @{}.mutableCopy;
        objc_setAssociatedObject(self, _cmd, templateCellsByIdentifiers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }//懒加载
    
    UITableViewCell *templateCell = templateCellsByIdentifiers[identifier];
    
    if (!templateCell) {
        templateCell = [self dequeueReusableCellWithIdentifier:identifier];
        NSAssert(templateCell != nil, @"Cell must be registered to table view for identifier - %@", identifier);
        templateCell.fd_isTemplateLayoutCell = YES;//runtime关联。不过这个属性的get方法似乎没有被调用。使用 UITableViewCell 模板Cell计算高度，通过 fd_isTemplateLayoutCell 可在Cell内部判断当前是否是模板Cell。可以省去一些与高度无关的操作。
        templateCell.contentView.translatesAutoresizingMaskIntoConstraints = NO;
        templateCellsByIdentifiers[identifier] = templateCell;
        [self fd_debugLog:[NSString stringWithFormat:@"layout cell created - %@", identifier]];
    }
    
    return templateCell;
}
```

 fd_isTemplateLayoutCell属性：模板cell仅用来计算高度，通过 fd_isTemplateLayoutCell 可在Cell内部判断当前是否是模板Cell。若是模板cell可以省去一些与高度计算无关的操作。

 ![](http://upload-images.jianshu.io/upload_images/1727123-4f57dc5ca907c0d9.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

- templateCell高度计算

 ```- (CGFloat)fd_systemFittingHeightForConfiguratedCell:(UITableViewCell *)cell ```中有段注释说明算高的流程：

 ```
    // If not using auto layout, you have to override "-sizeThatFits:" to provide a fitting size by yourself.
    // This is the same height calculation passes used in iOS8 self-sizing cell's implementation.
    //
    // 1. Try "- systemLayoutSizeFittingSize:" first. (skip this step if 'fd_enforceFrameLayout' set to YES.)
    // 2. Warning once if step 1 still returns 0 when using AutoLayout
    // 3. Try "- sizeThatFits:" if step 1 returns 0
    // 4. Use a valid height or default row height (44) if not exist one
```

 默认情况下是使用autoLayout的(fd_enforceFrameLayout属性默认为NO)，如果使用的是frameLayout则设置fd_enforceFrameLayout为YES，代码会根据你使用的layout模式来计算template Cell的高度。使用autoLayout的用systemLayoutSizeFittingSize:方法。使用frameLayout需要在自定义Cell里重写sizeThatFit:方法。如果两种模式都没有使用，单元格高度设为默认的44。
fd_enforceFrameLayout属性不需要手动设置：```it will automatically choose a proper mode by whether you have set auto layout constrants on cell's content view. ```

 **关于UILable的问题**：
 
 > 当 UILabel 行数大于0时，需要指定 preferredMaxLayoutWidth 后它才知道自己什么时候该折行。这是个“鸡生蛋蛋生鸡”的问题，因为 UILabel 需要知道 superview 的宽度才能折行，而 superview 的宽度还依仗着子 view 宽度的累加才能确定。

 框架中的做法是：先计算contentView的宽度，然后对contentView添加宽度约束，然后使用systemLayoutSizeFittingSize：计算获得高度，计算完成以后移除contentView的宽度约束。
 
 ```objective-c
CGFloat contentViewWidth = CGRectGetWidth(self.frame);//先设置contentView的宽度等于tableView的宽度
    
    // If a cell has accessory view or system accessory type, its content view's width is smaller
    // than cell's by some fixed values.
    //如果单元格有accessory类型或者accessory子视图的，contentView的宽度要减去这一部分
    if (cell.accessoryView) {        contentViewWidth -= 16 + CGRectGetWidth(cell.accessoryView.frame);
    } else {
        static const CGFloat systemAccessoryWidths[] = {
            [UITableViewCellAccessoryNone] = 0,
            [UITableViewCellAccessoryDisclosureIndicator] = 34,
            [UITableViewCellAccessoryDetailDisclosureButton] = 68,
            [UITableViewCellAccessoryCheckmark] = 40,
            [UITableViewCellAccessoryDetailButton] = 48
        };
        contentViewWidth -= systemAccessoryWidths[cell.accessoryType];
    }

    CGFloat fittingHeight = 0;
    
    if (!cell.fd_enforceFrameLayout && contentViewWidth > 0) {//不使用frameLayout
        // Add a hard width constraint to make dynamic content views (like labels) expand vertically instead
        // of growing horizontally, in a flow-layout manner.
        NSLayoutConstraint *widthFenceConstraint = [NSLayoutConstraint constraintWithItem:cell.contentView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:contentViewWidth];//宽度约束
        [cell.contentView addConstraint:widthFenceConstraint];
        
        // Auto layout engine does its math
        fittingHeight = [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;//算高
        [cell.contentView removeConstraint:widthFenceConstraint];//移除宽度约束
        
        [self fd_debugLog:[NSString stringWithFormat:@"calculate using system fitting size (AutoLayout) - %@", @(fittingHeight)]];
    }
```

 如果使用的是frameLayout，重写sizeThatFits:并用数据内容来反算高度。
 
 `fittingHeight = [cell sizeThatFits:CGSizeMake(contentViewWidth, 0)].height;`

```objective-c
 - (CGSize)sizeThatFits:(CGSize)size {
    CGFloat totalHeight = 0;
    totalHeight += [self.titleLabel sizeThatFits:size].height;
    totalHeight += [self.contentLabel sizeThatFits:size].height;
    totalHeight += [self.contentImageView sizeThatFits:size].height;
    totalHeight += [self.usernameLabel sizeThatFits:size].height;
    totalHeight += 40; // margins
    return CGSizeMake(size.width, totalHeight);
}
```

 最后视情况而定是否需要加上分割线高度：
 
 ```objective-c
     if (self.separatorStyle != UITableViewCellSeparatorStyleNone) {
        fittingHeight += 1.0 / [UIScreen mainScreen].scale;
    }
 ```

### 其他
`__kindof`:一般用在方法的返回值，返回类或者其子类都是合法的。

### 使用
注意的地方：

1. 使用storyboard创建cell，要保证 contentView 内部上下左右所有方向都有约束支撑。

2. 使用代码或 XIB 创建的 cell，使用以下注册方法:

 ```objective-c
- (void)registerClass:(nullableClass)cellClassforCellReuseIdentifier:(NSString *)identifier;
- (void)registerNib:(nullableUINib *)nibforCellReuseIdentifier:(NSString *)identifier;
```

3. cell通过-dequeueCellForReuseIdentifier:来创建。

4. 在```-tableView:heightForRowAtIndexPath: ```方法中调用cacheByIndexPath或者cacheByKey的方法完成高度缓存的创建和获取。

 ```objective-c
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [tableView fd_heightForCellWithIdentifier:@"identifer" cacheByIndexPath:indexPath configuration:^(id cell) {
        // configurations
    }];
}

 - (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    Entity *entity = self.entities[indexPath.row];
    return [tableView fd_heightForCellWithIdentifier:@"identifer" cacheByKey:entity.uid configuration:^(id cell) {
        // configurations
    }];
}
```

5. 不需要再设置estimatedRowHeight属性

这里以使用autolayout的情况为例，使用frameLayout的情况不作说明，以下demo数据来自原作demo。

- 使用storyboard

UITableView+FDTemplateLayoutCell框架中的demo就是使用storyboard实现的，非常简单易懂不作过多说明。下面说一些要注意的地方：

在子线程解析json数据然后再回到主线程刷新tableView。以前自己一般的做法是设置一个NSMutableArray类型属性用来储存模型数据，然后在懒加载中解析数据。

![](http://upload-images.jianshu.io/upload_images/1727123-2c096e041dba5004.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 imageview 的mode设置为aspect fit，在保持长宽比的前提下，缩放图片，使得图片在容器内完整显示出来。
 
![imageView注意1.png](http://upload-images.jianshu.io/upload_images/1727123-cb6494e9610fc067.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

然后imageView的右约束是一个不等于约束，intrinsic size 设为placeholder。这是因为：如果内容是运行时决定的如UIImageView，若图片是从服务器下载的，那么我们就需要放一个空的UIImageView，不包含所显示的图片，不过这样会因未设置图片导致imageView尺寸无法确定，storyboard抛出错误，解决方案便是放一个临时的占位尺寸来告诉sotryboard。

![imageView注意2.png](http://upload-images.jianshu.io/upload_images/1727123-a97d780dc7cf5dad.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

- 使用纯代码，autolayout

参照storyboard约束设置用纯代码写约束条件。

自定义cell里面的实现：初始化的方法内部创建子控件并且使用Masonry布局

![](http://upload-images.jianshu.io/upload_images/1727123-2d961cc98f88a136.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

initSubview方法的实现，保证 contentView 内部上下左右所有方向都有约束支撑：

![](http://upload-images.jianshu.io/upload_images/1727123-4f617579e6a224d8.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

ps:这样子设置约束还是会有点问题（包括原作的例子），想想如果标题、正文内容、图片或者名字其中一个子控件赋值为空，但是约束仍然存在，这种情况下应该怎样处理。

更新：解决办法。

```objective-c
 #import "HXTableViewCell.h"
 #import "Masonry.h"
 @interface HXTableViewCell()
 @property (weak, nonatomic) UILabel *title;
 @property (weak, nonatomic) UILabel *content;
 @property (weak, nonatomic) UILabel *name;
 @property (weak, nonatomic) UILabel *time;
 @property (weak, nonatomic) UIImageView *image;
  
 @property (nonatomic,strong) MASConstraint *contentConstraint;
 @property (nonatomic,strong) MASConstraint *imgConstraint;
 @property (nonatomic,strong) MASConstraint *titleConstraint;
 @end
 
 @implementation HXTableViewCell
 - (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self initSubView];
    }
    return self;
}
 
 - (void)setDatamodel:(DataModel *)datamodel{
    _datamodel = datamodel;
    self.title.text = datamodel.title;
    self.content.text = datamodel.content;
    self.name.text = datamodel.username;
    self.time.text = datamodel.time;
    self.image.image = datamodel.imageName.length > 0 ? [UIImage imageNamed:datamodel.imageName] : nil;
 
    self.title.text.length ==  0 ? [self.titleConstraint deactivate]:[self.titleConstraint activate];
    self.content.text.length ==  0 ? [self.contentConstraint deactivate]:[self.contentConstraint activate];
    self.image.image == nil ? [self.imgConstraint deactivate]:[self.imgConstraint activate];
}

 - (void)initSubView{
    UILabel *title = [[UILabel alloc]init];
    _title = title;
    _title.numberOfLines = 0;//多行文字
    [self.contentView addSubview:_title];
     
    UILabel *content = [[UILabel alloc]init];
    _content = content;
    _content.numberOfLines = 0;//多行文字
    [self.contentView addSubview:_content];
     
    UILabel *name = [[UILabel alloc]init];
    _name = name;
    _name.font = [UIFont systemFontOfSize:14.0];
    [self.contentView addSubview:_name];
     
    UILabel *time = [[UILabel alloc]init];
    _time = time;
    _time.font = [UIFont systemFontOfSize:14.0];
    [self.contentView addSubview:_time];
     
    UIImageView *image = [[UIImageView alloc]init];
    _image = image;
    _image.contentMode = UIViewContentModeScaleAspectFill;
    [self.contentView addSubview:_image];
     
    int padding = 20;
    __weak typeof(self) weakself = self;
    [_title mas_makeConstraints:^(MASConstraintMaker *make) {
        //以下设置距离contentView的边距,设置两条优先度不同的约束，内容为空时将优先度高的约束禁用
        make.top.equalTo(weakself.contentView).priorityLow();
        weakself.titleConstraint = make.top.mas_equalTo(weakself.contentView).offset(20).priorityHigh();
         
        make.left.mas_equalTo(weakself.contentView).offset(padding);
        make.right.mas_equalTo(weakself.contentView.mas_right).offset(-padding);
    }];
    [_content mas_makeConstraints:^(MASConstraintMaker *make) {
        //以下设置距离title的边距,设置两条优先度不同的约束，内容为空时将优先度高的约束禁用
        make.top.equalTo(_title.mas_bottom).priorityLow();
        weakself.contentConstraint = make.top.mas_equalTo(_title.mas_bottom).offset(20).priorityHigh();
         
        make.leading.mas_equalTo(_title.mas_leading);
        make.right.mas_equalTo(weakself.contentView.mas_right).offset(-padding);
    }];
     
    [_image mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_content.mas_bottom).priorityLow();
        weakself.imgConstraint = make.top.mas_equalTo(weakself.content.mas_bottom).offset(20).priorityHigh();
         
        make.leading.mas_equalTo(_title.mas_leading);
    }];
    [_name mas_makeConstraints:^(MASConstraintMaker *make) {
        make.leading.mas_equalTo(_title.mas_leading);
        make.top.mas_equalTo(_image.mas_bottom).offset(20);
         make.bottom.mas_equalTo(weakself.contentView.mas_bottom).offset(-10);
    }];
    [_time mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.mas_equalTo(weakself.contentView.mas_right).offset(-padding);
        make.baseline.mas_equalTo(_name.mas_baseline);
    }];
}
@end
```

 控制器中的实现：基本和原作demo中的差不多，一定要使用```- registerClass:forCellReuseIdentifier:```方法注册。而且应该像原作demo中在子线程解析json数据然后再回到主线程刷新tableView

 有个奇怪的现象：如果vc中的数据模型是二维数组（section \row）的话只会计算、缓存一次高度。如果是一维数组，就会计算、缓存两次高度（重复两次）。不知道为什么。代码如下：
 
```objective-c
 - (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.fd_debugLogEnabled = YES;
    [self buildTestDataThen:^{
        [self.tableView reloadData];
    }];
}

 - (void)buildTestDataThen:(void (^)(void))then{
    // Simulate an async request
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // Data from `data.json`
        NSString *dataFilePath = [[NSBundle mainBundle] pathForResource:@"data" ofType:@"json"];
        NSData *data = [NSData dataWithContentsOfFile:dataFilePath];
        NSDictionary *rootDict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
        NSArray *feedDicts = rootDict[@"feed"];
        
        // Convert to `FDFeedEntity`
        NSMutableArray *entities = @[].mutableCopy;
        [feedDicts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [entities addObject:[[DataModel alloc] initWithDictionary:obj]];
        }];
        self.cellData = entities;
        
        // Callback
        dispatch_async(dispatch_get_main_queue(), ^{
            !then ?: then();
        });
    });
}

 - (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
 
 - (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
 
 - (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.cellData count];
}
 
 - (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    HXTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FDDemo"];
    [self configureCell:cell atIndexPath:indexPath];
    return cell;
}
 
  - (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    return [tableView fd_heightForCellWithIdentifier:@"FDDemo" cacheByIndexPath:indexPath configuration:^(HXTableViewCell *cell) {
        [self configureCell:cell atIndexPath:indexPath];
    }];
}
 
 - (void)configureCell:(HXTableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    cell.fd_enforceFrameLayout = NO; 
    cell.datamodel = self.cellData[indexPath.row];
}
```


参考文章：

[UITableViewCell 自动高度](http://www.jianshu.com/p/7a96c97460a4)

[优化UITableViewCell高度计算的那些事](http://blog.sunnyxx.com/2015/05/17/cell-height-calculation/)

[UITableView+FDTemplateLayoutCell 框架学习](http://www.tuicool.com/articles/YniYNnb)

[UITableView-FDTemplateLayoutCell源码分析](http://www.jianshu.com/p/5fc142ab8573)

[有了Auto Layout,为什么你还是害怕写UITabelView的自适应布局?](https://segmentfault.com/a/1190000003784416)

[使用Autolayout实现UITableView的Cell动态布局和高度动态改变](http://codingobjc.com/blog/2014/10/15/shi-yong-autolayoutshi-xian-uitableviewde-celldong-tai-bu-ju-he-ke-bian-xing-gao/index.html)

更新：

关于UITableView+FDTemplateLayoutCell的1.2版本中利用RunLoop空闲时间执行预缓存任务（虽然预缓存功能因为下拉刷新的冲突和不明显的收益已经废弃）

sunny博客原文在这一部分已经讲述得比较清楚了，这里总结一下

先来看看runloop内部逻辑:

![RunLoop 内部的逻辑](http://upload-images.jianshu.io/upload_images/1727123-b4ab8057db973958.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

预缓存高度 要求页面处于空闲状态时才执行高度计算，当用户正在滑动列表时不应该执行计算任务影响滑动体验，需要在最无感知的时刻进行，所以应该同时满足：

1. RunLoop 处于“空闲”状态（defaultMode）
2. 当这一次 RunLoop 迭代处理完成了所有事件，马上要休眠时

注册 RunLoopObserver 可以观测当前 RunLoop 的运行状态，每个 Observer 都包含了一个回调（函数指针），当 RunLoop 的状态发生变化时，观察者就能通过回调接受到这个变化。可以观测的时间点有以下几个：

```
在源代码中对应的就是：
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry         = (1UL << 0), // 即将进入Loop
    kCFRunLoopBeforeTimers  = (1UL << 1), // 即将处理 Timer
    kCFRunLoopBeforeSources = (1UL << 2), // 即将处理 Source
    kCFRunLoopBeforeWaiting = (1UL << 5), // 即将进入休眠
    kCFRunLoopAfterWaiting  = (1UL << 6), // 刚从休眠中唤醒
    kCFRunLoopExit          = (1UL << 7), // 即将退出Loop
};
```

FD框架里面做的主要两个事情：

1.创建observer观测runloop即将进入休眠（kCFRunLoopBeforeWaiting），

2.在observer的回调里收集、分发任务（分发到多个runloop中执行避免卡主线程）。
利用performSelector这个api创建一个 Source 0 任务，分发到指定线程的 RunLoop 中，在给定的 Mode 下执行，若指定的 RunLoop 处于休眠状态，则唤醒它处理事件（上面图中第七步，source0任务可以唤醒runloop）

```objective-c
- (void)performSelector:(SEL)aSelector
               onThread:(NSThread *)thr
             withObject:(id)arg
          waitUntilDone:(BOOL)wait
                  modes:(NSArray *)array;
```

参考：
[深入理解RunLoop](http://blog.ibireme.com/2015/05/18/runloop/)

[Cocoa深入学习:NSOperationQueue、NSRunLoop和线程安全](https://blog.cnbluebox.com/blog/2014/07/01/cocoashen-ru-xue-xi-nsoperationqueuehe-nsoperationyuan-li-he-shi-yong/)