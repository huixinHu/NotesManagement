# STUN探测流程

客户端A，NAT B，服务端C。

STUN服务端部署在一台有两个公网IP的服务器上，每个公网IP有两个UDP端口，所以服务端有4个UDP套接口：`IPC1:PC1`，`IPC1:PC2`，`IPC2:PC1`，`IPC2:PC2`。客户端的套接字为`IPA:PA`，NAT的公网套接字为`IPB:PB`。

- TEST I

 客户端A`IPA:PA`向服务端C`IPC1:PC1`发一个UDP包。C收到这个包，把包的源IP和源port（记为`IPx:Px`）写到新UDP包中，通过`IPC1:PC1`响应给A。

 如果A收不到响应，有以下的可能：STUN服务器不存在，或者弄错了IP、端口；UDP Block，位于UDP防火墙之后，拒绝一切UDP包从外部向内部通过。

 如果A收到响应比较`IPA:PA`和`IPx:Px`（仅比较IP还是端口也需要？），如果相同，则A连在公网，下一步探测防火墙类型；若不同，则A位于NAT后，需要进一步探测。在这一步可以得到NAT的外网`IPB:PB`。