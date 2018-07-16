## 一、增删改

### 创建本地仓库 

`git init`

当前目录下会多了一个.git目录（隐藏目录），是git用来跟踪管理仓库的。

### 添加文件修改到暂存区 `git add filename`

该命令不会有任何输出，用于添加单个文件。如果需要添加所有改动过的文件，可以`git add -a`或者`git add .`

### 提交修改到本地仓库

`git commit -m "此次提交的说明"`

```
$ git commit -m "modify"
[master 6926c51] modify
 1 file changed, 1 insertion(+), 1 deletion(-)
```

提交的是已经执行了`git add`放入暂存区中的修改，没放入暂存区的修改不会被提交。

### 查看本地仓库当前状态 

`git status`

修改一个文件，然后运行`git status` ：

```
On branch master
Your branch is up to date with 'origin/master'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git checkout -- <file>..." to discard changes in working directory)

	modified:   123.txt

no changes added to commit (use "git add" and/or "git commit -a")
```

上面的输出：123.txt文件已经被修改，但还没有添加到暂存区（即还没有执行`git add`，可以执行一次`git add .`然后再执行`git status`看一下输出结果）。同时可以使用`git checkout -- filename`来撤销修改。

### 查看文件具体修改内容 

`git diff`

### 撤销修改

#### 1.还没`git add`，修改仍在工作区

`git checkout -- filename` 把文件在工作区的修改全部撤销，让这个文件回到最近一次`git commit`或`git add`时的状态。

一种是文件自修改后还没有执行`git add`被放到暂存区，撤销修改就回到和本地库一模一样的状态；

一种是文件已经执行过`git add`添加到暂存区后，又作了修改，撤销修改就回到最近一次执行`git add`后的状态。

`git checkout`其实是用版本库里的版本替换工作区的版本，无论工作区是修改还是删除文件，都可以“一键还原”。

#### 2.已经`git add`到暂存区，但还没`commit`

`git reset HEAD filename`把该文件暂存区的修改**全部**撤销。

#### 3.已经`commit`但还没有`push`

查看版本历史记录：`git log`。例如：

```
$ git log
commit f7251293fb195674212d1ffd5fc6ce3ab1ac316c (HEAD -> master)
Author: commit <huhuixin@huhuixindeAir.lan>
Date:   Tue Jul 3 01:36:37 2018 +0800

    modify2

commit 6926c5136ea36130850008e7913e39f8ad962934
Author: commit <huhuixin@huhuixindeAir.lan>
Date:   Tue Jul 3 01:29:23 2018 +0800

    modify

commit cf538a258a996a580bb50609a570c05cb1a67888 (origin/master, origin/HEAD)
Author: huixinhu <huixinhu@tencent.com>
Date:   Mon Jul 2 21:26:13 2018 +0800

    modify1

commit 504d245d9de97074fcdf5aa62fffaf2614836363
Author: huixinHu <305757732@qq.com>
Date:   Mon Jul 2 21:15:05 2018 +0800

    Update 123.txt
```
显示的从上往下是从最近到最远的日志，需要关注的是`commit xxxx`那一行。可以用`git log --pretty=oneline`来只输出这一行的信息。

`f7251293fb195674212d1ffd5fc6ce3ab1ac316c`、`6926c5136ea36130850008e7913e39f8ad962934`这些是用sha1计算出来的`commit id`(版本号)。

如果要回退到某一版本，可以`git reset --hard 版本号`。如果对此次回退后悔了，也可以使用同样的方法`git reset --hard 版本号`恢复。

## 二、分支管理

### 创建分支

`git branch 分支名`

### 切换分支

`git checkout 分支名`

创建并切换分支：`git checkout -b 分支名`

### 查看所有分支

`git branch`，输出结果会在当前分支前面标记一个`*`号。

### 合并分支

`git merge 分支名` 合并分支到**当前所在分支**

比如把`dev`分支的内容合并到`master`分支上：

```
git checkout master 确保先把当前分支切换到master
git merge dev
``` 

### 删除分支

`git branch -d 分支名` 合并分支后删除。

`git branch -D 分支名` 还没合并分支，要强行删除分支。

### bug分支

比如当前在`dev`分支上开发，同时有一个bug要修复，我要临时创建一个分支fix bug，但是`dev`上的代码我还不想提交。要怎么做呢？

1. 用`git stash`把当前分支的工作存储起来
2. 确定要在哪个分支修bug，比如在`master`上修复，那么把分支切换到`master`，然后从`master`另建一个临时分支。

 ```
 git checkout master
 git checkout -b tempBranch
 ```
 
3. 修复完bug，切换回`master`、合并，删除临时分支
4. 切换回`dev`分支，把之前存储的工作取出来继续完成：`git stash apply`回复，然后`git stash drop`删除stash内容；或者`git stash pop`恢复并删除。

### 解决冲突

比如当在不同的分支上修改了同一个文件就**有可能**产生冲突。当控制台提示产生冲突时，找到产生冲突的文件，可以看到git用`<<<<<<<`、`=======`、`>>>>>>>`标记出不同分支的内容。手动修改冲突之后，再进行一次`git add`和`git comiit`操作保存修改。

用`git status`可以查看冲突的文件，用`git log --graph`命令可以看到分支合并图。