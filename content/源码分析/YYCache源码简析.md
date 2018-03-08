[作者设计思路](https://blog.ibireme.com/2015/10/26/yycache/)

# 1.YYMemoryCache
`YYMemoryCache`负责管理内存缓存。这个类是线程安全的。

### LRU算法的实现
用双向链表和 CFMutableDictionary 实现。存储单元是`_YYLinkedMapNode`（相当于链表结点）。

```objective-c
@interface _YYLinkedMapNode : NSObject {
    //@package 是框架级别的实例变量作用域修饰符，只要处于同一个框架中就可以直接通过变量名访问
    @package
    __unsafe_unretained _YYLinkedMapNode *_prev; // retained by dic 前驱
    __unsafe_unretained _YYLinkedMapNode *_next; // retained by dic 后继
    
    id _key;
    id _value;
    NSUInteger _cost; //内存开销大小
    NSTimeInterval _time;//创建时间？
}
@end

@interface _YYLinkedMap : NSObject {
    @package
    CFMutableDictionaryRef _dic; // do not set object directly 字典，存储结点。使用CFMutableDictionaryRef要比使用oc字典效率高，但是要自己管理内存
    NSUInteger _totalCost; //链表总开销
    NSUInteger _totalCount;//缓存总对象数目
    _YYLinkedMapNode *_head; // MRU, do not change it directly 头结点
    _YYLinkedMapNode *_tail; // LRU, do not change it directly 尾结点
    BOOL _releaseOnMainThread;
    BOOL _releaseAsynchronously;
}
```
`_YYLinkedMapNode `除了包含key value外，还包含该结点的前驱、后继结点地址。
`_YYLinkedMap`双向链表包含了链表首尾结点。双向链表里的对象是按访问时间排序的，因为LRU算法，最后使用的最先淘汰，因此使用双向链表去操作各个Node，一个Node被使用到了就移到链表头。**而为了优化查找时间，就使用了一个字典来保存数据关系。**这个字典用的是CFMutableDictionary而不是NSMutableDictionary，原因可能是前者的效率比较高，毕竟是c的操作，但是要注意手动管理内存的问题。

Node的value值就是要存储的数据对象；CFMutableDictionary字典的value值是Node，key就是Node的key。比如在查询某个node时，根据某个key在字典里面取出对应的node，然后把这个node移到链表头，如果缓存超过设定的上限了，就把链表尾的结点淘汰掉。

另外，可以看到，在`_YYLinkedMapNode`中使用了__unsafe_unretained这个属性。作者在它的[另一篇文章](https://blog.ibireme.com/2015/10/23/ios_model_framework_benchmark/)中提到：
> 避免多余的内存管理方法
在 ARC 条件下，默认声明的对象是 __strong 类型的，赋值时有可能会产生 retain/release 调用，如果一个变量在其生命周期内不会被释放，则使用 __unsafe_unretained 会节省很大的开销。
评论区：关于 __unsafe_unretained 这个属性，我只提到需要在性能优化时才需要尝试使用，平时开发自然是不推荐用的。

`_YYLinkedMap`实现的功能：
- 在链表头部插入结点
- 把结点移到链表头部，一般在结点访问和更新时候会做这个事情。
- 删除结点
都是一些比较简单的链表知识，应该很容易就能看懂，所以就不展开谈了。

### YYMemoryCache的内部实现
成员变量：

```objective-c
    pthread_mutex_t _lock;//锁
    _YYLinkedMap *_lru; //双向链表
    dispatch_queue_t _queue;//串行队列
```

1.初始化

init：主要是对属性进行初始化，以及添加`UIApplicationDidReceiveMemoryWarningNotification`和`UIApplicationDidEnterBackgroundNotification`通知，在程序进入后台以及收到内存不足警告时，清除所有内存缓存。最后，递归调用_trimRecursively方法：

```objective-c
//递归淘汰缓存
- (void)_trimRecursively {
    __weak typeof(self) _self = self;
    //定时清理 5s
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTrimInterval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __strong typeof(_self) self = _self;
        if (!self) return;
        [self _trimInBackground];
        [self _trimRecursively];
    });
}
```

在一个优先级LOW的全局队列中，每5秒执行一次方法_trimInBackground。

```objective-c
//在后台线程进行缓存淘汰
- (void)_trimInBackground {
    //异步串行
    //lock是为了保证内部数据的线程安全，所有访问接口都要经过这个lock。_queue只是用来执行后台检查和移除的逻辑，它内部还是要用Lock来锁住数据的。
    dispatch_async(_queue, ^{
        [self _trimToCost:self->_costLimit];
        [self _trimToCount:self->_countLimit];
        [self _trimToAge:self->_ageLimit];
    });
}
```

在串行队列中异步执行方法`_trimToCost`、`_trimToCount`、`_trimToAge`。_queue只是用来执行后台检查和移除的逻辑，并不能保证线程安全，因此所有的数据访问接口都要lock，比如：

```objective-c
//根据object数量来淘汰
- (void)_trimToCount:(NSUInteger)countLimit {
    BOOL finish = NO;
    //上锁
    pthread_mutex_lock(&_lock);
    if (countLimit == 0) {//数量最大限制=0
        [_lru removeAll];//清空所有数据
        finish = YES;
    } else if (_lru->_totalCount <= countLimit) {//还没达到最大上限
        finish = YES;
    }
    pthread_mutex_unlock(&_lock);//解锁
    if (finish) return;
    
    NSMutableArray *holder = [NSMutableArray new];
    //已缓存>容量上限。从尾后结点开始清除，知道存储总数目<上限
    while (!finish) {
    //非阻塞的锁定互斥锁，pthread_mutex_lock的非阻塞版本，成功返回0
        if (pthread_mutex_trylock(&_lock) == 0) {
            if (_lru->_totalCount > countLimit) {
                _YYLinkedMapNode *node = [_lru removeTailNode];
                if (node) [holder addObject:node];
            } else {
                finish = YES;
            }
            pthread_mutex_unlock(&_lock);//解锁
        } else {
            usleep(10 * 1000); //10 ms 把调用该函数的线程挂起一段时间
        }
    }
    //异步释放被删除的结点
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : YYMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count]; // release in queue
        });
    }
}
```

淘汰到某个大小，如果数量上限是0就全部清空，如果当前链表数目小于数量上限，就不需要淘汰直接返回。如果需要淘汰结点，就在CF字典中删除对应k-v项，把该结点移除出链表，并把链表尾的node拿出来放到一个holder 数组中。直到链表结点总数目小于数量上限。

线程安全是使用pthread_mutex_lock来实现的，因为OSSpinLock已经不再安全了，所以作者后来换用pthread_mutex了。另外，当已缓存对象数目超过容量数目上限，需要从链表尾开始淘汰结点时，使用了pthread_mutex_lock的非阻塞版本的锁：pthread_mutex_trylock，如果锁失败了，就把调用该函数的线程挂起一段时间。

另外在这里有两句代码：

```objective-c
dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : YYMemoryCacheGetReleaseQueue();
dispatch_async(queue, ^{
    [holder count]; // release in queue
});
```

一开始确实没看懂`[holder count]`的调用意图，而且在该代码所在文件中有多处使用了同样的技巧。这里作者给出的解释是：holder 持有了待释放的对象，这些对象应该根据配置在不同线程进行释放(release)。此处 holder 被 block 持有，然后在另外的 queue 中释放。[holder count] 只是为了让 holder 被 block 捕获，保证编译器不会优化掉这个操作，所以随便调用了一个方法。

当block执行完毕，此时holder就会在block对应的queue上release了，这里确实很巧妙。作者在[另一篇文章](https://blog.ibireme.com/2015/11/12/smooth_user_interfaces_for_ios/)中说到：
> 对象的销毁虽然消耗资源不多，但累积起来也是不容忽视的。通常当容器类持有大量对象时，其销毁时的资源消耗就非常明显。同样的，如果对象可以放到后台线程去释放，那就挪到后台线程去。这里有个小 Tip：把对象捕获到 block 中，然后扔到后台队列去随便发送个消息以避免编译器警告，就可以让对象在后台线程销毁了。

代码中很多地方都体现出作者非常注重性能问题，不得不感叹作者写代码确实很讲究。
_trimToCost和_trimToAge方法的实现大致类似，就不展开谈了。

2.增删改查操作

简单谈谈`- (void)setObject:(id)object forKey:(id)key`方法的实现。其他的方法基本上都差不多，实际上就是对node、链表、和CF字典的操作。

`- (void)setObject:(id)object forKey:(id)key`实际上调用的是`- (void)setObject:(id)object forKey:(id)key withCost:(NSUInteger)cost`方法，但cost参数传入的总是0，所以说cost这个维度实际上好像没什么卵用，而且作者也谈到，我们一般不需要太关注cost。

内部实现：

如果key为空，就直接返回；如果object为空，就把key对应的Object删除。
否则，就根据这个key找到对应的node，如果node找得到，就更新这个node的属性以及修改链表totalCost，然后把这个node移到链表头；如果node找不到，就创建一个node并插入到链表头。

最后进行totalCost和totalCount检查，如果缓存超标，就用LRU算法去移除结点并在对应线程中释放。

```objective-c
- (void)setObject:(id)object forKey:(id)key withCost:(NSUInteger)cost {
    if (!key) return;
    if (!object) {//如果object为空，就代表把该key对应项清除
        [self removeObjectForKey:key];
        return;
    }
    pthread_mutex_lock(&_lock);
    _YYLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    NSTimeInterval now = CACurrentMediaTime();//最新修改时间
    //先判断字典里有没有这个key-node值
    if (node) {//如果该key原有对应object//取出某结点，更新字段，把结点移到头部
        //更新链表cost
        _lru->_totalCost -= node->_cost;
        _lru->_totalCost += cost;
        node->_cost = cost;
        node->_time = now;//修改时间
        node->_value = object;
        [_lru bringNodeToHead:node];
    } else {//原key不含object 在链表头部插入新结点
        node = [_YYLinkedMapNode new];
        node->_cost = cost;
        node->_time = now;
        node->_key = key;
        node->_value = object;
        [_lru insertNodeAtHead:node];
    }
    //总开销超出上限，删除链表尾部结点
    if (_lru->_totalCost > _costLimit) {
        //异步串行
        dispatch_async(_queue, ^{
            [self trimToCost:_costLimit];
        });
    }
    //数目超出上限
    if (_lru->_totalCount > _countLimit) {
        _YYLinkedMapNode *node = [_lru removeTailNode];

        if (_lru->_releaseAsynchronously) {
            dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : YYMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                //为了给node增加使用的周期，如果没有在开的queue中调用node的方法，node就会在queue之前被释放掉
                //这样做是为了让node在开的子线程中释放而不是在主线程
                [node class]; //hold and release in queue
            });
        } else if (_lru->_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class]; //hold and release in queue
            });
        }
    }
    pthread_mutex_unlock(&_lock);
}
```

## 2.YYKVStorage
在YYCache中，YYDiskCache负责管理磁盘缓存，而他的核心功能类是YYKVStorage，通过文件+sqlite数据库的方式缓存数据。但YYKVStorage不是线程安全的，YYDiskCache线程安全，作者建议不要直接使用YYKVStorage。

三种数据缓存策略

```objective-c
typedef NS_ENUM(NSUInteger, YYKVStorageType) {
    //文件读写缓存
    YYKVStorageTypeFile = 0,
    
    //数据库缓存
    YYKVStorageTypeSQLite = 1,
    
    //混合方式。如果YYKVStorageItem.filename不为空就用文件缓存，否则就使用数据库缓存
    YYKVStorageTypeMixed = 2,
};
```

#### 初始化方法：
指定数据缓存方式，创建了缓存文件夹、sqlite数据库，打开并初始化数据库。

```objective-c
- (instancetype)initWithPath:(NSString *)path type:(YYKVStorageType)type {
    if (path.length == 0 || path.length > kPathLengthMax) {
        NSLog(@"YYKVStorage init error: invalid path: [%@].", path);
        return nil;
    }
    if (type > YYKVStorageTypeMixed) {
        NSLog(@"YYKVStorage init error: invalid type: %lu.", (unsigned long)type);
        return nil;
    }
    
    self = [super init];
    _path = path.copy;
    _type = type;
    _dataPath = [path stringByAppendingPathComponent:kDataDirectoryName];//path/data 缓存数据的文件路径
    _trashPath = [path stringByAppendingPathComponent:kTrashDirectoryName];//path/trash 存放丢弃的数据的文件路径
    _trashQueue = dispatch_queue_create("com.ibireme.cache.disk.trash", DISPATCH_QUEUE_SERIAL);//串行队列
    _dbPath = [path stringByAppendingPathComponent:kDBFileName];//path/manifest.sqlite sqlite数据库路径
    _errorLogsEnabled = YES;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error] ||
        ![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByAppendingPathComponent:kDataDirectoryName]
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error] ||
        ![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByAppendingPathComponent:kTrashDirectoryName]
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error]) {
        NSLog(@"YYKVStorage init error:%@", error);
        return nil;
    }

    //创建、打开数据库
    if (![self _dbOpen] || ![self _dbInitialize]) {
        // db file may broken...
        //数据库初始化、打开失败
        [self _dbClose];//关闭数据库
        [self _reset]; // rebuild 移除相关文件夹、文件
        if (![self _dbOpen] || ![self _dbInitialize]) {
            [self _dbClose];
            NSLog(@"YYKVStorage init error: fail to open sqlite db.");
            return nil;
        }
    }
    [self _fileEmptyTrashInBackground]; // empty the trash if failed at last time
    return self;
}
```

dataPath是基于文件方式缓存数据的文件夹，当需要把数据清除时，数据文件先移动到trashPath，然后再在后台线程中把trashPath数据清空。dbPath数数据库文件路径。

在这儿里涉及到几个数据库操作方法，作者严谨、优雅的封装以及数据库读写性能的优化非常值得学习。

1.`_dbOpen`方法

```objective-c
//打开数据库
- (BOOL)_dbOpen {
    if (_db) return YES;
    
    int result = sqlite3_open(_dbPath.UTF8String, &_db);
    if (result == SQLITE_OK) {
        CFDictionaryKeyCallBacks keyCallbacks = kCFCopyStringDictionaryKeyCallBacks;
        CFDictionaryValueCallBacks valueCallbacks = {0};
        _dbStmtCache = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &keyCallbacks, &valueCallbacks);//创建sql语句缓存字典
        _dbLastOpenErrorTime = 0;
        _dbOpenErrorCount = 0;
        return YES;
    } else {
        _db = NULL;
        if (_dbStmtCache) CFRelease(_dbStmtCache);//释放数组
        _dbStmtCache = NULL;
        _dbLastOpenErrorTime = CACurrentMediaTime();
        _dbOpenErrorCount++;
        
        if (_errorLogsEnabled) {//打印错误日志
            NSLog(@"%s line:%d sqlite open failed (%d).", __FUNCTION__, __LINE__, result);
        }
        return NO;
    }
}
```
主要完成打开数据库的功能，另外初始化了几个成员变量，其中`_dbStmtCache`是一个用来缓存sql prepared语句的字典。

在sqlite操作中，直接调用`sqlite3_exce()`函数，会隐式地开启一个事务，而且`sqlite3_exce()`是`sqlite3_perpare()`，`sqlite3_step()`，`sqlite3_finalize()`的一个结合，每调用一次这个函数，就会重复执行这三条语句，事务会被反复地开启关闭，增大IO量；其中`sqlite3_perpare`相当于编译sql语句，如果sql语句相同，就会增加很多的重复操作，重复编译很多次。

在sqlite官方文档中已经指出，很多时候`sqlite3_perpare_v2()`的执行时间要多于`sqlite3_step()`，因此建议开发者尽量避免重复调用`sqlite3_perpare_v2()`。要想避免这样的开销，只需要将待插入的数据以变量的形式**绑定**到sql语句中，这样，sql语句就只需要调用`sqlite3_perpare_v2()`函数**编译一次**即可，其后操作只是替换不同的变量数值。关于绑定的内容之后会谈到。

言归正传，在YYKVStorage初始化方法中的`_dbStmtCache`字典，就是用来缓存经`sqlite3_prepare_v2()`函数编译后的sql语句的。在YYKVStorage中，作者基本上都是把插入的数据以变量的形式绑定到sql语句中。当下一次再次使用某sql语句，则先从`_dbStmtCache`字典找出编译过的sql语句，这样就能减少编译次数。因此就有了以下这个方法：

2.`_dbPrepareStmt`方法

```objective-c
//准备 检查，编译优化
//与sqlite3_exec等价的一组函数是sqlite3_prepare_v2、sqlite3_step、sqlite3_finalize。sqlite3_exec将编译、执行进行了封装
//sqlite3_prepare_v2更高效，只需要编译一次就可以重复执行N次
- (sqlite3_stmt *)_dbPrepareStmt:(NSString *)sql {
    if (![self _dbCheck] || sql.length == 0 || !_dbStmtCache) return NULL;
    //从字典里取出之前编译过的sqlite3_stmt
    sqlite3_stmt *stmt = (sqlite3_stmt *)CFDictionaryGetValue(_dbStmtCache, (__bridge const void *)(sql));
    if (!stmt) {//不存在，就编译一次
        int result = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
        if (result != SQLITE_OK) {
            if (_errorLogsEnabled) NSLog(@"%s line:%d sqlite stmt prepare error (%d): %s", __FUNCTION__, __LINE__, result, sqlite3_errmsg(_db));
            return NULL;
        }
        //将新的sqlite3_stmt保存进字典
        CFDictionarySetValue(_dbStmtCache, (__bridge const void *)(sql), stmt);
    } else {
        //将已编译的SQL语句恢复到初始状态，保留语句相关资源（不会对绑定状态进行改变）
        sqlite3_reset(stmt);
    }
    return stmt;
}
```

如果能从缓存字典中能找到编译过的sql就调用`sqlite3_reset()`函数把sql语句恢复到`sqlite3_prepare_v2()`运行之后的状态（之前没有执行过`sqlite3_step()`或者执行后返回`SQLITE_DONE\SQLITE_OK\SQLITE_ROW`中的一个）。如果找不到，就编译一次。

3.`_dbInitialize`方法创建一张表

```objective-c
- (BOOL)_dbInitialize {
    NSString *sql = @"pragma journal_mode = wal; pragma synchronous = normal; create table if not exists manifest (key text, filename text, size integer, inline_data blob, modification_time integer, last_access_time integer, extended_data blob, primary key(key)); create index if not exists last_access_time_idx on manifest(last_access_time);";
    return [self _dbExecute:sql];
}
```

这个表中一共有七个字段：key、filename、size、inline_data、modification_time、last_access_time、extended_data

3.1`pragma journal_mode = wal`表示使用sqlite日志模式中的WAL模式。
> SQLite中日志模式主要有`DELETE`和`WAL`两种，其他几种比如`TRUNCATE`，`PERSIST`，`MEMORY`基本原理都与`DELETE`模式相同，不作详细展开。`DELETE`模式下，日志中记录的变更前数据页内容；`WAL`模式下，日志中记录的是变更后的数据页内容。事务提交时，`DELETE`模式将日志刷盘，将DB文件刷盘，成功后，再将日志文件清理；WAL模式则是将日志文件刷盘，即可完成提交过程。那么WAL模式下，数据文件何时更新呢？这里引入了检查点概念，检查点的作用就是定期将日志中的新页覆盖DB文件中的老页，并通过参数`wal_autocheckpoint`来控制检查点时机，达到权衡读写的目的。

WAL的优势在于，它支持读写并发，而且写入性能要比DELETE好。使用WAL模式，写事务将更新写到.wal文件中，暂时不更新数据库文件，当执行checkPoint方法时，把.wal文件的内容批量写到数据库中。checkPoint可以自动执行，也可以手动执行。
[更多关于WAL模式请看](http://www.cnblogs.com/softidea/p/4756035.html)

YY中封装的checkpoint方法：

```objective-c
- (void)_dbCheckpoint {
    if (![self _dbCheck]) return;
    // Cause a checkpoint to occur, merge `sqlite-wal` file to `sqlite` file.
    sqlite3_wal_checkpoint(_db, NULL);//手动执行checkpoint,把wal文件中的数据写入到数据库中
}
```

3.2`pragma synchronous = normal`获取或设置当前磁盘的同步模式。默认设置是FULL。
简要说来，full写入速度最慢，但保证数据是安全的，不受断电、系统崩溃等影响，而off可以加速数据库的一些操作，但如果系统崩溃或断电，则数据库可能会损毁。

而当synchronous设置为NORMAL, SQLite数据库引擎在大部分紧急时刻会暂停，但不像FULL模式下那么频繁。 NORMAL模式下有很小的几率(但不是不存在)发生电源故障导致数据库损坏的情况。但实际上，在这种情况 下很可能你的硬盘已经不能使用，或者发生了其他的不可恢复的硬件错误。 


4.`_dbClose`方法 关闭数据库

```objective-c
- (BOOL)_dbClose {
    if (!_db) return YES;
    
    int  result = 0;
    BOOL retry = NO;
    BOOL stmtFinalized = NO; //缓存语句是否已经全部释放完毕
    
    if (_dbStmtCache) CFRelease(_dbStmtCache);//释放字典
    _dbStmtCache = NULL;
    
    do {
        retry = NO;
        result = sqlite3_close(_db);//关闭数据库
        if (result == SQLITE_BUSY || result == SQLITE_LOCKED) {//数据库上锁或者表上锁 此时有读写操作
            if (!stmtFinalized) {
                stmtFinalized = YES;
                sqlite3_stmt *stmt;
                while ((stmt = sqlite3_next_stmt(_db, nil)) != 0) { //sqlite3_next_stmt查找下一个prepared statement（编译过的sql语句）
                    sqlite3_finalize(stmt);//释放 prepared statement
                    retry = YES;
                }
            }
        } else if (result != SQLITE_OK) {
            if (_errorLogsEnabled) {
                NSLog(@"%s line:%d sqlite close failed (%d).", __FUNCTION__, __LINE__, result);
            }
        }
    } while (retry);
    _db = NULL;
    return YES;
}
```

完成释放`_dbStmtCache`字典、关闭数据库的功能。如果有未释放的编译过的语句（`sqlite3_close`也会返回SQLITE_BUSY），就逐个把编译过的sql语句用`sqlite3_finalize()`函数释放掉。

#### 缓存数据的增删查改
YYKVStorageItem：

```objective-c
@property (nonatomic, strong) NSString *key;                ///< key 键值
@property (nonatomic, strong) NSData *value;                ///< value 对象，对应数据库的inline_data字段
@property (nullable, nonatomic, strong) NSString *filename; ///< filename (nil if inline) 缓存文件名
@property (nonatomic) int size;                             ///< value's size in bytes 缓存大小（字节）
@property (nonatomic) int modTime;                          ///< modification unix timestamp 修改时间戳
@property (nonatomic) int accessTime;                       ///< last access unix timestamp 最后使用时间时间戳
@property (nullable, nonatomic, strong) NSData *extendedData;
```
YYKVStorageItem用来保存k-v对和元数据，一一对应数据库表中的七个字段。

1.增-写入数据

```objective-c
- (BOOL)saveItemWithKey:(NSString *)key value:(NSData *)value filename:(NSString *)filename extendedData:(NSData *)extendedData {
    if (key.length == 0 || value.length == 0) return NO;
    if (_type == YYKVStorageTypeFile && filename.length == 0) {//选择文件缓存，但文件名这个字段为空。缓存失败
        return NO;
    }
    //存在文件名
    if (filename.length) {
        //把数据data写入path/data/filename文件
        if (![self _fileWriteWithName:filename data:value]) { //失败
            return NO;
        }
        //把key value filename extendedData写入数据库manifest： /path/manifest.sqlite
        if (![self _dbSaveWithKey:key value:value fileName:filename extendedData:extendedData]) {
            //数据库操作失败，就删除之前的缓存文件 path/data/filename文件
            [self _fileDeleteWithName:filename];
            return NO;
        }
        return YES;
    } else {
        //非数据库缓存（同时又没有传入文件名，所以是混合方法缓存..
        if (_type != YYKVStorageTypeSQLite) {
            //根据key从数据库manifest查找文件名
            NSString *filename = [self _dbGetFilenameWithKey:key];
            if (filename) {
                //删除文件缓存 path/data/filename文件 //因为不可能文件系统缓存(filename参数不存在)所以要把文件缓存的文件删除掉？
                [self _fileDeleteWithName:filename];
            }
        }
//        把数据写入数据库manifest
        return [self _dbSaveWithKey:key value:value fileName:nil extendedData:extendedData];
    }
}
```
如果初始化时设置的缓存策略是文件缓存，但此方法中传入的filename为空，就判错，缓存失败。

然后判断filename是否存在，如果存在，就把数据写入文件，并把该数据相关信息写入数据库（但不会把数据本身存到数据库）。

如果filename不存在，就把数据及相关信息直接写到数据库，另外如果是混合方式的缓存策略，还要检查以前是否在文件中缓存了相同key的数据。

文件写入操作：

```objective-c
//向文件写入数据
- (BOOL)_fileWriteWithName:(NSString *)filename data:(NSData *)data {
    NSString *path = [_dataPath stringByAppendingPathComponent:filename];
    return [data writeToFile:path atomically:NO];
}
```

数据库写入方法：

```objective-c
//写入数据库
- (BOOL)_dbSaveWithKey:(NSString *)key value:(NSData *)value fileName:(NSString *)fileName extendedData:(NSData *)extendedData {
    NSString *sql = @"insert or replace into manifest (key, filename, size, inline_data, modification_time, last_access_time, extended_data) values (?1, ?2, ?3, ?4, ?5, ?6, ?7);";
    sqlite3_stmt *stmt = [self _dbPrepareStmt:sql];//取出已编译的sql语句或者编译该语句
    if (!stmt) return NO;
    //绑定七个字段
    int timestamp = (int)time(NULL);
    sqlite3_bind_text(stmt, 1, key.UTF8String, -1, NULL);
    sqlite3_bind_text(stmt, 2, fileName.UTF8String, -1, NULL);
    sqlite3_bind_int(stmt, 3, (int)value.length);
    if (fileName.length == 0) {
        sqlite3_bind_blob(stmt, 4, value.bytes, (int)value.length, 0);
    } else {
        sqlite3_bind_blob(stmt, 4, NULL, 0, 0);
    }
    sqlite3_bind_int(stmt, 5, timestamp);
    sqlite3_bind_int(stmt, 6, timestamp);
    sqlite3_bind_blob(stmt, 7, extendedData.bytes, (int)extendedData.length, 0);
    
    int result = sqlite3_step(stmt);//单步执行
    if (result != SQLITE_DONE) {
        if (_errorLogsEnabled) NSLog(@"%s line:%d sqlite insert error (%d): %s", __FUNCTION__, __LINE__, result, sqlite3_errmsg(_db));//输出错误
        return NO;
    }
    return YES;
}
```

先创建了一条sql语句，将待插入的数据以变量的形式绑定到sql语句中，这样只需要将该语句编译一次就可以重复使用多次了。“？”表示参数需要通过变量绑定，“？”后的数字表示绑定变量对应的索引号。最后调用`sqlite3_step ()`函数执行sql语句。
留意到：

```objective-c
if (fileName.length == 0) {
        sqlite3_bind_blob(stmt, 4, value.bytes, (int)value.length, 0);
    } else {
        sqlite3_bind_blob(stmt, 4, NULL, 0, 0);
    }
```

如果filename存在，inline_data字段就不绑定数据，fileName字段绑定文件名。因为数据已经保存在文件中了，不必重复保存。如果filename不存在，那么代表是使用数据库缓存策略，inline_data字段绑定数据，同时fileName字段不绑定。

理解这段代码很重要，因为YYCache的磁盘缓存就是基于这样的方式进行设计的。比如要查找数据：如果使用的是文件缓存策略，要取出缓存数据，先根据key值，在数据库中找到文件名，然后根据拿到的文件名去对应的文件路径中去取数据。如果使用的是数据库缓存，那么根据key值直接在数据库中就能找到数据。

比如删除缓存就是如此。

2.删除数据

```objective-c
//根据key删除数据库缓存
- (BOOL)removeItemForKey:(NSString *)key {
    if (key.length == 0) return NO;
    switch (_type) {//缓存方式
        case YYKVStorageTypeSQLite: {
            return [self _dbDeleteItemWithKey:key];//根据key来删除数据库记录
        } break;
        case YYKVStorageTypeFile:
        case YYKVStorageTypeMixed: {
            NSString *filename = [self _dbGetFilenameWithKey:key];//根据key从数据库中找到对应的filename
            if (filename) {//如果filename存在，删除文件中的数据
                [self _fileDeleteWithName:filename];
            }
            return [self _dbDeleteItemWithKey:key];//删除数据库中的记录
        } break;
        default: return NO;
    }
}
```
查找数据的过程基本就如上所述，根据不同的缓存策略使用不同的方式来删除数据。如果是文件缓存或者是混合缓存的话，除了删除文件数据还要把数据库中对应的记录删除掉。

触类旁通，至于查找和修改数据的方法，大多都是类似的数据库、文件读写方法，把握好了一个思路，其实看起来都是差不多的，在这里就不展开了讲了。

## 3.YYDiskCache
YYDiskCache是YYKVStorage的线程安全封装，与YYMemoryCache类似，实现了LRU淘汰算法。

#### 初始化
```objective-c
- (instancetype)initWithPath:(NSString *)path {
    return [self initWithPath:path inlineThreshold:1024 * 20]; // 20KB
}

- (instancetype)initWithPath:(NSString *)path
             inlineThreshold:(NSUInteger)threshold {
    self = [super init];
    if (!self) return nil;
    //根据path找YYDiskCache对象
    YYDiskCache *globalCache = _YYDiskCacheGetGlobal(path);//线程安全地取得YYDiskCache对象（相当于单例）
    if (globalCache) return globalCache;
    //找不到，就新建一个
    YYKVStorageType type;
    if (threshold == 0) {
        type = YYKVStorageTypeFile;
    } else if (threshold == NSUIntegerMax) {
        type = YYKVStorageTypeSQLite;
    } else {//默认策略
        type = YYKVStorageTypeMixed;
    }
    
    YYKVStorage *kv = [[YYKVStorage alloc] initWithPath:path type:type];
    if (!kv) return nil;
    
    _kv = kv;
    _path = path;
    _lock = dispatch_semaphore_create(1);//信号量
    _queue = dispatch_queue_create("com.ibireme.cache.disk", DISPATCH_QUEUE_CONCURRENT);//并发队列
    _inlineThreshold = threshold;
    _countLimit = NSUIntegerMax;
    _costLimit = NSUIntegerMax;
    _ageLimit = DBL_MAX;
    _freeDiskSpaceLimit = 0;
    _autoTrimInterval = 60;
    
    [self _trimRecursively];
    _YYDiskCacheSetGlobal(self);
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appWillBeTerminated) name:UIApplicationWillTerminateNotification object:nil];
    return self;
}
```
方法需要传入缓存路径和缓存阈值threshold参数。在作者设计思路文章中分析到，超过20k数据使用文件缓存读写快，而低于20k数据使用数据库读写比较快，所以默认的阈值是20K，当然我们也可以自行设置阈值。初始化方法中根据阈值参数决定缓存策略，默认是`YYKVStorageTypeMixed`。

一个路径path对应一个YYDiskCache，类似的，使用了NSMapTable来缓存两者的对应关系，并且使用dispatch_semaphore信号量上锁来保证字典读写安全。

```objective-c
static YYDiskCache *_YYDiskCacheGetGlobal(NSString *path) {
    if (path.length == 0) return nil;
    _YYDiskCacheInitGlobal();
    dispatch_semaphore_wait(_globalInstancesLock, DISPATCH_TIME_FOREVER);//如果信号量>0就继续执行下面的操作，并将信号量-1.否则会阻塞当前线程，等待timeout
    id cache = [_globalInstances objectForKey:path];
    dispatch_semaphore_signal(_globalInstancesLock);//信号量+1
    return cache;
}

static void _YYDiskCacheSetGlobal(YYDiskCache *cache) {
    if (cache.path.length == 0) return;
    _YYDiskCacheInitGlobal();
    dispatch_semaphore_wait(_globalInstancesLock, DISPATCH_TIME_FOREVER);
    [_globalInstances setObject:cache forKey:cache.path];
    dispatch_semaphore_signal(_globalInstancesLock);
}

//初始化字典和锁
static void _YYDiskCacheInitGlobal() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _globalInstancesLock = dispatch_semaphore_create(1);//生成信号量
        _globalInstances = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory capacity:0];
    });
}
```

LRU淘汰，**基于 SQLite 存储的元数据**。与YYMemoryCache中的实现类似，递归调用`_trimRecursively`方法：

```objective-c
//递归淘汰
- (void)_trimRecursively {
    __weak typeof(self) _self = self;
    //60s定时清理
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTrimInterval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __strong typeof(_self) self = _self;
        if (!self) return;
        [self _trimInBackground];
        [self _trimRecursively];
    });
}
```

只不过清理的频率变成了60s一次。除了有根据缓存花销（cost）、缓存对象数目、最后使用时间这三个维度进行淘汰，还有根据磁盘剩余空间大小来进行淘汰。其中涉及到了数据读写，需要用锁来保证多线程访问的安全性，同样地，这里也使用了`dispatch_semaphore `信号量，下面是相关的两个宏：

```objective-c
#define Lock() dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER)
#define Unlock() dispatch_semaphore_signal(self->_lock)
```

```objective-c
- (void)_trimInBackground {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        if (!self) return;
        Lock();
        //由于下面这些方法的实现不是线程安全的，所以在使用它们之前要先上锁
        [self _trimToCost:self.costLimit];
        [self _trimToCount:self.countLimit];
        [self _trimToAge:self.ageLimit];
        [self _trimToFreeDiskSpace:self.freeDiskSpaceLimit];
        Unlock();
    });
}
```

#### 写缓存
```objective-c
//添加缓存
- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key {
    if (!key) return;
    if (!object) {//如果object为空，就删除缓存中和key关联的item
        [self removeObjectForKey:key];
        return;
    }
    
    NSData *extendedData = [YYDiskCache getExtendedDataFromObject:object];
    NSData *value = nil;
    //归档数据
    if (_customArchiveBlock) {//是否有自定义归档block
        value = _customArchiveBlock(object);
    } else {
        @try {
            value = [NSKeyedArchiver archivedDataWithRootObject:object];
        }
        @catch (NSException *exception) {
            // nothing to do...
        }
    }
    if (!value) return;
    NSString *filename = nil;
    if (_kv.type != YYKVStorageTypeSQLite) {
        if (value.length > _inlineThreshold) {//数据超过阈值（要使用文件缓存），取出key关联的文件名
            filename = [self _filenameForKey:key];
        }
    }
    
    Lock();
    [_kv saveItemWithKey:key value:value filename:filename extendedData:extendedData];//添加缓存
    Unlock();
}
```
传入缓存对象和key。先对对象进行归档，转成二进制数据，如果有自定义的归档方法就用，否则就用系统默认的归档方法。
判断缓存策略type，如果是数据库缓存，就直接调用`-saveItemWithKey: value: filename: extendedData:`将数据写入数据库，filename=nil。如果是另外两种缓存策略，判断数据是否超过threshold阈值（如果是文件缓存策略，作者已经写死只有threshold=0才是文件缓存；默认是混合缓存，阈值20K），超阈值就将数据写入文件。

#### 读缓存
`- (id<NSCoding>)objectForKey:(NSString *)key`，先使用YYKVStorage 的`getItemForKey:`方法得到key对应YYKVStorageItem对象，然后再解档item.value得到原来的缓存对象。

还有一些删除缓存、异步回调的方法，比较简单，这里也不多说了。

## 4.最后
用过阅读YY源码，学习到了很多，LRU算法的实现(内存缓存基于用双向链表和 CFMutableDictionary 实现，磁盘缓存基于基于 SQLite 存储的元数据)、SQLite封装、线程安全等等，特别是性能优化问题上，代码中更是处处有体现，像作者这样的大神，技术真是让我敬佩。


参考文章：
[作者设计思路](https://blog.ibireme.com/2015/10/26/yycache/)
[Sqlite3常用的插入方法及性能测试](http://www.cnblogs.com/liuroy/p/5616236.html)
[sqlite3中绑定bind函数用法 （将变量插入到字段中）](http://blog.csdn.net/xiaoaid01/article/details/17892579)
[sqlite3_reset作用](http://blog.csdn.net/jiangdianqin/article/details/71082428)
[提升SQLite数据插入效率低、速度慢的方法](http://blog.csdn.net/majiakun1/article/details/46607163)
