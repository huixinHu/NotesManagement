msgPack本身设计上还有很多可以优化的点，然而这个库实在是太老了，很多年没有人维护过。有一些开发者提的pull requests都没有人merge。

OC版本只支持NSArray、NSDictionary的序列化。比如如果我只是想序列化一个数字，还得先把它放到一个NSArray里面才能序列化。

不支持NSData的序列化，也即官方raw data binary format类型的数据（依我的理解，当然也可能是我没找到正确的序列化方法，OC版本的使用文档真的非常少..）。

根据网上搜集来的信息：如果需要序列化的信息包含大量的字符串，那么msgPack、ProtocolBuffer、FlatBuffers序列化后数据大小相差并不大，因为msgPack和pb对字符串都没有压缩（不了解FlatBuffers所以先不谈）。如果序列化信息中数字较多，那么Pb将会展现出优势。

另外一点：MsgPack的反序列化非常耗内存，相较于其他序列化协议，并没有特别大的优势。

[干货](http://www.cocoachina.com/ios/20180226/22353.html)