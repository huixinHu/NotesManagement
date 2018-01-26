# iOS EventKit日历事件操作 开发笔记
最近手头上一个日程管理的项目里有一个功能是做事务提醒的，原本是想用本地推送来实现，但是无奈本地推送数量有限制，最多不能超过64条。如果改用远程推送来实现，那是最好的了，但是资源、条件不是很完备（毕竟是学生项目，要申请开发者账号还得增加后台同学工作量等等），最后选择了用系统日历来完成。在此做了一些总结，方便日后查阅。（后来知道其实也可以用本地推送来做的，等以后有空再试一下能不能实现）

## 了解EventKit框架
事件库框架授权访问用户的 Calendar.app 和 Reminders.app 应用的信息。尽管是用两个不同的应用显示用户的日历和提醒数据，但确是同一个框架维护这份数据。他们使用相同的库（EKEventStore）处理数据。

该框架除了允许检索用户已经存在的calendar和reminder数据外，还允许创建新的事件和提醒。更高级的任务，诸如添加闹钟或指定循环事件，也可以使用事件库完成。

## 使用
### 准备
在项目中导入EventKit框架和EventKitUI框架
![](http://upload-images.jianshu.io/upload_images/1727123-8a52e0ede364b87c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

在使用到这个框架的文件中import进来：
```objectivec
#import <EventKit/EventKit.h>
#import <EventKitUI/EventKitUI.h>
```

### 创建一个事件库实例
```EKEventStore *eventStore = [[EKEventStore alloc] init];```

因为EKEventStore就像数据库一样，频繁的开启，关闭会影响效率，所以如果你的程序需要频繁操作日历和提醒，建议仅生成该对象一次，仅用一个对象进行操作。因此项目里面我单独写了一个类封装对日历的操作，并用单例创建EKEventStore实例。

### 授权
iOS10以后获得授权要在plist文件中进行设置：添加权限字符串访问日历:NSCalendarsUsageDescription 访问提醒事项:NSRemindersUsageDescription
![](http://upload-images.jianshu.io/upload_images/1727123-f6cf5573bcb03647.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

EKEntityType有两类
```objectivec
EKEntityTypeEvent日历事件 ,   EKEntityTypeReminder//提醒事项
```
```objectivec
- (void)calendarAuthority{
//获取授权状态
    EKAuthorizationStatus eventStatus = [EKEventStore  authorizationStatusForEntityType:EKEntityTypeEvent];
    //用户还没授权过
    if(eventStatus ==EKAuthorizationStatusNotDetermined){
        //提示用户授权，调出授权弹窗
        [[[EKEventStore alloc]init] requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError * _Nullable error) {
            if(granted){
                NSLog(@"允许");
            }else{
                NSLog(@"拒绝授权");
            }
        }];
    }
    //用户授权不允许
    else if (eventStatus == EKAuthorizationStatusDenied){
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"当前日历服务不可用" message:@"您还没有授权本应用使用日历,请到 设置 > 隐私 > 日历 中授权" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *action = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        }];
        [alert addAction:action];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
//还有两种授权状态：
//EKAuthorizationStatusAuthorized用户已经允许授权
//EKAuthorizationStatusRestricted,未授权，且用户无法更新，如家长控制情况下
```

检查授权状态我们使用的是EKEventStore authorizationStatusForEntityType:类方法,而调出系统日历事件授权弹窗使用的却是EKEventStore的实例方法requestAccessToEntityType:

### 找到对应的日历源
日历源它是EKSource的实例对象，可以理解为是按照日历类型去分类的一些组。在模拟器下：
![模拟器截图](http://upload-images.jianshu.io/upload_images/1727123-ebeb837ee5f9ea07.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

在这个图里，我们看到有两个日历源，一个是“ON MY IPHONE”另一个是"OTHER"。这里我们打个断点查看所有日历源：
![](http://upload-images.jianshu.io/upload_images/1727123-12fa8505e1f9c470.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

可以看到日历数据库中第一个日历源的真正名称为Default(是一个Local源),而后面一个名称为Other。在模拟器中显示的第一个日历源的名称只是一个便于用户理解的别名。(但我目前还不是很清楚subscribe类型的那一项是什么)

然后在真机上，第一个日历源的名字是ICLOUD，第二个日历源是“其他”。我们可以看到无论是真机还是模拟器，每个日历源里都可以有若干个日历。

举例获取iCloud源：
```objectivec
EKSource *localSource = nil;
for (EKSource *source in _eventStore.sources){
//获取iCloud源。这里可以只通过日历源的title来查找，不过加上对类型的检查就是双保险
   if (source.sourceType == EKSourceTypeCalDAV && [source.title isEqualToString:@"iCloud"]){
    //把获取到的iCloud源保存起来
    localSource = source;
   }
}
```

其他几种日历源：
```objectivec
typedef NS_ENUM(NSInteger, EKSourceType) {
    EKSourceTypeLocal,
    EKSourceTypeExchange,
    EKSourceTypeCalDAV,
    EKSourceTypeMobileMe,
    EKSourceTypeSubscribed,
    EKSourceTypeBirthdays
};
```
（Local是本地的源；iCloud是远程源，网络联网同步数据有点关系，EKSourceTypeExchange也是远程源）

### 获取日历源中指定的日历
使用EKEventStore的```- (NSArray<EKCalendar *> *)calendarsForEntityType:(EKEntityType)entityType```方法，这个方法会返回一个EKCalendar的数组，里面包含符合要求的日历（支持事件的或者支持提醒的）
原本EKSource里面有一个只读的获取指定日历源中所有日历的属性，但现在已经废弃掉了~```@property(nonatomic, readonly) NSSet<EKCalendar *> *calendars NS_DEPRECATED(NA, NA, 4_0, 6_0);```
```objectivec
EKCalendar *calendar;
for (EKCalendar *ekcalendar in [_eventStore calendarsForEntityType:EKEntityTypeEvent]) {
//当然这里也可以加上日历源类型的检查，像上面一样的双保险 calendar.type == EKCalendarTypeCalDAV
      if ([ekcalendar.title isEqualToString:@"小雅"] ) {
           calendar = ekcalendar;
      }
}
```

和上面几种日历源对应的日历类型：
```objectivec
typedef NS_ENUM(NSInteger, EKCalendarType) {
    EKCalendarTypeLocal,
    EKCalendarTypeCalDAV,
    EKCalendarTypeExchange,
    EKCalendarTypeSubscription,
    EKCalendarTypeBirthday
};
```

### 在系统日历中创建自定义日历

![](http://upload-images.jianshu.io/upload_images/1727123-ebeb837ee5f9ea07.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
我们需要先找到iCloud大分类，然后才能创建自定义的日历，而且创建时，我们需要判断是否创建，否则，会创建一些具有同样名称的日历
```objectivec
@property (nonatomic ,strong)EKCalendar *cal;

- (EKCalendar *)cal{
    if (_cal == nil) {
        BOOL shouldAdd = YES;
        EKCalendar *calendar;
        for (EKCalendar *ekcalendar in [_eventStore calendarsForEntityType:EKEntityTypeEvent]) {
            if ([ekcalendar.title isEqualToString:@"小雅"] ) {
                shouldAdd = NO;
                calendar = ekcalendar;
            }
        }
        if (shouldAdd) {
            EKSource *localSource = nil;
            //真机
            for (EKSource *source in _eventStore.sources){
                if (source.sourceType == EKSourceTypeCalDAV && [source.title isEqualToString:@"iCloud"]){//获取iCloud源
                    localSource = source;
                    break;
                }
            }
            if (localSource == nil){
                //模拟器
                for (EKSource *source in _eventStore.sources) {//获取本地Local源(就是上面说的模拟器中名为的Default的日历源)
                    if (source.sourceType == EKSourceTypeLocal){
                        localSource = source;
                        break;
                    }
                }
            }
            calendar = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:_eventStore];
            calendar.source = localSource;
            calendar.title = @"小雅";//自定义日历标题
            calendar.CGColor = [UIColor greenColor].CGColor;//自定义日历颜色
            NSError* error;
            [_eventStore saveCalendar:calendar commit:YES error:&error];
        }
        _cal = calendar;
    }
    return _cal;
}
```

### 日历事件查询
要访问日历中的事件，需要提供一个查询条件，因为有些重复事件是没有尽头的，你不可能获取一个无限长的事件列表。因此需要使用NSPredicate谓词来进行筛选。
```- (NSPredicate *)predicateForEventsWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate calendars:(nullable NSArray<EKCalendar *> *)calendars;```在这个方法里分别需要传入：需要查询的开始时间、截止时间、要查询的日历类型数组。返回符合条件的日历事件（上限是四年内，如果开始、结束的时间跨度超过4年就截取最开始的4年的事件返回）
```objectivec
- (NSArray*)checkEvent{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    // 创建起始日期组件
    NSDateComponents *oneDayAgoComponents = [[NSDateComponents alloc] init];
    oneDayAgoComponents.day = -1;
    NSDate *oneDayAgo = [calendar dateByAddingComponents:oneDayAgoComponents
                                                  toDate:[NSDate date]
                                                 options:0];  
    // 创建结束日期组件
    NSDateComponents *oneMonthFromNowComponents = [[NSDateComponents alloc] init];
    oneMonthFromNowComponents.month = 1;
    NSDate *oneMonthFromNow = [calendar dateByAddingComponents:oneMonthFromNowComponents
                                                       toDate:[NSDate date]
                                                      options:0];
    // 用事件库的实例方法创建谓词。表示 找出从当前时间前一天到当前时间的一个月后的时间范围的所有typesArray里类型的日历事件
    NSPredicate*predicate = [self.eventStore predicateForEventsWithStartDate:oneDayAgo endDate:oneMonthFromNow calendars:@[self.cal]];
    NSArray *eventArray = [self.eventStore eventsMatchingPredicate:predicate];
    return eventArray;
}
```
这样就获取了从当前时间前一天到当前时间的一个月后的事件数组。

eventArray是符合条件的日历事件数组，数组里存的是EKEvent类型数据。关于EKEvent的一些属性和方法，这里简单提几个，详细的看api文档。
```objectivec
+ (EKEvent *)eventWithEventStore:(EKEventStore *)eventStore 创建一个新的自动释放的事件对象
@property(nonatomic, readonly) NSString *eventIdentifier; 唯一标识符区分某个事件.修改事件有可能
@property(nonatomic, getter=isAllDay) BOOL allDay 设置是否是全天事件
@property(nonatomic, copy) NSDate *startDate; 事件开始时间
@property(nonatomic, copy) NSDate *endDate; 结束时间
@property(nonatomic, copy, nullable) EKStructuredLocation *structuredLocation 事件里添加的位置。可以获取到经纬度等相关信息。
```

- 事件修改
拿到event然后对它的各个属性赋新值就好了。在保存时，从哪个EKEventStore里取出来就要存回哪个EKEventStore。

### 添加事件到系统日历、设置重复周期、创建任意时间之前开始的提醒
添加的方法：```- (BOOL)saveEvent:(EKEvent *)event span:(EKSpan)span commit:(BOOL)commit error:(NSError **)error```

event:要添加的事件。

span:设置跨度。 有两种选择：```EKSpanThisEven```t表示只影响当前事件，```EKSpanFutureEvents```表示影响当前和以后的所有事件。比如某条重复任务修改后保存时，传```EKSpanThisEvent```表示值修改这一条重复事件，传```EKSpanFutureEvents```表示修改这一条和以后的所有重复事件；删除事件时，分别表示删除这一条；删除这一条和以后的所有。

commit：是否马上保存事件（类似sqlite里面的“事务”）。YES表示马上执行，立即把此次操作提交到系统事件库；NO表示此时不提交，直到调用commit:方法时才执行。

如果一次性操作的事件数比较少的话，可以每次都传YES，实时更新事件数据库。如果一次性操作的事件较多的话，可以每次传NO，最后再执行一次提交所有更改到数据库，把原来的更改（不管是添加还是删除）全部提交到数据库。

error：出错信息，如果没出错值是nil。

```objectivec
- (void)addEventNotifyWithTitle:(NSString*)title dateString:(NSString*)dateString startSection:(NSString *)startSection endSection:(NSString *)endSection repeatIndex:(NSInteger)repeatindex alarmSettings:(NSArray *)remindIndexs note:(NSString*)notes{
//创建一个新事件
    EKEvent *event = [EKEvent eventWithEventStore:self.eventStore];
    //1.标题
    event.title = title;
    //2.开始时间
    event.startDate = [self.dateFormatter dateFromString:[dateString stringByAppendingString:[self sectionStartTime:startSection]]];
    //3.结束时间
    event.endDate = [self.dateFormatter dateFromString:[dateString stringByAppendingString:[self sectionEndTime:endSection]]];
    //4.重复规则
    EKRecurrenceRule *rule = [self repeatRule:repeatindex currentDate:dateString];
    if (rule != nil) {
        event.recurrenceRules = @[rule];
    }else{
        event.recurrenceRules = nil;
    }
    event.notes = notes;//6.备注
    [event setAllDay:NO];//设置全天
    //5.设置提醒
    for (int i = 0; i < remindIndexs.count; i++) {
        EKAlarm *alarm = [self alarmsSettingWithIndex:[remindIndexs[i] intValue]];
        if (alarm == nil) {
            event.alarms = nil;
            break;
        }
        [event addAlarm:alarm];
    }
    [event setCalendar:self.cal];//设置日历类型
    //保存事件
    NSError *err = nil;
    if([self.eventStore saveEvent:event span:EKSpanThisEvent commit:NO error:nil]){//注意这里是no，在外部调用完这个add方法之后一定要commit
        NSLog(@"创建事件到系统日历成功!,%@",title);
    }else{
        NSLog(@"创建失败%@",err);
    }
}

//重复规则
- (EKRecurrenceRule *)repeatRule:(NSInteger)repeatIndex currentDate:(NSString*)dateString{
    NSDate *currentDate = [self.dateFormatter dateFromString:[dateString stringByAppendingString:@"0000"]];
    NSCalendar * gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [gregorian components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:currentDate];
    components.year += 1;
    NSDate *recurrenceEndDate = [gregorian dateFromComponents:components];//高频率：每天、每两天、工作日
    NSDateComponents *components2 = [gregorian components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:currentDate];
    components2.year += 3;
    NSDate *recurrenceEndDate2 = [gregorian dateFromComponents:components2];//低频率：每周、每月、每年

    EKRecurrenceRule * rule;
    switch (repeatIndex) {
        case 0://每天
            rule = [[EKRecurrenceRule alloc]initRecurrenceWithFrequency:EKRecurrenceFrequencyDaily interval:1 daysOfTheWeek:nil daysOfTheMonth:nil monthsOfTheYear:nil weeksOfTheYear:nil daysOfTheYear:nil setPositions:nil end:[EKRecurrenceEnd recurrenceEndWithEndDate:recurrenceEndDate]];
            break;
        case 1://每两天
            rule = [[EKRecurrenceRule alloc]initRecurrenceWithFrequency:EKRecurrenceFrequencyDaily interval:2 daysOfTheWeek:nil daysOfTheMonth:nil monthsOfTheYear:nil weeksOfTheYear:nil daysOfTheYear:nil setPositions:nil end:[EKRecurrenceEnd recurrenceEndWithEndDate:recurrenceEndDate]];
            break;
        case 2://每周
            rule = [[EKRecurrenceRule alloc]initRecurrenceWithFrequency:EKRecurrenceFrequencyWeekly interval:1 daysOfTheWeek:nil daysOfTheMonth:nil monthsOfTheYear:nil weeksOfTheYear:nil daysOfTheYear:nil setPositions:nil end:[EKRecurrenceEnd recurrenceEndWithEndDate:recurrenceEndDate2]];
            break;
        case 3://每月
            rule = [[EKRecurrenceRule alloc]initRecurrenceWithFrequency:EKRecurrenceFrequencyMonthly interval:1 daysOfTheWeek:nil daysOfTheMonth:nil monthsOfTheYear:nil weeksOfTheYear:nil daysOfTheYear:nil setPositions:nil end:[EKRecurrenceEnd recurrenceEndWithEndDate:recurrenceEndDate2]];
            break;
        case 4://每年
            rule = [[EKRecurrenceRule alloc]initRecurrenceWithFrequency:EKRecurrenceFrequencyYearly interval:1 daysOfTheWeek:nil daysOfTheMonth:nil monthsOfTheYear:nil weeksOfTheYear:nil daysOfTheYear:nil setPositions:nil end:[EKRecurrenceEnd recurrenceEndWithEndDate:recurrenceEndDate2]];
            break;
        case 5://工作日
            rule = [[EKRecurrenceRule alloc]initRecurrenceWithFrequency:EKRecurrenceFrequencyDaily interval:1 daysOfTheWeek:[NSArray arrayWithObjects:[EKRecurrenceDayOfWeek dayOfWeek:2],[EKRecurrenceDayOfWeek dayOfWeek:3],[EKRecurrenceDayOfWeek dayOfWeek:4],[EKRecurrenceDayOfWeek dayOfWeek:5],[EKRecurrenceDayOfWeek dayOfWeek:6],nil] daysOfTheMonth:nil monthsOfTheYear:nil weeksOfTheYear:nil daysOfTheYear:nil setPositions:nil end:[EKRecurrenceEnd recurrenceEndWithEndDate:recurrenceEndDate]];
            break;
        case 6:
            rule = nil;
            break;
        default:
            rule = nil;
            break;
    }
    return rule;
}

//@[@"当事件发生时",@"5分钟前",@"15分钟前",@"30分钟前",@"1小时前",@"1天前",@"不提醒"]
- (EKAlarm *)alarmsSettingWithIndex:(int )remindIndex{
    EKAlarm *alarm;
    switch (remindIndex) {
        case 0:
            alarm = [EKAlarm alarmWithRelativeOffset:0];
            break;
        case 1:
            alarm = [EKAlarm alarmWithRelativeOffset:- 60.0 * 5];
            break;
        case 2:
            alarm = [EKAlarm alarmWithRelativeOffset:- 60.0 * 15];
            break;
        case 3:
            alarm = [EKAlarm alarmWithRelativeOffset:-60.0 * 30];
            break;
        case 4:
            alarm = [EKAlarm alarmWithRelativeOffset:-60.0 * 60];
            break;
        case 5:
            alarm = [EKAlarm alarmWithRelativeOffset:-60.0 * 60 * 24];
            break;
        case 6:
            alarm = nil;
            break;
        default:
            alarm = nil;
            break;
    }
    return alarm;
}
```

- 设置事件重复

主要用到EKRecurrenceRule这个类来设置重复规则

 ```objectivec
 - (instancetype)initRecurrenceWithFrequency:(EKRecurrenceFrequency)type
                         interval:(NSInteger)interval 
                    daysOfTheWeek:(nullable NSArray<EKRecurrenceDayOfWeek *> *)days
                   daysOfTheMonth:(nullable NSArray<NSNumber *> *)monthDays
                  monthsOfTheYear:(nullable NSArray<NSNumber *> *)months
                   weeksOfTheYear:(nullable NSArray<NSNumber *> *)weeksOfTheYear
                    daysOfTheYear:(nullable NSArray<NSNumber *> *)daysOfTheYear
                     setPositions:(nullable NSArray<NSNumber *> *)setPositions
                              end:(nullable EKRecurrenceEnd *)end;
```

一个个参数来看：

type:重复规则的频率
```objectivec
typedef NS_ENUM(NSInteger, EKRecurrenceFrequency) {
    EKRecurrenceFrequencyDaily,//按天
    EKRecurrenceFrequencyWeekly,//按周
    EKRecurrenceFrequencyMonthly,//按月
    EKRecurrenceFrequencyYearly//按年
};
```
interval：间隔，必须大于0

days：一周中的哪几天

monthDays：一个月中的哪几号

months：一年中哪几个月

weeksOfTheYear：一年中的哪几周

daysOfTheYear：一年中的哪几天

setPositions：规则外的设置

end：结束规则。有两种：按次数和按时间。按时间：```[EKRecurrenceEnd recurrenceEndWithEndDate:recurrenceEndDate]```表示recurrenceEndDate该时间后不再计算；按次数：```[EKRecurrenceEnd recurrenceEndWithOccurrenceCount:10]```表示十次

 举个例子：
1.每两天执行一次：type: EKRecurrenceFrequencyDaily；interval:2

2.每工作日执行：type: EKRecurrenceFrequencyDaily；interval:1；days为星期一...星期五，具体参数设置：```[NSArray arrayWithObjects:[EKRecurrenceDayOfWeek dayOfWeek:2],[EKRecurrenceDayOfWeek dayOfWeek:3],[EKRecurrenceDayOfWeek dayOfWeek:4],[EKRecurrenceDayOfWeek dayOfWeek:5],[EKRecurrenceDayOfWeek dayOfWeek:6],nil]```

3.每两周周一执行一次：type:EKRecurrenceFrequencyWeekly；interval:2；days：```[NSArray arrayWithObjects:[EKRecurrenceDayOfWeek dayOfWeek:2],nil]```

4.每月1号执行一次：type: EKRecurrenceFrequencyMonthly；interval:1；monthDays：@[@1];

 添加重复：```event.recurrenceRules = rule数组;```或者使用```- (void)addRecurrenceRule:(EKRecurrenceRule *)rule;```逐个规则添加

- 创建任意时间之前开始的提醒

使用EKAlarm闹钟来做提醒功能。
创建方法有两种：
```objectivec
 + (EKAlarm *)alarmWithAbsoluteDate:(NSDate *)date; 设置绝对时间
 + (EKAlarm *)alarmWithRelativeOffset:(NSTimeInterval)offset; 设置相对时间（相对event的start date），而且这个相对时间的基本单位是秒，设置负值表示事件前提醒，设置正值是事件发生后提醒
```

举例：事件五分钟前提醒
```objectivec
EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:- 60.0 * 5];
[event addAlarm:alarm];//逐个闹钟添加到事件
```
也可以```event.alarms = 闹钟数组```一次性添加所有提醒。

 设置了提醒后,我们打开iOS系统自带的日历App,会发现只会显示2个提醒,看不到多余的提醒.但是实际测试发现全部提醒都可以工作,而且我们可以在Mac的日历程序中看到所有的提醒。

### 删除系统日历事件

删除的方法：```- (BOOL)removeEvent:(EKEvent *)event span:(EKSpan)span commit:(BOOL)commit error:(NSError **)error```参数和添加事件方法差不多，使用也很简单，这里只贴一下代码不多叙述。
```objectivec
NSArray *eventArray = [self checkEventWithDateString:dateStrArray startSection:startSection endSection:endSection];
    if (eventArray.count > 0) {
        for (int i = 0; i < eventArray.count; i++) {
            EKEvent * event = eventArray[i];
            [event setCalendar:self.cal];
            NSError *error = nil;
            BOOL successDelete;
            if (deleteFuture) {
                successDelete = [self.eventStore removeEvent:event span:EKSpanFutureEvents commit:NO error:&error];
            }else{
                successDelete = [self.eventStore removeEvent:event span:EKSpanThisEvent commit:NO error:&error];
            }
//            if(!successDelete) {
//                NSLog(@"删除本条事件失败");
//            }else{
//                NSLog(@"删除本条事件成功，%@",error);
//            }
        }
        //一次提交所有操作到事件库
        [self commitEvent];
    }

- (void)commitEvent{
    NSError *error =nil;
    BOOL commitSuccess= [self.eventStore commit:&error];
    if(!commitSuccess) {
        NSLog(@"一次性提交事件失败，%@",error);
    }else{
        NSLog(@"成功一次性提交事件,%s",__func__);
    }
}
```

### 其他

还有一个问题，就是在你修改事件的过程中如果事件发生了变化。
日历发生变化时都会发出EKEventStoreChangedNotification通知，调用EKEvent的refresh方法即可刷新这个事件确保事件还是可用的，另外它还会刷新事件的属性值，已经修改过的属性并不会被更新。（如果refresh方法返回NO那么这个事件已经被删除掉或者已经是无效的，不应该再使用它）。
关于这个问题，因为我还没有实际使用到，所以点到即止。

项目中遇到的一个问题：如果app正在使用时切换到系统“设置”，把app的日历授权关了，这时候app会崩掉。不清楚原因，崩溃时断点显示“SIGKILL”
