# 搭建vue脚手架
 
## 一、环境搭建

1. 安装node.js

    node.js已经自带npm。安装教程网上很多，安装完成后：

    ![](../image/1.png)

2. 安装淘宝镜像（选做）

    `npm install -g cnpm --registry=https://registry.npm.taobao.org`，安装完成后输入`cnpm -v`出现对应版本号。和npm有关的操作要用`cnpm`替换`npm`。

3. 安装webpack

    命令行工具输入：`npm install webpack -g`，`-g`表示全局安装。安装完成后输入`webpack -v`出现对应版本号，则已成功。

4. 安装vue-cli脚手架工具

    命令行输入：`npm install vue-cli -g`。安装完成后输`vue -V`（大写V）出现对应版本号，则已成功。

ps:公司内部还要另外配置一下代理。

## 二、使用vue-cli构建项目

1. 新建一个文件夹，用来放工程文件。

2. 以管理员权限运行命令行终端。进入新建的文件夹，输入`vue init webpack 项目名（不能用中文）`。之后会让你填一些信息，如果用默认的一直按回车就可以，需要个性化配置按提示输入。

    ![](../image/2.png)

3. 进入新建的工程目录，安装项目依赖`npm install`，会把package.json文件中的依赖进行安装。

4. 接下来执行 `npm run dev`，在浏览器输入`localhost:8080`会看到项目已经运行起来了。
    
    ![](../image/3.png)