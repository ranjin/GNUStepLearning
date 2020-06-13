/* Interface for NSURLConnection for GNUstep
   Copyright (C) 2006 Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <frm@gnu.org>
   Date: 2006
   
   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.
   */ 

#ifndef __NSURLConnection_h_GNUSTEP_BASE_INCLUDE
#define __NSURLConnection_h_GNUSTEP_BASE_INCLUDE
#import	<GNUstepBase/GSVersionMacros.h>

#if OS_API_VERSION(MAC_OS_X_VERSION_10_2,GS_API_LATEST) && GS_API_VERSION( 11300,GS_API_LATEST)

#import	<Foundation/NSObject.h>

#if	defined(__cplusplus)
extern "C" {
#endif

@class NSCachedURLResponse;
@class NSData;
@class NSError;
@class NSURLAuthenticationChallenge;
@class NSURLRequest;
@class NSURLResponse;

/**
 */
@interface NSURLConnection : NSObject
{
#if	GS_EXPOSE(NSURLConnection)
  void *_NSURLConnectionInternal;
#endif
}

/**
 * 进行一个初步的检查，看看指定的请求的负载是否可以被这个request的实例处理，这个方法的结果可能会因请求的后续更改或注册协议的更改而失效。
 * Performs a preliminary check to see if a load of the specified
 * request can be handled by an instance of this class.<br />
 * The results of this method may be invalidated by subsequent
 * changes to the request or changes to the registered protocols
 * etc.
 */
+ (BOOL) canHandleRequest: (NSURLRequest *)request;

/**
 * 分配并返回autorelease实例，它使用-initWithReuqest:delegate: 方法初始化该实例
 * Allocates and returns the autoreleased instance which it initialises
 * using the -initWithRequest:delegate: method.
 */
+ (NSURLConnection *) connectionWithRequest: (NSURLRequest *)request
				   delegate: (id)delegate;

/**
 * 取消这个连接中的异步加载
 * Cancel the asynchronous load in progress (if any) for this connection.
 */
- (void) cancel;

/** <init />
 * 用指定的请求初始化接收方并委托
 * Initialises the receiver with the specified request (performing
 * a deep copy so that the request does not change during loading)
 * and delegate.<br />
 *
 * 这将自动启动请求的异步加载
 * This automatically initiates an asynchronous load for the request.<br />
 *
 * 请求的处理是在调用此方法的线程中完成的，因此线程必须运行在当前的runloop中才能继续/完成处理。
 * Processing of the request is done in the thread which calls this
 * method, so the thread must run its current run loop
 * (in NSDefaultRunLoopMode) for processing to continue/complete.<br />
 *
 * 委托将收到回调，通知它加载的进度
 * The delegate will receive callbacks informing it of the progress
 * of the load.<br />
 *
 * 这个方法会保留delegate对象，并在连接完成加载、失败或取消时释放它。
 * This method breaks with convention and retains the delegate object,
 * releasing it when the connection finished loading, fails, or is cancelled.
 */
- (id) initWithRequest: (NSURLRequest *)request delegate: (id)delegate;

@end



/**
 * 这个category是一种非正式的协议，指定NSURLConnection实例如何与其委托进行通信，以通知委托(并允许委托管理)加载请求的进程。加载操作是由异步I/O使用启动它的线程的运行循环执行，因此所有回调都将在该线程中发生。
 *
 * This category is an informal protocol specifying how an NSURLConnection
 * instance will communicate with its delegate to inform it of (and allow
 * it to manage) the progress of a load request.<br />
 * A load operation is performed by asynchronous I/O using the
 * run loop of the thread in which it was initiated, so all callbacks
 * will occur in that thread.<br />
 *
 * 加载资源的过程如下所示：
 * The process of loading a resource occurs as follows -<br />
 * <list>
 *   <item>
 *     1. 任意数量的-connection:willSendRequest:redirectResponse:消息可以在发送此列表中的任何其它消息之前发送给委托。这允许在最终加载真实数据之前遵循一个重定向链
 *
 *     Any number of -connection:willSendRequest:redirectResponse:
 *     messages may be sent to the delegate before any other messages
 *     in this list are sent.  This permits a chain of redirects to
 *     be followed before eventual loading of 'real' data.
 *   </item>
 *   <item>
 *
 *     2. 一个didReceiveAuthenticationChallenge消息在相应数据可以下载之前可能会被发送给delegate(那里需要身份认证)
 *
 *     A -connection:didReceiveAuthenticationChallenge: message may be
 *     sent to the delegate (where authentication is required) before
 *     response data can be downloaded.
 *   </item>
 *   <item>
 *
 *     3. 任意数量的didReceiveResponse消息可以在didReceiveData消息之前发送给委托
 *     Any number of -connection:didReceiveResponse: messages
 *     may be be sent to the delegate before a
 *     -connection:didReceiveData: message.
 *
 *     通常只会有一个didReceiveResponse，但是对于multipart/x-mixed-replace，每个部分可能有多个响应，如果在下载中出现错误，委托可能根本没有收到响应。委托在收到新响应时应该丢弃以前处理过的数据。
 *     Usually there is exactly one
 *     of these, but for multipart/x-mixed-replace there may be multiple
 *     responses for each part, and if an error occurs in the download
 *     the delegate may not receive a response at all.<br />
 *     Delegates should discard previously handled data when they
 *     receive a new response.
 *   </item>
 *   <item>
 *     任意数量的didReceiveData消息可以在加载完成之前发送。
 *     Any number of -connection:didReceiveData: messages may
 *     be sent before the load completes as described below.
 *   </item>
 *   <item>
 *     一个单独的willCacheResponse消息可以在任何didReceiveData消息被发送但在connectionDidFinishLoading消息被发送之前发送给委托
 *     A single -connection:willCacheResponse: message may
 *     be sent to the delegate after any -connection:didReceiveData:
 *     messages are sent but before a -connectionDidFinishLoading: message
 *     is sent.
 *   </item>
 *   <item>
 *     除非NSURLConnection收到一个-cancel消息，否则委托将只会收到一个-connectionDidFinishLoading或didFailWithError，但不会同时收到。
 *     Unless the NSURLConnection receives a -cancel message,
 *     the delegate will receive one and only one of
 *     -connectionDidFinishLoading:, or
 *     -connection:didFailWithError: message, but never
 *     both.<br />
 *
 *
 *     一旦发送了这些终端信息中的任何一条，delegae将不再接收来自NSURLConnection的消息
 *     Once either of these terminal messages is sent the
 *     delegate will receive no further messages from the 
 *     NSURLConnection.
 *   </item>
 * </list>
 */
#if OS_API_VERSION(MAC_OS_X_VERSION_10_7,GS_API_LATEST) && GS_API_VERSION(11300,GS_API_LATEST)
@protocol NSURLConnectionDelegate <NSObject>

#if GS_PROTOCOLS_HAVE_OPTIONAL
@optional
#else
@end
@interface NSObject (NSURLConnectionDelegate)
#endif

#else
@interface NSObject (NSURLConnectionDelegate)
#endif

/**
 * Instructs the delegate that authentication for challenge has
 * been cancelled for the request loading on connection.
 */
- (void) connection: (NSURLConnection *)connection
  didCancelAuthenticationChallenge: (NSURLAuthenticationChallenge *)challenge;

/*
 * Called when an NSURLConnection has failed to load successfully.
 */
- (void) connection: (NSURLConnection *)connection
   didFailWithError: (NSError *)error;

/**
 * Called when an NSURLConnection has finished loading successfully.
 */
- (void) connectionDidFinishLoading: (NSURLConnection *)connection;

/**
 * Called when an authentication challenge is received ... the delegate
 * should send -useCredential:forAuthenticationChallenge: or
 * -continueWithoutCredentialForAuthenticationChallenge: or
 * -cancelAuthenticationChallenge: to the challenge sender when done.
 */
- (void) connection: (NSURLConnection *)connection
  didReceiveAuthenticationChallenge: (NSURLAuthenticationChallenge *)challenge;

/**
 * Called when content data arrives during a load operations ... this
 * may be incremental or may be the compolete data for the load.
 */
- (void) connection: (NSURLConnection *)connection
     didReceiveData: (NSData *)data;

/**
 * Called when enough information to build a NSURLResponse object has
 * been received.
 */
- (void) connection: (NSURLConnection *)connection
 didReceiveResponse: (NSURLResponse *)response;

/**
 * Called with the cachedResponse to be stored in the cache.
 * The delegate can inspect the cachedResponse and return a modified
 * copy if if wants changed to what whill be stored.<br />
 * If it returns nil, nothing will be stored in the cache.
 */
- (NSCachedURLResponse *) connection: (NSURLConnection *)connection
  willCacheResponse: (NSCachedURLResponse *)cachedResponse;

/**
 * Informs the delegate that the connection must change the URL of
 * the request in order to continue with the load operation.<br />
 * This allows the delegate to ionspect and/or modify a copy of the request
 * before the connection continues loading it.  Normally the delegate
 * can return the request unmodifield.<br />
 * The redirection can be rejectected by the delegate calling -cancel
 * or returning nil.<br />
 * Cancelling the load will simply stop it, but returning nil will
 * cause it to complete with a redirection failure.<br />
 * As a special case, this method may be called with a nil response,
 * indicating a change of URL made internally by the system rather than
 * due to a response from the server.
 */
- (NSURLRequest *) connection: (NSURLConnection *)connection
	      willSendRequest: (NSURLRequest *)request
	     redirectResponse: (NSURLResponse *)response;
@end

/**
 * An interface to perform synchronous loading of URL requests.
 */
@interface NSURLConnection (NSURLConnectionSynchronousLoading)

/**
 * Performs a synchronous load of request and returns the
 * [NSURLResponse] in response.<br />
 * Returns the result of the load or nil if the load failed.
 */
+ (NSData *) sendSynchronousRequest: (NSURLRequest *)request
		  returningResponse: (NSURLResponse **)response
			      error: (NSError **)error;

@end

#if	defined(__cplusplus)
}
#endif

#endif

#endif
