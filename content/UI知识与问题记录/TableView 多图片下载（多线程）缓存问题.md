### 一些前期准备
最终效果需求：界面使用storyboard搭建

![](http://upload-images.jianshu.io/upload_images/1727123-3f0da48f297bc0f1.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

plist文件定义：

![](http://upload-images.jianshu.io/upload_images/1727123-a8dd4d0377f82737.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

数据模型：

```objective-c
#import "DataModel.h"
@implementation DataModel
+(instancetype)appInfoFromDic:(NSDictionary *)dic{
    DataModel *appInfo = [[DataModel alloc] init];    
    [appInfo setValuesForKeysWithDictionary:dic];    
    return appInfo;
}
@end
```

自定义cell：

```objective-c
#import "HXCustomCell.h"
@implementation HXCustomCell
- (void)awakeFromNib {
    // Initialization code
}

-(void)setAppInfo:(DataModel *)appInfo{
    self.name.text = appInfo.name;
    self.dowload.text = appInfo.download;
    //设置占位图片，这里直接在storyboard中设置好了
//    self.icon.image = [UIImage imageNamed:@"user_default"];
}
@end
```

vc中用一个数组保存所有模型数据

```objective-c
/** 所有数据 */
@property (nonatomic, strong) NSArray *apps;
- (NSArray *)apps
{
    if (!_apps) {
        NSArray *dictArray = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"apps.plist" ofType:nil]];
        
        NSMutableArray *appArray = [NSMutableArray array];
        for (NSDictionary *dict in dictArray) {
            [appArray addObject:[DataModel appInfoFromDic:dict]];
        }
        _apps = appArray;
    }
    return _apps;
}
```

### 图片加载
在cell生成的时候下载图片，由于图片下载是耗时操作，用同步方式去下载图片的时候，系统无法很快执行界面渲染，导致“卡主线程”tableview滑动不流畅。因此图片下载要放在子线程中执行，下载后回到主线程显示图片。如下：

```objective-c
/** 队列对象 */
@property (nonatomic, strong) NSOperationQueue *queue;
- (NSOperationQueue *)queue
{
    if (!_queue) {
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 3;//最大并发数
    }
    return _queue;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *ID = @"app";
    HXCustomCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    DataModel *appModel = self.apps[indexPath.row];
    cell.appInfo = appModel;
    NSBlockOperation *downloadIMG = [NSBlockOperation blockOperationWithBlock:^{
        NSLog(@"下载图片%@",appModel.name);
        // 下载图片
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:appModel.icon]];
        UIImage *image = [UIImage imageWithData:data];
        // [NSThread sleepForTimeInterval:1.0];//模拟网络延时
        // 回到主线程显示图片
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            cell.icon.image = image;
        }];
    }];
    [self.queue addOperation:downloadIMG];
    return cell;
}
@end
```
如上，主线程不卡了，但有新的问题出现：**频繁滚动时，图片可能错位(可以把上面模拟网络延时的代码取消注释运行查看)，并且图片来回跳，反复下载相同图片（来回拖动tableview，从上面代码的控制台输出看到“下载图片xxx”多次打印）**

1. 先说说反复下载图片。由于cell复用引起，因为每行单元格只要显示出来就至少要调用一次```cellForRow.....```方法来获得它需要显示的数据。

解决办法：**内存缓存**

图片下载完就用一个字典缓存起来。每次调用到tableview代理方法时，先从内存缓存中取图片，取不到再下载图片然后存到数组中。

```objective-c
/** 内存缓存的图片 */
@property (nonatomic, strong) NSMutableDictionary *images;
- (NSMutableDictionary *)images
{
    if (!_images) {
        _images = [NSMutableDictionary dictionary];
    }
    return _images;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *ID = @"app";
    HXCustomCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];  
    cell.icon.image = nil;
    DataModel *appModel = self.apps[indexPath.row];
    cell.appInfo = appModel;
    UIImage *image = self.images[appModel.icon];
    if (image) { // 内存中有图片
        NSLog(@"内存缓存%@",appModel.name);
        cell.icon.image = image;
    }else{
        NSBlockOperation *downloadIMG = [NSBlockOperation blockOperationWithBlock:^{
            NSLog(@"下载图片%@",appModel.name);
            // 下载图片
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:appModel.icon]];
            UIImage *image = [UIImage imageWithData:data];
            [NSThread sleepForTimeInterval:1.0];//模拟网络延时
            // 回到主线程显示图片
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
               [self.images setObject:image forKey:appModel.icon];//把图片放到数组缓存起来
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            }];
        }];
        [self.queue addOperation:downloadIMG];
    }
    return cell;
}
```

然而！这样还是不能彻底解决多次下载图片的问题！想想如果滑动过快而网络不佳等原因图片加载延时，这时如果再滑动回去之前的cell，因为图片还没下载好，内存缓存数组里面是取不到数据的，这时还是会再次开启下载。

解决办法：**操作缓存**

每开启了下载就把这个任务（operation对象）用一个字典缓存起来，当下载完成了就把它移除。在内存缓存中取不到图片后，去询问是否有下载任务在进行，没有下载任务再去下载。

```objective-c
//操作缓存
@property(nonatomic,strong) NSMutableDictionary *operationCache;
-(NSMutableDictionary *)operationCache{
    if(!_operationCache){
        _operationCache = [NSMutableDictionary dictionary];
    }
    return _operationCache;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *ID = @"app";
    HXCustomCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];

    cell.icon.image = nil;
    DataModel *appModel = self.apps[indexPath.row];
    cell.appInfo = appModel;
    UIImage *image = self.images[appModel.icon];
    if (image) { // 内存中有图片
        NSLog(@"内存缓存%@",appModel.name);
        cell.icon.image = image;
    }else if (self.operationCache[appModel.icon]){
        //已经在下载了，只是还没下载完
        NSLog(@"图片正在下载,请稍后%@",appModel.name);
    }
    else{
        NSBlockOperation *downloadIMG = [NSBlockOperation blockOperationWithBlock:^{
            NSLog(@"下载图片%@",appModel.name);
            // 下载图片
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:appModel.icon]];
            UIImage *image = [UIImage imageWithData:data];
            [NSThread sleepForTimeInterval:1.0];//模拟网络延时
            // 回到主线程显示图片
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self.operationCache removeObjectForKey:appModel.icon];//把下载操作移出缓存
//                cell.icon.image = image;
                [self.images setObject:image forKey:appModel.icon];//把图片放到数组缓存起来
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            }];
        }];
        [self.operationCache setObject:downloadIMG forKey:appModel.icon];//把还在进行的操作缓存起来
        [self.queue addOperation:downloadIMG];
    }
    return cell;
}
```

![这样就不会重复下载了](http://upload-images.jianshu.io/upload_images/1727123-7021e8261e3a78bf.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

2. 图片“错位”。也是由于cell复用引起的，比如当网络状况不佳，下载图片耗时比较长，当图片还没下载完显示到cell上。由于cell是重用的，如果被重用的cell上有图片数据，那么当前cell显示的图片就是被重用cell的图片了。虽然这个当前cell也会下载当前行需要显示的图片，但直到图片下载好了才会替换掉之前那张图片。

解决办法：在dequeue取得复用的cell后先把图片清空（不管是否真的有内容）。

```objective-c
static NSString *ID = @"app";
HXCustomCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
cell.icon.image = nil;
......
```

而且要注意的是，在主线程刷新图片不要这样写```cell.icon.image = image;```这样还是会出现图片错位的。使用```reloadRowsAtIndexPaths......```方法直接刷新某一行的数据，这个方法会触发调用```cellForRow......```方法

```objective-c
[[NSOperationQueue mainQueue] addOperationWithBlock:^{
//      cell.icon.image = image;
    [self.images setObject:image forKey:appModel.icon];//把图片放到数组缓存起来
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}];
```

3. 最后还有一个问题。当系统内存不足的时候，清除内存缓存，这个时候上下滚动又回去下载之前下载过的图片。又或者退出程序，再次打开app时又重新下载图片了。

解决办法：**用沙盒把数据保存下来**

```objective-c
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *ID = @"app";
    HXCustomCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    cell.icon.image = nil;    
    DataModel *appModel = self.apps[indexPath.row];
    cell.appInfo = appModel;
    
    // 先从内存缓存中取出图片
    UIImage *image = self.images[appModel.icon];
    if (image) { // 内存中有图片
        NSLog(@"内存缓存%@",appModel.name);
        cell.icon.image = image;
    }else if (self.operationCache[appModel.icon]){
        NSLog(@"图片正在下载,请稍后%@",appModel.name);
    }
    else {  // 内存中没有图片
        // 获得Library/Caches文件夹
        NSString *cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        // 获得文件名
        NSString *filename = [appModel.icon lastPathComponent];
        // 计算出文件的全路径
        NSString *file = [cachesPath stringByAppendingPathComponent:filename];
        // 加载沙盒的文件数据
        NSData *data = [NSData dataWithContentsOfFile:file];
//        NSData *data = nil;
        if (data) { // 直接利用沙盒中图片
            UIImage *image = [UIImage imageWithData:data];
            cell.icon.image = image;
            // 存到字典中
            self.images[appModel.icon] = image;
        } else { // 下载图片 queue设置最大并发数
            NSBlockOperation *downloadIMG = [NSBlockOperation blockOperationWithBlock:^{
                NSLog(@"下载图片%@",appModel.name);
                // 下载图片
                NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:appModel.icon]];
//                if (data ==nil) {//如果图片下载不成功
//                    [self.operationCache removeObjectForKey:appModel.icon];
//                    return ;
//                }
                UIImage *image = [UIImage imageWithData:data];
                [NSThread sleepForTimeInterval:1.0];
                // 回到主线程显示图片
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self.operationCache removeObjectForKey:appModel.icon];//把下载操作移出缓存
//                    cell.icon.image = image;//不要这样写，会图片错位
                    if (image == nil) {//如果图片下载不成功
                        return ;
                    }
                    //图片存到字典
                    [self.images setObject:image forKey:appModel.icon];
//                    刷新tableviewcell
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                }];
                // 将图片文件数据写入沙盒中
                [data writeToFile:file atomically:YES];
            }];
            [self.operationCache setObject:downloadIMG forKey:appModel.icon];//把还在进行的操作缓存起来
            [self.queue addOperation:downloadIMG];
        }
    }
    return cell;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    self.images = nil;
    self.operationCache = nil;
    //[self.queue cancelAllOperations];
}
```
ps：沙盒操作，这种读写文件的操作（IO操作）相对比较耗时，放到子线程去做，主线程用来渲染。上面的代码还没把读写操作放子线程。

总结：

![](http://upload-images.jianshu.io/upload_images/1727123-f001678cb2938211.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)