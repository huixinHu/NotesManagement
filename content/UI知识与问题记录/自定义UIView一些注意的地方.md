- 初始化
**从代码中加载：**

 重写initWithFrame:方法，不要重写Init方法，因为即使调用的是init，最终还是会调用到initWithFrame:（虽然有一些类在初始化的时候没有遵守这个约定，如 UIImageView 的 initWithImage 和 UITableViewCell 的 initWithStyle:reuseIdentifier: 的构造器等）。
所以如果重写了init:,当别人调用initWithFrame:的时候，控件便无法创建。

 如果有自己命名的初始化方法，要在实现中调用父类的initWithFrame:

 **如果要同时支持 initWithFrame（代码加载） 和 initWithCoder （文件加载），那么可以把统一的初始化写在一个commonInit:中。而awakeFromNib 方法里就不要再去调用 commonInit 了**

- 调整布局

 **1.如果是基于frameLayout布局:**
 
 **尽量不要在initWithFrame:里面对子控件进行布局，而应该在layoutSubViews方法里面布局子控件。**
如果在initWithFrame中取自身(self)的宽高，得到的可能不是准确的值。也不要使用带有 比如self.frame.size.width这样 自身宽高的运算来对子控件进行布局。

 比如：
 
 ```objective-c
 - (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.lable = [[UIImageView alloc]init];
        self.lable.frame = CGRectMake(0, 0, self.frame.size.width-20, self.frame.size.height-30);
        [self addSubview:self.lable];
    }
    return self;
}
```
 如果直接调用init方法，那么当initWithFrame被调用时，frame根本就没有值。。。

 **2.如果是基于autoLayout布局：**
 
 可以在 commonInit 调用的时候就把约束添加上去，不要重写 layoutSubviews 方法，因为这种情况下它的默认实现就是根据约束来计算 frame。

