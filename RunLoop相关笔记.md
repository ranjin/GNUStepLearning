####### 1. app如何接收到触摸事件的？
```
苹果注册了一个source1用来接收系统事件，对应的有一个queueCallback()的回调函数。
当一个触摸事件发生后，首先由IOKit.framework生成一个IOHIDEvent事件并由SpringBoard接收。随后用mach port转发给需要的App进程。随后苹果注册的source1就会触发回调，并调用_UIApplicationHandleEventQueue()进行应用内部的分发。

这个函数将Event事件最终转化成UIEvent事件进行处理，这其中就包括了我们的点击触摸事件等。
```

####### 为什么只有主线程的runloop是开启的，或者说为什么子线程的runloop需要手动开启？
```
我们知道，runloop和线程是一一对应的，它们的关系保存在一个全局的dic里面。key是pthread_t,value是CFRunLoopRef。通过源码我们知道，在进入runloop的时候，我们会先判断这个dic存不存在，如果不存在则会新建一个全局变量，同时创建一个主线程对应的runloop，然后保存主线程。
如果当前的线程没有runloop，会使用懒加载的方式创建一个runloop，并保存到全局的dic里。
```
####### 为什么只在主线程刷新UI
```
UIKit并不是一个线程安全的类，UI操作涉及到渲染访问各种view对象的属性，在异步操作下会存在读写问题，而为其枷锁则会耗费大量资源并拖慢运行速度。
另一方面因为整个程序的起点UIApplication是在主线程进行初始化的，所有的用户事件都是在主线程中进行传递，所以view只能在主线程上才能对事件进行响应。
渲染方面，由于图像的渲染需要以60帧的刷新率在屏幕上同时更新，在大多异步情况下无法确定这个处理过程能否实现同步更新。

那跟runloop又有啥关系了？UIApplication在主线程所初始化的runloop我们称为main runloop。它负责处理app存活期间的大部分事件。它一直处于不断处理事件和休眠的循环之中，以确保能尽快的将用户事件传递给GPU进行渲染。
```

###### PerformSelector和runloop的关系
```
不知道要考察的知识点是不是这个。
使用performSelector：afterDelay函数时，这个afterDelay其实就相当于添加了一个NSTimer，如果是在子线程里面，定时器是不会自动被加入到指定的runloop里面的，需要手动加入。不然是不会执行这个方法的。
```

####### 如何使线程保活
```
其实就是如何开启一个常驻线程吧。
1. 添加一条用于常驻内存的强引用的子线程，在该线程的runloop下添加一个sources，开启线程。
@property (nonatomic, strong) NSThread *thread;

2. 在viewdidload里面创建线程，使线程启动并执行run方法。

- (void)viewDidLoad{
[super viewDidLoad];
self.thread = [[NSThread alloc] initwithTarget:self selector:@selector(run1) object:nil]
//开启线程
}

- (void)run1{
    [[NSRunLoop currentRunLoop] addPort:[NSPort port] forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] run];
}
```
