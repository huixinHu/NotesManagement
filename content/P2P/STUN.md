# STUN探测流程

客户端A，NAT B，服务端C。

STUN服务端部署在一台有两个公网IP的服务器上，每个公网IP有两个UDP端口，所以服务端有4个UDP套接口：`IPC1:PC1`，`IPC1:PC2`，`IPC2:PC1`，`IPC2:PC2`。客户端的套接字为`IPA:PA`，NAT的公网套接字为`IPB:PB`。

- TEST I

 客户端A`IPA:PA`向服务端C`IPC1:PC1`发一个UDP包。C收到这个包，把包的源IP和源port（记为`IPx:Px`）写到新UDP包中，通过`IPC1:PC1`响应给A。

 如果A收不到响应，有以下的可能：STUN服务器不存在，或者弄错了IP、端口；UDP Block，位于UDP防火墙之后，拒绝一切UDP包从外部向内部通过。

 如果A收到响应比较`IPA:PA`和`IPx:Px`（仅比较IP还是端口也需要？），如果相同，则A连在公网，下一步探测防火墙类型；若不同，则A位于NAT后，需要进一步探测。在这一步可以得到NAT的外网`IPB:PB`。
 
 - TEST II

 客户端A`IPA:PA`向服务端C`IPC1:PC1`发一个UDP包，请求C通过另一个`IPC2:PCx`（IP不一样即可）向A返回一个UDP数据包。根据TEST I：
 
 1.若客户端A连在公网
 
 进行TEST II，A能收到响应，则判断A处于完全开放的网络。如果收不到响应，则客户端A为`Symmetric FireWall`类型（处于对称防火墙之后）。
 
 2.若客户端A位于NAT后
 
  进行TEST II，A能收到响应，说明NAT来者不拒，也就是全锥形。如果没收到响应，进行下一步探测。
  
 - TEST I2

  客户端A`IPA:PA`向服务端C`IPC2:PC2`发一个UDP包，C收到这个包，把包的源IP和源port（也即NAT的外网套接字`IPB2:PB2`）写到新UDP包中，通过`IPC2:PC2`响应给A（A一定能收到）。
  
  `IPB2:PB2`与TEST I中得到的`IPB:PB`比较，若不同，则是对称NAT，否则是限制锥型或者端口限制锥型。
  
 - TEST III

  客户端A`IPA:PA`向服务端C`IPC1:PC1`发一个UDP包，请求C通过`IPC1:PC2`返回一个数据包给客户端A。
  
  如果A收到响应，意味只要IP相同，即使端口不同，NAT也允许数据包通过，因此是限制锥形，如果没有收到响应，则是端口限制锥形。

  