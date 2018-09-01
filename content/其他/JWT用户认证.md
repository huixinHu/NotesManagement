## HTTP 基础鉴权

每次请求时都提供用户的username 和 password，是最简单的认证方式，但有暴露用户名密码的风险，尽量少用。

## OAuth

允许用户让第三方应用访问用户在某一服务器上的资源，但无需将用户名和密码提供给第三方。

## cookie

前端登录，后端根据用户信息生成一个token，并**保存这个 token 和对应的用户id到数据库或Session**中，接着把 token 传给用户，存入浏览器 cookie，之后浏览器请求带上这个cookie，后端根据这个cookie值来查询用户，验证是否过期。

存在的问题：

1. XSS漏洞，通过js注入读取cookie，从而泄漏token。解决办法：在设置cookie的时候设置httpOnly。
2. httpOnly 的问题：[跨站请求伪造XSRF](https://blog.csdn.net/stpeace/article/details/53512283)
3. 后端每次都要根据token查出用户id，增加数据库查询和存储开销

## token

token和cookie鉴权的流程对比：

![](https://images2015.cnblogs.com/blog/34831/201606/34831-20160622150124531-1416052185.png)

token相对于cookie的优点：

- 支持跨域访问: Cookie是不允许垮域访问的，这一点对Token机制是不存在的，前提是传输的用户认证信息通过HTTP头传输.
- 无状态:Token机制在服务端不需要存储session信息，因为Token 自身包含了所有登录用户的信息，只需要在客户端的cookie或本地介质存储状态信息.
- 更适用于移动应用: 当客户端是一个原生平台（iOS, Android等）时，Cookie是不被支持的，这时采用Token认证机制就会简单得多。
- **XSS** Session的提交方式，是将Session信息存储在Cookie中，提交到服务器端，因此很容易被客户端注入的javascript代码，截获Cookie信息。
- **XSRF** 基于Session的验证方式，有可能会被跨站请求伪造。

### 基于JWT的token认证机制

JWT:JSON Web Token 已经得到标准化。[官网](https://jwt.io/)

JWT组成：头部、payload、签名。

#### 1.头部

描述JWT的最基本信息，比如token类型（JWT）以及签名使用的算法，表示成一个JSON的形式：

```
{
  "alg": "HS256",
  "typ": "JWT"
}
```
然后进行BASE64编码，得到：`eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9`

#### 2.payload

这个部分是token的具体内容，有一些标准字段：

```
iss：Issuer，发行者
sub：Subject，该JWT所面向的用户
aud：Audience，接收该JWT的一方
exp：Expiration time，过期时间
nbf：Not before 如果当前时间在nbf里的时间之前，则Token不被接受
iat：Issued at，发行时间
jti：JWT ID
```

除此之外，还可以有一些自定义字段。以上这些字段，同样也是用JSON形式表示，然后进行BASE64编码。

比如：

```
{
  "sub": "1234567890",
  "name": "John Doe",
  "iat": 1516239022
}
```
name就是自定义字段，编码后得到：`eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ`

#### 3.签名

对头部和payload进行签名，防止内容被篡改。把之前得到的header和payload以 '.' 拼接：`eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9. eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ `

然后用加密算法处理一下，另外需要提供一个密钥，比如用`secretKey`作为密钥，加密处理后得到：`SneQiuAGUW9aTpxlNNbMkEoYNj7v4-Sw_5jl13-hosk`就是签名。

最后token就是`头部.payload.签名`，由服务端发送给客户端。以后客户端每次向服务端请求时带着这个 Token ，服务端进行验证。

#### 安全问题

1. 登录（验证）需要用户输入用户名和密码，这个过程建议用HTTPS
2. 前端在每次请求时将JWT放入HTTP Header中的Authorization位。(解决XSS和XSRF问题)
3. 防范重放攻击。token设置短的过期时间
4. BASE64是可逆的，所以不应该在token中存放比较敏感的信息。
