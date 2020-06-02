#######  1. 如果在异步线程发送通知，如果保证在主线程响应通知？
```
1. 使用addObserverForName方法注册通知，指定在mainqueue上响应block。
2. 在主线程注册一个machPort，它是用来做线程通知的，当在异步线程收到通知，然后给machPort发送消息，这样肯定是在主线程处理的。
```
#######  2. 通知的发送是同步的，还是异步的 ?
```
通知的发送核心函数是postNotificationName，最后进到_postAndRelease进行发送操作，调用performSelector执行响应方法，是同步的。
```
#######  3. 下面的方式能接收到通知吗、为什么？
```
// 发送通知
[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNotification:) name:@"TestNotification" object:@1];

// 接收通知
[NSNotificationCenter.defaultCenter postNotificationName:@"TestNotification" object:nil];

---
不会收到通知，我们知道，存储是以name和object为维度的，如果这两个都一样则认为是同一个通知。可以再回顾下addObserve的三种类型过程。
```
####### 3. NSNotificationCenter接收消息和发送消息是在一个线程里吗？如何异步发送消息
```
引用苹果官方的阐述：在多线程应用程序中，通知总是在发布通知的线程中传递，而这个线程可能与观察者注册自己的线程不同。

```
####### 4. 如果我们希望在一个Notification的post线程与转发线程不是同一线程，应该怎么办？
```
在这种情况下，必须捕获在默认线程上传递的通知，并将它们重定向到合适的线程。
NSNotificationCenter是线程安全的。
```
####### 5. NSNotificationQueue是异步还是同步发送？在哪个线程响应
```
都可以。指定要发送的队列，哪个线程发送，哪个线程响应呗。
```

####### 6. NSNotificationQueue和runloop的关系
```
NSNotificationQueue是依赖于runloop的。如果需要在子线程使用NSNotificationQueue，则需要手动开启runloop。
把需要发送的通知添加到队列，等待发送。这里默认的mode是NSDefaultRunLoopMode。
在发送通知的时候需要指定发送时机，如果是Idle值，则表明需要等runloop空闲的时候。
```

####### 7. 如何保证通知接收的线程在主线程
```
我们知道线程的发送和接收在同一个线程，所以如果子线程post，那么主线程是接收不到的。
方法：
1. 在响应函数处强制切换线程，切换到主线程
- (void)handleNotification:(NSNotification *)notification {
   dispatch_async(dispatch_get_main_queue(), ^{
      NSLog(@"current thread = %@", [NSThread currentThread]);
   });
}
2. 线程重定向：使用一个通知队列(NSNotificationQueue)去记录需要实现的通知，然后将它们重定向到预期线程(主线程)。

3. 使用方法：
- (id<NSObject>)addObserverForName:(NSString *)name
    object:(id)obj
     queue:(NSOperationQueue *)queue
usingBlock:(void (^)(NSNotification *note))block
回调方法里把block抛给指定的queue去执行。

参考：https://segmentfault.com/a/1190000005889055
```

####### 7. 页面销毁时不移除通知会崩溃吗
```
iOS 9.0之后不需要手动移除，因为NSNotificationCenter没有对对象做retain处理。
通过addObserverForName:object:queue:usingBlock方法添加的通知，都需要手动移除，不然会产生内存泄漏。
```
####### 8. 多次添加同一个通知会是什么结果？多次移除通知呢
```
多次添加同一个通知，根据方法addObserver里面的，我们是可以为一个通知注册多个观察者的，这种情况下，发送通知时观察者将收到多个消息。因为addObserve方法里面是没有去重操作的。

多次移除通知也不会crash，多次remove之后，如果观察者为nil，其效果是删除指定通知的所有注册表。
```
```
2. 实现原理（结构设计、通知如何存储的、name & observer & SEL之间的关系等）
```
