本想在这篇文章中单独写AFNetworking 3.0中`AFSecurityPolicy`的源码阅读笔记的。但随着源码阅读的过程，发现关于有太多相关背景知识需要恶补..所以一边学习一边总结写了这篇文章。如果有写错的地方，请及时指正。

# 1.HTTPS
HTTPS 是运行在 TLS/SSL 之上的 HTTP，是为了解决HTTP通信不安全的问题而设计的。

- 对称加密、非对称加密

 对称加密使用同一个密钥进行加密解密，速度快。
非对称加密使用公钥加密，私钥解密，计算量大速度慢。非对称加密又称**公钥密码**技术

 **使用时两者折中。在SSL/TLS中，用“对称加密”来加解密通信信息，速度快；使用“非对称加密”来加解密“对称密钥”。**

- SSL/TLS四次握手

 ![SSL/TLS协议运行机制的概述-阮一峰](http://upload-images.jianshu.io/upload_images/1727123-38e55f4cf39f86c5.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
 
 1.客户端发出请求
 
 - **ClientHello** 向服务器传递随机数1、协议版本、客户端支持的加密套件(Cipher Suites)、压缩方法、签名算法等信息。

 2.服务器回应
 
 - **SeverHello** 服务器收到客户端请求后，向客户端发出回应。传递内容：确认使用的协议版本、从收到的客户端加密套件中筛选出来的加密方法、压缩算法和签名算法，和服务器新生成的一个随机数2等等返回给客户端。
 - **severCertificate** 服务器发送数字证书（其实就是要拿到公钥）。
 - **CertificateRequest** 如果服务器需要确认客户端的身份（双向认证），就会再包含一项请求，要求客户端提供"客户端证书"。比如，金融机构往往只允许认证客户连入自己的网络，就会向正式客户提供USB密钥，里面就包含了一张客户端证书。

 3.客户端回应
 
 - **Client Key Exchange** 客户端确认证书有效，则会生产最后一个随机数3（pre-master key），并使用证书的公钥加密这个随机数，发回给服务端。（为了更高的安全性，会使用Diffie-Hellman算法；采用DH算法，最后一个随机数是不需要传递的，客户端和服务端交换参数之后就可以算出）
 - **Change Cipher Spec** 通知对方，编码改变，接下来的所有消息都会使用双方商定的加密方法和密钥发送。
 - **Finished** 客户端握手结束通知，表示客户端的握手阶段已经结束。该报文包含前面发送的所有报文的整体校验值（hash），用来供服务器校验。

 4.服务器回应
 
 - **Change Cipher Spec** 服务端同样发送Change Cipher Spec报文。
 - **Finished** 服务端同样发送Finished报文

 至此，整个握手阶段全部结束。**接下来，客户端与服务器进入加密通信，就完全是使用普通的HTTP协议，只不过用"会话密钥"加密内容**。
 
 至于这个会话密钥呢，就是通信两端同时拥有的三个随机数，用双方事先商定的加密方法，各自生成之后通信所用的对称密钥。

- 简单总结一下，这四次握手过程主要交换了：

 1.证书，一般由服务器发给客户端；验证证书是不是可信机构颁发的，如果是自签证书，一般在客户端本地置入证书拷贝，然后两份证书对比来判断证书是否可信。
如果是双向认证的，客户端也要给服务器发送证书。[关于单向、双向认证](http://blog.csdn.net/duanbokan/article/details/50847612)

 2.三个随机数，用来生成后续通信进行加解密的对称密钥。其中前两个随机数都是明文传输，只有第三个随机数是加密的（公钥足够长，2048位，可保证不被破解）。
为什么是三个随机数？SSL协议不相信每个主机都能产生完全随机的随机数，如果只有一个伪随机数就容易被破解，如果3个伪随机数就接近随机了。

 3.加密方式

- 其他，session恢复
由于新建立一个SSL/TLS Session的成本太高，所以之前有建立SSL/TLS连接Session的话，客户端会保存Session ID。如果对话中断，在下一次请求时在Client Hello中带上session ID，服务端验证有效之后，就会成功重用Sesssion。双方就不再进行握手阶段剩余的步骤，而直接用已有的对话密钥进行加密通信

# 2.数字证书
这里先简单讲一些**数字签名**。**它能确认消息的完整性，进行认证。**和*公钥密码*一样也要用到一对公钥、私钥。但*签名*是用私钥加密（生成签名），公钥解密（验证签名）。**私钥加密只能由持有私钥的人完成，而由于公钥是对外公开的，因此任何人都可以用公钥进行解密（验证签名）。**

要确认公钥是否合法，就需要使用证书。

公钥证书一般会记有姓名、组织、邮箱地址等个人信息，以及属于本人的公钥，并由认证机构(CA)进行数字签名。通过认证机构使用证书的过程如下图所示：

![《图解密码技术》](http://upload-images.jianshu.io/upload_images/1727123-1176119070bafa1a.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

公钥基础设施(PKI)是为了能够更有效地运用公钥而制定的一系列规范和规格的总称。使用最广泛的 X.509 规范也是PKI的一种。

- 证书链
CA有层级的关系，处于最顶层的认证机构一般就称为根CA。下层证书是经过上层签名的。而**根CA则会对自己的证书进行签名，即自签名**。

![](http://upload-images.jianshu.io/upload_images/1727123-cfadf3f6ff90cdbb.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 **怎么验证证书有没有被篡改？**
 
当客户端走 HTTPS 访问站点时，服务器会返回整个证书链。先从最底层的CA开始，用上层的公钥对下层证书的数字签名进行验证。这样逐层向上验证，直到遇到了锚点证书。

- 锚点证书
嵌入到操作系统中的根证书（系统隐式信任的证书），通常是包括在系统中的 CA 根证书。不过你也可以在验证证书链时，设置自定义的证书作为可信的锚点。


# 3.SSL Pinning 
HTTPS挺安全的但也不是无懈可击。本人在网络安全方面也不是专业的，这里就简单说一点。中间人攻击。简单来说，iPhone信任的证书包括一些预装的证书和用户自己安装的证书，如果攻击者手上拥有一个受信任的证书，那么就会发生中间人攻击了。

这时候就需要SSL Pinning 了，原理是把server证书的拷贝捆绑在APP中，client通过对比server发来的证书检测它有没有被篡改。结合[这篇文章](http://www.kancloud.cn/digest/ios-security/67013)中讲的SSL中间人攻击、模拟攻击实例，对上面所讲的有更好的理解。

# 4.证书校验
## 4.1域名验证
服务器证书上的域名和请求域名是否匹配。
使用NSURLSession获取默认验证策略：

```objective-c
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    CFArrayRef defaultPolicies = NULL;//获取默认的校验策略
    SecTrustCopyPolicies(trust, &defaultPolicies);
    NSLog(@"Default Trust Policies: %@", (__bridge id)defaultPolicies);
}
```

默认的验证策略是包含域名验证的。如果想重置验证策略，可以调用`SecTrustSetPolicies `。比如AFNetworking中就是这样做的：

```objective-c
NSMutableArray *policies = [NSMutableArray array];
//BasicX509 就是不验证域名，返回的服务器证书，只要是可信任CA机构签发的，都会校验通过
[policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];    
//设置评估中要使用的策略
SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
```

## 4.2校验证书链
> 证书链的验证，主要由三部分来保证证书的可信：叶子证书是对应HTTPS请求域名的证书，根证书是被系统信任的证书，以及这个证书链之间都是层层签发可信任链；证书之所以能成立，本质是基于信任链，这样任何一个节点证书加上域名校验（CA机构不会为不同的对不同的用户签发相同域名的证书），就确定一条唯一可信证书链。

基于证书信任链进行校验。如果该信任链只包含有效的证书并以已知的锚证书结束，那么证书被认为是有效的(当返回的服务器证书是锚点证书或者是基于该证书签发的证书（可以是多个层级）都会被信任)。这里的锚证书也可以是自定义的证书，使用`SecTrustSetAnchorCertificates `函数设置锚点证书。比如AFNetworking中：

```objective-c
NSMutableArray *pinnedCertificates = [NSMutableArray array];
//把nsdata证书（der编码的x.509证书）转成SecCertificateRef类型的数据
for (NSData *certificateData in self.pinnedCertificates) {
  [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
}
//将本地证书设置成需要参与验证的锚点证书
SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
//验证服务器证书是否可信（由系统默认可信或者由用户选择可信）。
if (!AFServerTrustIsValid(serverTrust)) {
  return NO;
}
```

ps:只使用`SecTrustSetAnchorCertificates`函数，没使用`SecTrustSetAnchorCertificatesOnly`，就只会相信`SecTrustSetAnchorCertificates`由该锚点证书颁发的证书，哪怕是由系统其他锚点证书颁发的其他证书也不会通过验证。

如果要想恢复系统中 CA 证书作为锚点的功能：

```objective-c
// true 代表仅被传入的证书作为锚点，false 允许系统 CA 证书也作为锚点
SecTrustSetAnchorCertificatesOnly(trust, false);
```

## 4.3SSL Pinning把证书打包进app
如果用户访问不安全链接并且选择信任了不该信任的证书，证书校验依赖的源受污染，因此不能只依赖证书链来进行证书校验。安全的做法是，把证书拷贝打包进app中并把它作为锚点证书，然后和服务器的证书链做匹配。

比如在AFNetworking中：

```objective-c
SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
//验证服务器证书是否可信（由系统默认可信或者由用户选择可信）。
if (!AFServerTrustIsValid(serverTrust)) {
    return NO;
}
//从我们需要被验证的服务端去拿证书链
//这里的证书链顺序是从叶节点到根节点
NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
//逆序，从根节点开始匹配            
for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
     //如果本地证书中，有一个和它证书链中的证书匹配的，就返回YES
    if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
        return YES;
    }
}
```

# 5.AFNetworking3.0版本中的HTTPS认证
自 iOS 9 发布之后，由于新特性App Transport Security的引入，默认情况下是不能发送 HTTP 请求的。很多网站都在转用 HTTPS，而 `AFNetworking`中的 `AFSecurityPolicy`就是用来满足我们各种https认证需求的。

接下来从源码入手分析`AFSecurityPolicy`内部是如何做https认证的。（AF默认做的仅仅是单向认证，如果要做双向认证就只能自己写block来实现了）

##5.1AFSSLPinningMode和重要属性
1. AFSSLPinningMode共提供了三种验证方式

```objective-c
typedef NS_ENUM(NSUInteger, AFSSLPinningMode) {//三种验证服务器的方式
    AFSSLPinningModeNone,//不使用固定证书（本地）验证服务器。直接从客户端系统中的受信任颁发机构 CA 列表中去验证
    AFSSLPinningModePublicKey,//根据本地固定证书公钥验证服务器证书，不验证证书的有效期等信息
    AFSSLPinningModeCertificate,//根据本地固定证书验证服务器证书
};
```
**AFSSLPinningModeNone**不做本地证书验证，直接从客户端系统中的受信任颁发机构 CA 列表中去验证服务端返回的证书，若证书是信任机构签发的就通过，若是自己服务器生成的证书，这里是不会通过的。
**AFSSLPinningModePublicKey**用ssl pinning方式验证服务端返回的证书，只验证公钥。客户端要有服务端证书拷贝
**AFSSLPinningModeCertificate**根据本地固定证书验证服务器证书

2. AFSecurityPolicy中重要的属性
```根据本地固定证书验证服务器证书
//ssl pinning的模式，默认是AFSSLPinningModeNone
@property (readonly, nonatomic, assign) AFSSLPinningMode SSLPinningMode;
//本地证书，用于验证服务器
@property (nonatomic, strong, nullable) NSSet <NSData *> *pinnedCertificates;
//是否信任无效或者过期的ssl证书，默认不信任（比如自签名证书）
@property (nonatomic, assign) BOOL allowInvalidCertificates;
//是否验证证书域名，默认是YES
@property (nonatomic, assign) BOOL validatesDomainName;
//本地证书公钥
@property (readwrite, nonatomic, strong) NSSet *pinnedPublicKeys;
```

## 5.2初始化及设置
1.初始化

```objective-c
//创建一个默认的AFSecurityPolicy，SSLPinningMode是不验证
+ (instancetype)defaultPolicy {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = AFSSLPinningModeNone;
    return securityPolicy;
}

+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode {
    return [self policyWithPinningMode:pinningMode withPinnedCertificates:[self defaultPinnedCertificates]];
}

//根据指定的验证模式、证书创建AFSecurityPolicy
+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode withPinnedCertificates:(NSSet *)pinnedCertificates {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = pinningMode;
    [securityPolicy setPinnedCertificates:pinnedCertificates];
    return securityPolicy;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    self.validatesDomainName = YES;//验证证书域名
    return self;
}
```
这里没有什么地方值得解释的，根据需要选择创建一个默认的AFSecurityPolicy，或者根据指定的AFSSLPinningMode、PinnedCertificates创建AFSecurityPolicy。
在AF中是这样创建一个securityPolicy的：`self.securityPolicy = [AFSecurityPolicy defaultPolicy];`

2.设置本地证书PinnedCertificates

在调用`- setPinnedCertificates:`方法设置本地证书时，会把全部证书的公钥取出来存放到`pinnedPublicKeys`属性中，方便之后用于AFSSLPinningModePublicKey方式的验证.

```objective-c
//设置用于评估服务器是否可信的证书（本地证书）
//把证书中每个公钥放在了self.pinnedPublicKeys中,用于AFSSLPinningModePublicKey方式的验证
- (void)setPinnedCertificates:(NSSet *)pinnedCertificates {
    _pinnedCertificates = pinnedCertificates;

    if (self.pinnedCertificates) {
        //遍历取出所有证书中的公钥，然后保存在self.pinnedPublicKeys属性中
        NSMutableSet *mutablePinnedPublicKeys = [NSMutableSet setWithCapacity:[self.pinnedCertificates count]];
        for (NSData *certificate in self.pinnedCertificates) {
            id publicKey = AFPublicKeyForCertificate(certificate);//从证书中获取公钥
            if (!publicKey) {
                continue;
            }
            [mutablePinnedPublicKeys addObject:publicKey];
        }
        self.pinnedPublicKeys = [NSSet setWithSet:mutablePinnedPublicKeys];
    } else {
        self.pinnedPublicKeys = nil;
    }
}
```

3.其他

```objective-c
//以NSData的形式获取某个目录下的所有证书
+ (NSSet *)certificatesInBundle:(NSBundle *)bundle;
//以NSData的形式获取当前class目录下的所有证书
+ (NSSet *)defaultPinnedCertificates;
```

## 5.3核心方法
`- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain`
这个方法可以说是这个类的核心了。**用于验证服务器是否可信。**
这个方法有两个参数：`SecTrustRef类型`的`serverTrust`和`NSString`类型的`domain`

- SecTrustRef是啥

 在这个方法中，这个serverTrust是服务器传过来的，包含了服务器的证书信息。
大概是用来执行X.509证书信任评估的。

 > 其实就是一个容器，装了服务器端需要验证的证书的基本信息、公钥等等，不仅如此，它还可以装一些评估策略，还有客户端的锚点证书，这个客户端的证书，可以用来和服务端的证书去匹配验证的。
每一个SecTrustRef对象包含多个SecCertificateRef 和 SecPolicyRef。其中 SecCertificateRef 可以使用 DER 进行表示。

- domain服务器域名，用于域名验证

代码解析如下：

```objective-c
//验证服务端是否可信，这个serverTrust是服务器传过来的，里面包含了服务器的证书信息，是用于我们本地客户端去验证该证书是否合法用的
- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain
{
    //判断矛盾的条件
    //如果有服务器域名、设置了允许信任无效或者过期证书（自签名证书）、需要验证域名、没有提供证书或者不验证证书，返回no。后两者和allowInvalidCertificates为真的设置矛盾，说明这次验证是不安全的。
    if (domain && self.allowInvalidCertificates && self.validatesDomainName && (self.SSLPinningMode == AFSSLPinningModeNone || [self.pinnedCertificates count] == 0)) {
        // https://developer.apple.com/library/mac/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/OverridingSSLChainValidationCorrectly.html
        //  According to the docs, you should only trust your provided certs for evaluation.
        //  Pinned certificates are added to the trust. Without pinned certificates,
        //  there is nothing to evaluate against.
        //
        //  From Apple Docs:
        //          "Do not implicitly trust self-signed certificates as anchors (kSecTrustOptionImplicitAnchors).
        //           Instead, add your own (self-signed) CA certificate to the list of trusted anchors."
        NSLog(@"In order to validate a domain name for self signed certificates, you MUST use pinning.");
        return NO;
    }

    //生成验证策略。如果要验证域名，就以域名为参数创建一个策略，否则创建默认的basicX509策略
    NSMutableArray *policies = [NSMutableArray array];
    if (self.validatesDomainName) {
        //SecPolicyCreateSSL函数，创建用于评估SSL证书链的策略对象。第一个参数：true将为SSL服务器证书创建一个策略。第二个参数：如果这个参数存在，证书链上的叶子节点表示的那个domain要和传入的domain相匹配
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];//该策略不检验域名
    }
    
    //设置评估中要使用的策略
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);//为serverTrust设置验证的策略

    //如果是AFSSLPinningModeNone（不做本地证书验证，从客户端系统中的受信任颁发机构 CA 列表中去验证）
    if (self.SSLPinningMode == AFSSLPinningModeNone) {
        //不使用ssl pinning 但允许自建证书，直接返回YES；否则进行第二个条件判断，去客户端系统根证书里找是否有匹配的证书，验证serverTrust是否可信，直接返回YES；否则进行第二个条件判断，去客户端系统根证书里找是否有匹配的证书，验证serverTrust是否可信
        return self.allowInvalidCertificates || AFServerTrustIsValid(serverTrust);
    }
    //如果serverTrust不可信且不允许自签名，返回NO
    else if (!AFServerTrustIsValid(serverTrust) && !self.allowInvalidCertificates) {
        return NO;
    }

    //根据不同的SSLPinningMode分情况验证
    switch (self.SSLPinningMode) {
        //不验证
        case AFSSLPinningModeNone://上一部分已经判断过了，如果执行到这里的话就返回NO
        default:
            return NO;
        //验证证书
        case AFSSLPinningModeCertificate: {
            NSMutableArray *pinnedCertificates = [NSMutableArray array];
            //把nsdata证书（der编码的x.509证书）转成SecCertificateRef类型的数据
            for (NSData *certificateData in self.pinnedCertificates) {
                [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
            }
            // 将本地证书设置成需要参与验证的锚点证书，设为服务器信任的证书（锚点证书通常指：嵌入到操作系统中的根证书，通过SecTrustSetAnchorCertificates设置了参与校验锚点证书之后，假如验证的数字证书是这个锚点证书的子节点，即验证的数字证书是由锚点证书对应CA或子CA签发的，或是该证书本身，则信任该证书）
            //第二个参数，表示在验证证书时被SecTrustEvaluate函数视为有效（可信任）锚点的锚定证书集。 传递NULL以恢复默认的锚证书集。
            //自签证书在这步之前验证通过不了，把本地证书添加进去后就能验证成功。
            SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
            //验证服务器证书是否可信。
            if (!AFServerTrustIsValid(serverTrust)) {
                return NO;
            }

            // obtain the chain after being validated, which *should* contain the pinned certificate in the last position (if it's the Root CA)
            //从我们需要被验证的服务端去拿证书链
            //这里的证书链顺序是从叶节点到根节点
            NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
            //服务端证书链从根节点往叶节点遍历
            for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {//reverseObjectEnumerator逆序
                //如果本地证书中，有一个和它证书链中的证书匹配的，就返回YES
                if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
                    return YES;
                }
            }
            
            return NO;
        }
        //公钥验证 客户端有服务端的证书拷贝，只要公钥是正确的，就能保证通信不会被窃听，因为中间人没有私钥，无法解开通过公钥加密的数据。
        case AFSSLPinningModePublicKey: {
            NSUInteger trustedPublicKeyCount = 0;
            // 从serverTrust中取出服务器端传过来的所有可用的证书，并依次得到相应的公钥
            NSArray *publicKeys = AFPublicKeyTrustChainForServerTrust(serverTrust);
            //和本地公钥遍历对比
            for (id trustChainPublicKey in publicKeys) {
                for (id pinnedPublicKey in self.pinnedPublicKeys) {
                    if (AFSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
                        trustedPublicKeyCount += 1;//判断如果相同 trustedPublicKeyCount+1
                    }
                }
            }
            return trustedPublicKeyCount > 0;
        }
    }
    
    return NO;
}
```

**总结一下这个方法做了什么**

1.判断设置上的矛盾条件。

允许使用自建证书`self.allowInvalidCertificates=YES`，还想验证域名是否有效`self.validatesDomainName=YES`，那么必须使用SSL Pinning方式验证，但`AFSSLPinningModeNone `表示不使用SSL Pinning。再者，如果没有`pinnedCertificates`（在客户端保存的服务器颁发的证书拷贝，在下文称为“本地证书”），表示无法验证自建证书。

2.创建证书评估策略

如果要验证域名，就创建评估SSL证书链的策略；如果不验证域名，就使用默认的X509验证策略。

3.设置评估策略

4.（在还没设置本地锚点证书下，做第一次服务器验证）

4.1如果是`AFSSLPinningModeNone`，不使用ssl pinning 但允许自建证书，直接返回YES；或者使用`SecTrustEvaluate`去客户端系统根证书里找是否有匹配的证书，验证serverTrust是否可信。

4.2serverTrust不可信且不允许自建证书，返回NO。

5.根据不同的SSL Pinning Mode验证

5.1 `AFSSLPinningModeNone `
直接返回NO，因为前面的处理应该可以解决这种情况了。

5.2 `AFSSLPinningModeCertificate`
将本地证书设置成锚点证书，然后调用`SecTrustEvaluate`验证服务端证书是否可信。拿到服务端证书链，如果本地证书中有一个和它证书链中的证书匹配的（相当于是认为服务端证书在本地信任的证书列表中？）就返回YES。

假设是自签证书，因为APP bundle中的证书不是CA机构颁发的，不被信任。要调用`SecTrustSetAnchorCertificates `将本地证书设置成serverTrust证书链上的锚点证书（好比于将这些证书设置成系统信任的根证书），然后调用`SecTrustEvaluate`校验，如果遇到锚点证书就终止校验了。

5.3 `AFSSLPinningModePublicKey`
取出服务端证书公钥，和本地证书公钥进行匹配。

这个核心方法中用到一些私有函数，这里简单讲一下。

**1.AFPublicKeyForCertificate、AFServerTrustIsValid、AFCertificateTrustChainForServerTrust**

这三个函数的实现比较相似，这里放一起讲。

```objective-c
//在证书中获取公钥
static id AFPublicKeyForCertificate(NSData *certificate) {
    //1.初始化临时变量
    id allowedPublicKey = nil;
    SecCertificateRef allowedCertificate;//SecCertificateRef包含有关证书的信息
    SecPolicyRef policy = nil;
    SecTrustRef allowedTrust = nil;
    SecTrustResultType result;

    //2.创建SecCertificateRef对象，判断返回值是否为null
    //通过DER格式的证书（NSData）生成SecCertificateRef类型的证书引用。 如果传入的数据不是有效的DER编码的X.509证书，则返回NULL。
    //传入的第二个参数是CFDataRef类型，要用__bridge把oc对象转Core Foundation对象
    allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificate);
    //__Require_Quiet这个宏，判断allowedCertificate != NULL表达式是否为假，如果allowedCertificate=NULL，就跳到_out标签处执行
    __Require_Quiet(allowedCertificate != NULL, _out);

    //3.1.新建默认策略为X.509的SecPolicyRef策略对象
    policy = SecPolicyCreateBasicX509();
    /*3.2.
     OSStatus SecTrustCreateWithCertificates(CFTypeRef certificates,
     CFTypeRef __nullable policies, SecTrustRef * __nonnull CF_RETURNS_RETAINED trust)
     基于给定的证书和策略创建一个SecTrustRef信任引用对象，然后赋值给trust。
     这个函数返回一个结果码，判断是否出错
     */
    //__Require_noErr_Quiet，第一个参数是错误码表达式，如果不等于0（出错了）就跳到_out标签处执行
    __Require_noErr_Quiet(SecTrustCreateWithCertificates(allowedCertificate, policy, &allowedTrust), _out);//创建SecTrustRef，如果出错就跳到_out
    //3.3对SecTrustRef进行信任评估，确认它是值得信任的
    __Require_noErr_Quiet(SecTrustEvaluate(allowedTrust, &result), _out);

    //4.获取证书公钥
    //__bridge_transfer会将结果桥接成OC对象，然后将 SecTrustCopyPublicKey 返回的指针释放
    allowedPublicKey = (__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust);

_out:
    //5.释放c指针
    if (allowedTrust) {
        CFRelease(allowedTrust);
    }

    if (policy) {
        CFRelease(policy);
    }

    if (allowedCertificate) {
        CFRelease(allowedCertificate);
    }

    return allowedPublicKey;
}
```
这里用到的系统宏`__Require_Quiet`，是用来判断`allowedCertificate != NULL`表达式是否为假，如果`allowedCertificate=NULL`，就跳到_out标签处执行代码。

**AFPublicKeyTrustChainForServerTrust**函数的实现和它差不多，这里就不具体展开了，用于取出服务器返回的证书链的每个证书公钥。

Q:一点疑问，如果是自签证书，在获取本地证书公钥和服务器证书公钥的函数中，是怎么在没有设置锚点证书的情况下，通过`SecTrustEvaluate `检验证书可信的？

```objective-c
//取出服务器返回的证书链上所有证书
static NSArray * AFCertificateTrustChainForServerTrust(SecTrustRef serverTrust) {
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);//获取评估证书链中的证书数目。
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    //遍历获取证书链中的每个证书，并添加到trustChain中//获取的顺序，从证书链的叶节点到根节点
    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);//取得证书链中对应下标的证书
        //返回der格式的x.509证书
        [trustChain addObject:(__bridge_transfer NSData *)SecCertificateCopyData(certificate)];
    }

    return [NSArray arrayWithArray:trustChain];
}
```

 **2.AFServerTrustIsValid**
 
```objective-c
//验证serverTrust是否有效
static BOOL AFServerTrustIsValid(SecTrustRef serverTrust) {
    BOOL isValid = NO;
    SecTrustResultType result;
    __Require_noErr_Quiet(SecTrustEvaluate(serverTrust, &result), _out);//评估证书是否可信，确认它是值得信任的.
    /*SecTrustResultType结果有两个维度。 1.serverTrust评估是否成功，2.是否由用户决定评估成功。
     如果是用户决定的，成功是 kSecTrustResultProceed 失败是kSecTrustResultDeny。
     非用户定义的， 成功是kSecTrustResultUnspecified 失败是kSecTrustResultRecoverableTrustFailure
     用户决策通过使用SecTrustCopyExceptions（）和SecTrustSetExceptions（）*/
    isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);

 _out:
    return isValid;
}
/*
#ifndef __Require_noErr_Quiet
	#define __Require_noErr_Quiet(errorCode, exceptionLabel)                      \
	  do                                                                          \
	  {                                                                           \
		  if ( __builtin_expect(0 != (errorCode), 0) )                            \
		  {                                                                       \
			  goto exceptionLabel;                                                \
		  }                                                                       \
	  } while ( 0 )
#endif
*/
```

这个函数核心是用`SecTrustEvaluate `函数来验证serverTrust是否有效，返回一个`SecTrustResultType `类型的result。

`SecTrustResultType`的结果有两个维度。 1.serverTrust评估是否成功，2.是否由用户决定评估成功。
 
 - 如果是用户决定的（比如系统弹窗出来让用户决定是否信任证书），成功是`kSecTrustResultProceed`失败是`kSecTrustResultDeny`。
 - 非用户定义的， 成功是`kSecTrustResultUnspecified`失败是`kSecTrustResultRecoverableTrustFailure`

关于`__Require_noErr_Quiet`这个宏，是用来判断errorCode是否为0的，如果不为0就跳到exceptionLabel标签处执行代码。所以这里的意思就是，如果`SecTrustEvaluate `评估出错，就跳到_out标签那执行代码令isValid=0。

以下用到的原生c函数：

```objective-c
//1.创建用于评估SSL证书链的策略对象。第一个参数：true将为SSL服务器证书创建一个策略。第二个参数：如果这个参数存在，证书链上的叶子节点表示的那个domain要和传入的domain相匹配
SecPolicyCreateSSL(<#Boolean server#>, <#CFStringRef  _Nullable hostname#>)
//2.默认的BasicX509验证策略,不验证域名。
SecPolicyCreateBasicX509();
//3.为serverTrust设置验证策略
SecTrustSetPolicies(<#SecTrustRef  _Nonnull trust#>, <#CFTypeRef  _Nonnull policies#>)
//4.验证serverTrust,并且把验证结果返回给第二参数 result
//函数内部递归地从叶节点证书到根证书验证。使用系统默认的验证方式验证Trust Object，根据上述证书链的验证可知，系统会根据Trust Object的验证策略，一级一级往上，验证证书链上每一级证书有效性。
SecTrustEvaluate(<#SecTrustRef  _Nonnull trust#>, <#SecTrustResultType * _Nullable result#>)
//5.根据证书data,去创建SecCertificateRef类型的数据。
SecCertificateCreateWithData(<#CFAllocatorRef  _Nullable allocator#>, <#CFDataRef  _Nonnull data#>)
//6.给serverTrust设置锚点证书，即如果以后再次去验证serverTrust，会从锚点证书去找是否匹配。
SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
//7.拿到证书链中的证书个数
SecTrustGetCertificateCount(serverTrust);
//8.去取得证书链中对应下标的证书。
SecTrustGetCertificateAtIndex(serverTrust, i)
//8.根据证书获取公钥。
SecTrustCopyPublicKey(trust)
```

## 5.4在AF中的调用
```objective-c
- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    /*挑战处理类型
            NSURLSessionAuthChallengeUseCredential              使用指定证书
            NSURLSessionAuthChallengePerformDefaultHandling     默认方式处理
            NSURLSessionAuthChallengeCancelAuthenticationChallenge  取消挑战The entire request will be canceled; the credential parameter is ignored
            NSURLSessionAuthChallengeRejectProtectionSpace拒接认证请求。
     */
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;

    //sessionDidReceiveAuthenticationChallenge是自定义方法，用来处理如何应对服务器端的认证挑战
    if (self.sessionDidReceiveAuthenticationChallenge) {
        disposition = self.sessionDidReceiveAuthenticationChallenge(session, challenge, &credential);
    } else {
        // 也就是说服务器端需要客户端返回一个根据认证挑战的保护空间提供的信任（即challenge.protectionSpace.serverTrust）产生的挑战证书。
        //要求对保护空间执行服务器证书认证
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            // 基于客户端的安全策略来决定是否信任该服务器，不信任的话，也就没必要响应挑战
            if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                // 创建挑战证书
                //创建并返回一个NSURLCredential对象，以使用给定的可接受的信任进行服务器信任身份验证。
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
                // 确定挑战的方式
                if (credential) {
                    //证书挑战  设计policy,none，则跑到这里
                    disposition = NSURLSessionAuthChallengeUseCredential;
                } else {
                    disposition = NSURLSessionAuthChallengePerformDefaultHandling;
                }
            } else {
                //取消挑战
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            //默认挑战方式
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    }
    //完成挑战
    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}
```

这个方法大概做了什么：

1. 首先指定了处理认证挑战的默认方式。
2. 判断有没有自定义Block:sessionDidReceiveAuthenticationChallenge，有的话，使用我们自定义Block,自定义处理应对服务器端的认证挑战。
3. 如果没有自定义Block，我们判断如果服务端的认证方法要求是NSURLAuthenticationMethodServerTrust,则只需要验证服务端证书是否安全（即https的单向认证，这是AF默认处理的认证方式，其他的认证方式，只能由我们自定义Block的实现）

 3.1接着我们就执行了AFSecurityPolicy相关的一个方法，做了一个AF内部的一个对服务器的认证：
`[self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host])`
AF默认的处理是，如果这行返回NO、说明AF内部认证失败，则取消https认证，即取消请求。返回YES则进入if块，用服务器返回的一个serverTrust去生成了一个认证证书。然后如果有证书，则用证书认证方式，否则还是用默认的验证方式。

最后调用completionHandler传递认证方式和要认证的证书，去做系统根证书验证。

> 总结：这里securityPolicy存在的作用就是，使得在系统底层自己去验证之前，AF可以先去验证服务端的证书。如果通不过，则直接越过系统的验证，取消https的网络请求。否则，继续去走系统根证书的验证。
>
> 系统验证的流程：
>
> 系统的验证，首先是去系统的根证书找，看是否有能匹配服务端的证书，如果匹配，则验证成功，返回https的安全数据。
>
> 如果不匹配则去判断ATS是否关闭，如果关闭，则返回https不安全连接的数据。如果开启ATS，则拒绝这个请求，请求失败。
**AF的验证方式不是必须的，但是对有特殊验证需求的用户确是必要的。**

系统api上的一些用法记录：

- NSURLAuthenticationChallenge

 ```objective-c
@property (readonly, copy) NSURLProtectionSpace *protectionSpace;
NSURLProtectionSpace对象，受保护空间，代表了服务器上的一块需要授权信息的区域。包括了服务器地址、端口等信息。

 @property (nullable, readonly, copy) NSURLCredential *proposedCredential;
这个认证挑战 建议使用的证书

 @property (readonly) NSInteger previousFailureCount;
认证失败的次数

 @property (nullable, readonly, copy) NSURLResponse *failureResponse;
最后一次认证失败的响应信息

 @property (nullable, readonly, copy) NSError *error;
认真失败的错误信息

 @property (nullable, readonly, retain) id<NSURLAuthenticationChallengeSender> sender;
代理对象，challenge的发送者， NSURLSession、connection对象之类的
```
 `NSURLAuthenticationChallenge`类型的参数简单理解来说，就是服务端发起的认证挑战，客户端要根据认证挑战的类型提供响应的挑战凭证`（NSURLCredential）`。

 由于`- URLSession:didReceiveChallenge:completionHandler:`回调时不止HTTPS服务器身份鉴别，因此首先判断一下身份鉴别的类型。通过`challenge.protectionSpace.authenticationMethod`可以获取。

 `NSURLAuthenticationMethodServerTrust`指对`protectionSpace`执行服务器证书验证。

 **响应挑战**

 通过sender代理实例，让客户端来选择怎样的挑战响应方式。

 ```objective-c
// 用凭证响应挑战。如果是双向验证，不仅客户端要验证服务器身份，服务器也需要客户端提供证书，因此需要提供凭证
 - (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
//不提供凭证继续请求
 - (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
//取消凭证验证
 - (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
//使用默认方式处理认证挑战
 - (void)performDefaultHandlingForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
//拒绝当前提供的受保护空间并且尝试不提供凭证继续请求
 - (void)rejectProtectionSpaceAndContinueWithChallenge:(NSURLAuthenticationChallenge *)challenge;
```

- NSURLCredential

 表示身份验证证书（凭证）。URL Lodaing支持3种类型证书：password-based user credentials, certificate-based user credentials, 和certificate-based server credentials(需要验证服务器身份时使用)。NSURLCredential可以表示由用户名/密码组合、客户端证书及服务器信任创建的认证信息，适合大部分的认证请求。

 对于NSURLCredential也存在三种持久化机制：

  1. NSURLCredentialPersistenceNone ：要求 URL 载入系统 “在用完相应的认证信息后立刻丢弃”。
  2. NSURLCredentialPersistenceForSession ：要求 URL 载入系统 “在应用终止时，丢弃相应的 credential ”。
  3. NSURLCredentialPersistencePermanent ：要求 URL 载入系统 “将相应的认证信息存入钥匙串（keychain），以便其他应用也能使用。

- 如何处理挑战。 `NSURLSessionAuthChallengeDisposition`类型的数据，是一个常数：
```
NSURLSessionAuthChallengeUseCredential              使用指定证书
NSURLSessionAuthChallengePerformDefaultHandling     默认方式处理
NSURLSessionAuthChallengeCancelAuthenticationChallenge  取消挑战The entire request will be canceled; the credential parameter is ignored
NSURLSessionAuthChallengeRejectProtectionSpace拒接认证请求。
```

详细源码注释[请戳github](https://github.com/huixinHu/AFNetworking-)

参考文章：

[图解SSL/TLS协议](http://www.ruanyifeng.com/blog/2014/09/illustration-ssl.html)

[iOS安全系列之二：HTTPS进阶](http://www.kancloud.cn/digest/ios-security/67013)

[iOS 中 HTTPS 证书验证浅析](http://www.cnblogs.com/bugly/p/6289150.html)

[iOS 中对 HTTPS 证书链的验证](http://www.jianshu.com/p/31bcddf44b8d)
[AFNetworking之于https认证](http://www.jianshu.com/p/a84237b07611)

[深入理解HTTPS及在iOS系统中适配HTTPS类型网络请求(上)](https://my.oschina.net/u/2340880/blog/807358)

[深入理解HTTPS及在iOS系统中适配HTTPS类型网络请求(下)](https://my.oschina.net/u/2340880/blog/807863)

[iOS HPPTS证书验证](http://blog.csdn.net/myzlhh/article/details/50255805)