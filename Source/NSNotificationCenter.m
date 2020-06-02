/** Implementation of NSNotificationCenter for GNUstep
   Copyright (C) 1999 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Created: June 1999

   Many thanks for the earlier version, (from which this is loosely
   derived) by  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Created: March 1996

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

   <title>NSNotificationCenter class reference</title>
   $Date$ $Revision$
*/

/**
 单例类，负责管理通知的创建和发送。主要负责三件事：
 1. 添加通知
 2. 发送通知
 3. 移除通知
 */

#import "common.h"
#define	EXPOSE_NSNotificationCenter_IVARS	1
#import "Foundation/NSNotification.h"
#import "Foundation/NSDictionary.h"
#import "Foundation/NSException.h"
#import "Foundation/NSLock.h"
#import "Foundation/NSOperation.h"
#import "Foundation/NSThread.h"
#import "GNUstepBase/GSLock.h"

static NSZone	*_zone = 0;

/**
 * Concrete class implementing NSNotification.
 */
@interface	GSNotification : NSNotification
{
@public
  NSString	*_name;
  id		_object;
  NSDictionary	*_info;
}
@end

@implementation GSNotification

static Class concrete = 0;

+ (void) initialize
{
  if (concrete == 0)
    {
      concrete = [GSNotification class];
    }
}

+ (NSNotification*) notificationWithName: (NSString*)name
				  object: (id)object
			        userInfo: (NSDictionary*)info
{
  GSNotification	*n;

  n = (GSNotification*)NSAllocateObject(self, 0, NSDefaultMallocZone());
  n->_name = [name copyWithZone: [self zone]];
  n->_object = TEST_RETAIN(object);
  n->_info = TEST_RETAIN(info);
  return AUTORELEASE(n);
}

- (id) copyWithZone: (NSZone*)zone
{
  GSNotification	*n;

  if (NSShouldRetainWithZone (self, zone))
    {
      return [self retain];
    }
  n = (GSNotification*)NSAllocateObject(concrete, 0, zone);
  n->_name = [_name copyWithZone: [self zone]];
  n->_object = TEST_RETAIN(_object);
  n->_info = TEST_RETAIN(_info);
  return n;
}

- (void) dealloc
{
  RELEASE(_name);
  TEST_RELEASE(_object);
  TEST_RELEASE(_info);
  [super dealloc];
}

- (NSString*) name
{
  return _name;
}

- (id) object
{
  return _object;
}

- (NSDictionary*) userInfo
{
  return _info;
}

@end


/*
 * Garbage collection considerations -
 * The notification center is not supposed to retain any notification
 * observers or notification objects.  To achieve this when using garbage
 * collection, we must hide all references to observers and objects.
 * Within an Observation structure, this is not a problem, we simply
 * allocate the structure using 'atomic' allocation to tell the gc
 * system to ignore pointers inside it.
 * Elsewhere, we store the pointers with a bit added, to hide them from
 * the garbage collector.
 */

struct	NCTbl;		/* Notification Center Table structure	*/

/*
 * Observation structure - One of these objects is created for
 * each -addObserver... request.  It holds the requested selector,
 * name and object.  Each struct is placed in one LinkedList,
 * as keyed by the NAME/OBJECT parameters.
 * If 'next' is 0 then the observation is unused (ie it has been
 * removed from, or not yet added to  any list).  The end of a
 * list is marked by 'next' being set to 'ENDOBS'.
 *
 * This is normally a structure which handles memory management using a fast
 * reference count mechanism, but when built with clang for GC, a structure
 * can't hold a zeroing weak pointer to an observer so it's implemented as a
 * trivial class instead ... and gets managed by the garbage collector.
 */

//Observation 存储观察者和响应结构体，基本的存储单元。
typedef	struct	Obs {
    //观察者，接受通知的对象
  id		observer;	/* Object to receive message.	*/
    //响应方法
  SEL		selector;	/* Method selector.		*/
    //链表中指向的下一个元素
  struct Obs	*next;		/* Next item in linked list.	*/
  int		retained;	/* Retain count for structure.	*/
  struct NCTbl	*link;		/* Pointer back to chunk table	*/
} Observation;

#define	ENDOBS	((Observation*)-1)

static inline NSUInteger doHash(BOOL shouldHash, NSString* key)
{
  if (key == nil)
    {
      return 0;
    }
  else if (NO == shouldHash)
    {
      return (NSUInteger)(uintptr_t)key;
    }
  else
    {
      return [key hash];
    }
}

static inline BOOL doEqual(BOOL shouldHash, NSString* key1, NSString* key2)
{
  if (key1 == key2)
    {
      return YES;
    }
  else if (NO == shouldHash)
    {
      return NO;
    }
  else
    {
      return [key1 isEqualToString: key2];
    }
}

/*
 * Setup for inline operation on arrays of Observers.
 */
static void listFree(Observation *list);

/* Observations have retain/release counts managed explicitly by fast
 * function calls.
 */
static void obsRetain(Observation *o);
static void obsFree(Observation *o);


#define GSI_ARRAY_TYPES	0
#define GSI_ARRAY_TYPE	Observation*
#define GSI_ARRAY_RELEASE(A, X)   obsFree(X.ext)
#define GSI_ARRAY_RETAIN(A, X)    obsRetain(X.ext)

#include "GNUstepBase/GSIArray.h"

#define GSI_MAP_RETAIN_KEY(M, X)
#define GSI_MAP_RELEASE_KEY(M, X) ({if (YES == M->extra) RELEASE(X.obj);})
#define GSI_MAP_HASH(M, X)        doHash(M->extra, X.obj)
#define GSI_MAP_EQUAL(M, X,Y)     doEqual(M->extra, X.obj, Y.obj)
#define GSI_MAP_RETAIN_VAL(M, X)
#define GSI_MAP_RELEASE_VAL(M, X)

#define GSI_MAP_KTYPES GSUNION_OBJ|GSUNION_NSINT
#define GSI_MAP_VTYPES GSUNION_PTR
#define GSI_MAP_VEXTRA Observation*
#define	GSI_MAP_EXTRA	BOOL

#include "GNUstepBase/GSIMap.h"

/**
 NC表用来跟踪分配给存储观察结构体的内存。
 当一个观察从通知中心移除时，它的内存返回到chunk表的空闲表。而不是释放到一般的内存分配系统。
 这意味着，一旦注册了大量的观察者，即使删除了观察者，内存使用也不会减少。另一方面，增加和删除观察者的进程加快了。
 
 作为对性能的一个小帮助，还维护了用于将通知对象映射到观察列表的映射表的缓存。
 这使我们避免了在频繁添加和删除通知观察者时创建和销毁映射表的开销。
 
 性能并不是使用这个结构的真正原因，它提供了一种简洁的方式来确保观察结构所指向的观察者不会被GC机制视为正在使用的。
 */
/*
 * An NC table is used to keep track of memory allocated to store
 * Observation structures. When an Observation is removed from the
 * notification center, it's memory is returned to the free list of
 * the chunk table, rather than being released to the general
 * memory allocation system.  This means that, once a large numbner
 * of observers have been registered, memory usage will never shrink
 * even if the observers are removed.  On the other hand, the process
 * of adding and removing observers is speeded up.
 *
 * As another minor aid to performance, we also maintain a cache of
 * the map tables used to keep mappings of notification objects to
 * lists of Observations.  This lets us avoid the overhead of creating
 * and destroying map tables when we are frequently adding and removing
 * notification observations.
 *
 * Performance is however, not the primary reason for using this
 * structure - it provides a neat way to ensure that observers pointed
 * to by the Observation structures are not seen as being in use by
 * the garbage collection mechanism.
 */
#define	CHUNKSIZE	128
#define	CACHESIZE	16
typedef struct NCTbl {
    //wildcard：链表结构，保存既没有name也没有object的通知
  Observation		*wildcard;	/* Get ALL messages.		*/
    
    //存储没有name但是有object的通知
  GSIMapTable		nameless;	/* Get messages for any name.	*/
    
    //存储带有name的通知，不管有没有object
  GSIMapTable		named;		/* Getting named messages only.	*/
  unsigned		lockCount;	/* Count recursive operations.	*/
  NSRecursiveLock	*_lock;		/* Lock out other threads.	*/
  Observation		*freeList;
  Observation		**chunks;
  unsigned		numChunks;
  GSIMapTable		cache[CACHESIZE];
  unsigned short	chunkIndex;
  unsigned short	cacheIndex;
} NCTable;

#define	TABLE		((NCTable*)_table)
#define	WILDCARD	(TABLE->wildcard)
#define	NAMELESS	(TABLE->nameless)
#define	NAMED		(TABLE->named)
#define	LOCKCOUNT	(TABLE->lockCount)

static Observation *
obsNew(NCTable *t, SEL s, id o)
{
  Observation	*obs;

  /* Generally, observations are cached and we create a 'new' observation
   * by retrieving from the cache or by allocating a block of observations
   * in one go.  This works nicely to both hide observations from the
   * garbage collector (when using gcc for GC) and to provide high
   * performance for situations where apps add/remove lots of observers
   * very frequently (poor design, but something which happens in the
   * real world unfortunately).
   */
  if (t->freeList == 0)
    {
      Observation	*block;

      if (t->chunkIndex == CHUNKSIZE)
	{
	  unsigned	size;

	  t->numChunks++;

	  size = t->numChunks * sizeof(Observation*);
	  t->chunks = (Observation**)NSReallocateCollectable(
	    t->chunks, size, NSScannedOption);

	  size = CHUNKSIZE * sizeof(Observation);
	  t->chunks[t->numChunks - 1]
	    = (Observation*)NSAllocateCollectable(size, 0);
	  t->chunkIndex = 0;
	}
      block = t->chunks[t->numChunks - 1];
      t->freeList = &block[t->chunkIndex];
      t->chunkIndex++;
      t->freeList->link = 0;
    }
  obs = t->freeList;
  t->freeList = (Observation*)obs->link;
  obs->link = (void*)t;
  obs->retained = 0;
  obs->next = 0;

  obs->selector = s;
  obs->observer = o;

  return obs;
}

static GSIMapTable	mapNew(NCTable *t)
{
  if (t->cacheIndex > 0)
    {
      return t->cache[--t->cacheIndex];
    }
  else
    {
      GSIMapTable	m;

      m = NSAllocateCollectable(sizeof(GSIMapTable_t), NSScannedOption);
      GSIMapInitWithZoneAndCapacity(m, _zone, 2);
      return m;
    }
}

static void	mapFree(NCTable *t, GSIMapTable m)
{
  if (t->cacheIndex < CACHESIZE)
    {
      t->cache[t->cacheIndex++] = m;
    }
  else
    {
      GSIMapEmptyMap(m);
      NSZoneFree(NSDefaultMallocZone(), (void*)m);
    }
}

static void endNCTable(NCTable *t)
{
  unsigned		i;
  GSIMapEnumerator_t	e0;
  GSIMapNode		n0;
  Observation		*l;

  TEST_RELEASE(t->_lock);

  /*
   * Free observations without notification names or numbers.
   */
  listFree(t->wildcard);

  /*
   * Free lists of observations without notification names.
   */
  e0 = GSIMapEnumeratorForMap(t->nameless);
  n0 = GSIMapEnumeratorNextNode(&e0);
  while (n0 != 0)
    {
      l = (Observation*)n0->value.ptr;
      n0 = GSIMapEnumeratorNextNode(&e0);
      listFree(l);
    }
  GSIMapEmptyMap(t->nameless);
  NSZoneFree(NSDefaultMallocZone(), (void*)t->nameless);

  /*
   * Free lists of observations keyed by name and observer.
   */
  e0 = GSIMapEnumeratorForMap(t->named);
  n0 = GSIMapEnumeratorNextNode(&e0);
  while (n0 != 0)
    {
      GSIMapTable		m = (GSIMapTable)n0->value.ptr;
      GSIMapEnumerator_t	e1 = GSIMapEnumeratorForMap(m);
      GSIMapNode		n1 = GSIMapEnumeratorNextNode(&e1);

      n0 = GSIMapEnumeratorNextNode(&e0);

      while (n1 != 0)
	{
	  l = (Observation*)n1->value.ptr;
	  n1 = GSIMapEnumeratorNextNode(&e1);
	  listFree(l);
	}
      GSIMapEmptyMap(m);
      NSZoneFree(NSDefaultMallocZone(), (void*)m);
    }
  GSIMapEmptyMap(t->named);
  NSZoneFree(NSDefaultMallocZone(), (void*)t->named);

  for (i = 0; i < t->numChunks; i++)
    {
      NSZoneFree(NSDefaultMallocZone(), t->chunks[i]);
    }
  for (i = 0; i < t->cacheIndex; i++)
    {
      GSIMapEmptyMap(t->cache[i]);
      NSZoneFree(NSDefaultMallocZone(), (void*)t->cache[i]);
    }
  NSZoneFree(NSDefaultMallocZone(), t->chunks);
  NSZoneFree(NSDefaultMallocZone(), t);
}

static NCTable *newNCTable(void)
{
  NCTable	*t;

  t = (NCTable*)NSAllocateCollectable(sizeof(NCTable), NSScannedOption);
  t->chunkIndex = CHUNKSIZE;
  t->wildcard = ENDOBS;

  t->nameless = NSAllocateCollectable(sizeof(GSIMapTable_t), NSScannedOption);
  t->named = NSAllocateCollectable(sizeof(GSIMapTable_t), NSScannedOption);
  GSIMapInitWithZoneAndCapacity(t->nameless, _zone, 16);
  GSIMapInitWithZoneAndCapacity(t->named, _zone, 128);
  t->named->extra = YES;        // This table retains keys

  t->_lock = [NSRecursiveLock new];
  return t;
}

static inline void lockNCTable(NCTable* t)
{
  [t->_lock lock];
  t->lockCount++;
}

static inline void unlockNCTable(NCTable* t)
{
  t->lockCount--;
  [t->_lock unlock];
}

static void obsFree(Observation *o)
{
  NSCAssert(o->retained >= 0, NSInternalInconsistencyException);
  if (o->retained-- == 0)
    {
      NCTable	*t = o->link;

      o->link = (NCTable*)t->freeList;
      t->freeList = o;
    }
}

static void obsRetain(Observation *o)
{
  o->retained++;
}

static void listFree(Observation *list)
{
  while (list != ENDOBS)
    {
      Observation	*o = list;

      list = o->next;
      o->next = 0;
      obsFree(o);
    }
}

/*
 *	NB. We need to explicitly set the 'next' field of any observation
 *	we remove to be zero so that, if it currently exists in an array
 *	of observations being posted, the posting code can notice that it
 *	has been removed from its linked list.
 *
 *	Also, 
 */
static Observation *listPurge(Observation *list, id observer)
{
  Observation	*tmp;

  while (list != ENDOBS && list->observer == observer)
    {
      tmp = list->next;
      list->next = 0;
      obsFree(list);
      list = tmp;
    }
  if (list != ENDOBS)
    {
      tmp = list;
      while (tmp->next != ENDOBS)
	{
	  if (tmp->next->observer == observer)
	    {
	      Observation	*next = tmp->next;

	      tmp->next = next->next;
	      next->next = 0;
	      obsFree(next);
	    }
	  else
	    {
	      tmp = tmp->next;
	    }
	}
    }
  return list;
}

/*
 * Utility function to remove all the observations from a particular
 * map table node that match the specified observer.  If the observer
 * is nil, then all observations are removed.
 * If the list of observations in the map node is emptied, the node is
 * removed from the map.
 */
static inline void
purgeMapNode(GSIMapTable map, GSIMapNode node, id observer)
{
  Observation	*list = node->value.ext;

  if (observer == 0)
    {
      listFree(list);
      GSIMapRemoveKey(map, node->key);
    }
  else
    {
      Observation	*start = list;

      list = listPurge(list, observer);
      if (list == ENDOBS)
	{
	  /*
	   * The list is empty so remove from map.
	   */
	  GSIMapRemoveKey(map, node->key);
	}
      else if (list != start)
	{
	  /*
	   * The list is not empty, but we have changed its
	   * start, so we must place the new head in the map.
	   */
	  node->value.ext = list;
	}
    }
}

/* purgeCollected() returns a list of observations with any observations for
 * a collected observer removed.
 * purgeCollectedFromMapNode() does the same thing but also handles cleanup
 * of the map node containing the list if necessary.
 */
#define	purgeCollected(X)	(X)
#define purgeCollectedFromMapNode(X, Y) ((Observation*)Y->value.ext)


@interface GSNotificationBlockOperation : NSOperation
{
	NSNotification *_notification;
	GSNotificationBlock _block;
}

- (id) initWithNotification: (NSNotification *)notif 
                      block: (GSNotificationBlock)block;

@end

@implementation GSNotificationBlockOperation

- (id) initWithNotification: (NSNotification *)notif 
                      block: (GSNotificationBlock)block
{
	self = [super init];
	if (self == nil)
		return nil;

	ASSIGN(_notification, notif);
	_block = Block_copy(block);
	return self;

}

- (void) dealloc
{
	DESTROY(_notification);
	Block_release(_block);
	[super dealloc];
}

- (void) main
{
	CALL_BLOCK(_block, _notification);
}

@end

//作用是代理观察者，主要用来实现接口：
@interface GSNotificationObserver : NSObject
{
	NSOperationQueue *_queue;
	GSNotificationBlock _block;
}

@end

@implementation GSNotificationObserver

- (id) initWithQueue: (NSOperationQueue *)queue 
               block: (GSNotificationBlock)block
{
	self = [super init];
	if (self == nil)
		return nil;

	ASSIGN(_queue, queue);
	_block = Block_copy(block);
	return self;
}

- (void) dealloc
{
	DESTROY(_queue);
	Block_release(_block);
	[super dealloc];
}

//响应接受通知的方法，并在指定队列中执行block。
- (void) didReceiveNotification: (NSNotification *)notif
{
	if (_queue != nil)
	{
		GSNotificationBlockOperation *op = [[GSNotificationBlockOperation alloc] 
			initWithNotification: notif block: _block];

		[_queue addOperation: op];
	}
	else
	{
		CALL_BLOCK(_block, notif);
	}
}

@end


/**
 * <p>GNUstep provides a framework for sending messages between objects within
 * a process called <em>notifications</em>.  Objects register with an
 * <code>NSNotificationCenter</code> to be informed whenever other objects
 * post [NSNotification]s to it matching certain criteria. The notification
 * center processes notifications synchronously -- that is, control is only
 * returned to the notification poster once every recipient of the
 * notification has received it and processed it.  Asynchronous processing is
 * possible using an [NSNotificationQueue].</p>
 *
 * <p>Obtain an instance using the +defaultCenter method.</p>
 *
 * <p>In a multithreaded process, notifications are always sent on the thread
 * that they are posted from.</p>
 *
 * <p>Use the [NSDistributedNotificationCenter] for interprocess
 * communications on the same machine.</p>
 */
@implementation NSNotificationCenter

/* The default instance, most often the only one created.
   It is accessed by the class methods at the end of this file.
   There is no need to mutex locking of this variable. */

static NSNotificationCenter *default_center = nil;

+ (void) atExit
{
  id	tmp = default_center;

  default_center = nil;
  [tmp release];
}

+ (void) initialize
{
  if (self == [NSNotificationCenter class])
    {
      _zone = NSDefaultMallocZone();
      if (concrete == 0)
	{
	  concrete = [GSNotification class];
	}
      /*
       * Do alloc and init separately so the default center can refer to
       * the 'default_center' variable during initialisation.
       */
      default_center = [self alloc];
      [default_center init];
      [self registerAtExit];
    }
}

/**
 * Returns the default notification center being used for this task (process).
 * This is used for all notifications posted by the Base library unless
 * otherwise noted.
 */
+ (NSNotificationCenter*) defaultCenter
{
  return default_center;
}


/* Initializing. */

- (id) init
{
  if ((self = [super init]) != nil)
    {
      _table = newNCTable();
    }
  return self;
}

- (void) dealloc
{
  [self finalize];

  [super dealloc];
}

- (void) finalize
{
  if (self == default_center)
    {
      [NSException raise: NSInternalInconsistencyException
		  format: @"Attempt to destroy the default center"];
    }
  /*
   * Release all memory used to store Observations etc.
   */
  endNCTable(TABLE);
}


/* Adding new observers. */

/**
 * <p>Registers observer to receive notifications with the name
 * notificationName and/or containing object (one or both of these two must be
 * non-nil; nil acts like a wildcard).  When a notification of name name
 * containing object is posted, observer receives a selector message with this
 * notification as the argument.
 * 通知中心等待这个观察者先完成当前的消息处理，然后通知下一个与通知相符的注册者，当所有的处理完毕之后，控制权回到了消息发送者手里。因此在方法实现的处理过程中应该是很短的。
 * The notification center waits for the
 * observer to finish processing the message, then informs the next registree
 * matching the notification, and after all of this is done, control returns
 * to the poster of the notification.  Therefore the processing in the
 * selector implementation should be short.</p>
 *
 * <p>The notification center does not retain observer or object. Therefore,
 * you should always send removeObserver: or removeObserver:name:object: to
 * the notification center before releasing these objects.<br />
 * 通知中心不会保留观察者或对象。因此在释放这些对象之前，应该始终将removeObserve发送到通知中心。
 * 为了方便起见，在使用GC时，不需要删除任何GC的观察者，因为系统将隐式的删除它。
 * As a convenience, when built with garbage collection, you do not need to
 * remove any garbage collected observer as the system will do it implicitly.
 * </p>
 *
 * <p>NB. For MacOS-X compatibility, adding an observer multiple times will
 * register it to receive multiple copies of any matching notification, however
 * removing an observer will remove <em>all</em> of the multiple registrations.
 * </p>
 */
//添加观察者
- (void) addObserver: (id)observer
	    selector: (SEL)selector
                name: (NSString*)name
	      object: (id)object
{
  Observation	*list;
  Observation	*o;
  GSIMapTable	m;
  GSIMapNode	n;

    //前置条件判断
  if (observer == nil)
    [NSException raise: NSInvalidArgumentException
		format: @"Nil observer passed to addObserver ..."];

  if (selector == 0)
    [NSException raise: NSInvalidArgumentException
		format: @"Null selector passed to addObserver ..."];

  if ([observer respondsToSelector: selector] == NO)
    {
      [NSException raise: NSInvalidArgumentException
        format: @"[%@-%@] Observer '%@' does not respond to selector '%@'",
        NSStringFromClass([self class]), NSStringFromSelector(_cmd),
        observer, NSStringFromSelector(selector)];
    }

    //锁住
  lockNCTable(TABLE);

    //创建一个observation对象，持有观察者和SEL，下面进行的所有逻辑就是为了存储它。
  o = obsNew(TABLE, selector, observer);

  /*
   * Record the Observation in one of the linked lists.
   *
   * NB. It is possible to register an observer for a notification more than
   * once - in which case, the observer will receive multiple messages when
   * the notification is posted... odd, but the MacOS-X docs specify this.
   */

    /**
     将观察结果记录在一个链表中。
     注意：我们可以为一个通知注册多个观察者，这种情况下，发送通知时观察者将收到多个消息。
     */
    /**
     总结：
     1. 如果通知的name存在，则以name为key，在named字典里取出值n（也是个字典）。
     2. 然后以object（方法参数）为key，从字典n里面取出对应的值，这个值就是Observation类型的b链表，然后把刚开始创建的obs对象o存储进去。
     */
#pragma mark -- name不为空，object不确定

  if (name)
    {
      /*
       * 定位此名称的映射表，如果不存在则创建它
       * Locate the map table for this name - create it if not present.
       */
        //NAMED是个宏，表示名为named字典。以name为key，从named表中获取对应的mapTable
      n = GSIMapNodeForKey(NAMED, (GSIMapKey)(id)name);
      if (n == 0)   //不存在，则创建
	{
	  m = mapNew(TABLE);    //先取缓存，如果缓存没有则新建一个map
	  /*
       * 因为这是对给定名称的第一次观察，所以我们获取名称的一个副本，这样在映射中它就不会发生变化。
	   * As this is the first observation for the given name, we take a
	   * copy of the name so it cannot be mutated while in the map.
	   */
	  name = [name copyWithZone: NSDefaultMallocZone()];
	  GSIMapAddPair(NAMED, (GSIMapKey)(id)name, (GSIMapVal)(void*)m);
	  GS_CONSUMED(name)
	}
      else
	{   //存在则把值取出来，赋值给m
	  m = (GSIMapTable)n->value.ptr;
	}

      /*
       * 将观察结果添加到正确对象的列表中
       * Add the observation to the list for the correct object.
       */
      n = GSIMapNodeForSimpleKey(m, (GSIMapKey)object);
      if (n == 0)
	{
	  o->next = ENDOBS;
	  GSIMapAddPair(m, (GSIMapKey)object, (GSIMapVal)o);
	}
      else
	{
	  list = (Observation*)n->value.ptr;
	  o->next = list->next;
	  list->next = o;
	}
    }
#pragma mark -- name为空，object不为空
    //如果name为空，object不为空
    /**
     总结：
     1. 以object为key，从nameless字典中取出value，此value是个obs类型的链表
     2. 把创建的obs类型的对象o存储到链表中
     只存在object时存储只有一层，那就是object和obs对象之间的映射
     */
  else if (object)
    {
    
      //以object为key，从nameless字典中取出对应的value，value是个链表结构
      n = GSIMapNodeForSimpleKey(NAMELESS, (GSIMapKey)object);
      if (n == 0)
          //不存在则新建链表，并存到map中
	{
	  o->next = ENDOBS;
	  GSIMapAddPair(NAMELESS, (GSIMapKey)object, (GSIMapVal)o);
	}
      else
	{
        //存在，则把值接到链表的节点上
	  list = (Observation*)n->value.ptr;
	  o->next = list->next;
	  list->next = o;
	}
    }
    /**
     没有name和object的情况：直接把obs对象存放在了wildcard链表结构中
     */
#pragma mark -- name与object都为空
  else
      //name和object都为空，则存储到wildcard链表中
    {
      o->next = WILDCARD;
      WILDCARD = o;
    }

  unlockNCTable(TABLE);
}

/**
 * 返回一个添加到通知中心的观察者。
 * <p>Returns a new observer added to the notification center, in order to 
 * observe the given notification name posted by an object or any object (if 
 * the object argument is nil).</p>
 *
 * <p>For the name and object arguments, the constraints and behavior described 
 * in -addObserver:name:selector:object: remain valid.</p>
 *
 * 对于在消息中心收到的每个通知，观察者都将执行通知块，如果队列不为nil，则通知块被包在NSOperation中并在队列中调度，否则这个块会在发布线程中立即执行。
 * <p>For each notification received by the center, the observer will execute 
 * the notification block. If the queue is not nil, the notification block is 
 * wrapped in a NSOperation and scheduled in the queue, otherwise the block is 
 * executed immediately in the posting thread.</p>
 */
// 这个方法是GSNotificationObserver实现的接口
// 这里如何实现指定队列回调block的?
- (id) addObserverForName: (NSString *)name 
                   object: (id)object 
                    queue: (NSOperationQueue *)queue 
               usingBlock: (GSNotificationBlock)block
{
    /**
     相比addObserver多了一层代理观察者GSNotificationObserver。
     基本流程为：
     1. 创建了一个GSNotificationObserver类型的对象observer，并把queue和block保存下来
     2. 调用接口1进行通知的注册
     3. 接收到通知时会响应didReceiveNotification回调方法，在回调方法里把block抛给指定的queue去执行
     */
    //GSNotificationObserver保存了queue和block信息，并且作为观察者注册到通知中心，
	GSNotificationObserver *observer = 
		[[GSNotificationObserver alloc] initWithQueue: queue block: block];

	[self addObserver: observer 
	         selector: @selector(didReceiveNotification:) 
	             name: name 
	           object: object];

	return observer;
}

/**
 * 如果观察者为nil，其效果是删除指定通知的所有注册表，除非观察者和名称都为nil，在这种情况下不执行任何操作。
 * Deregisters observer for notifications matching name and/or object.  If
 * either or both is nil, they act like wildcards.  The observer may still
 * remain registered for other notifications; use -removeObserver: to remove
 * it from all.  If observer is nil, the effect is to remove all registrees
 * for the specified notifications, unless both observer and name are nil, in
 * which case nothing is done.
 */
- (void) removeObserver: (id)observer
		   name: (NSString*)name
                 object: (id)object
{
  if (name == nil && object == nil && observer == nil)
      return;

  /*
   *	NB. The removal algorithm depends on an implementation characteristic
   *	of our map tables - while enumerating a table, it is safe to remove
   *	the entry returned by the enumerator.
   */

  lockNCTable(TABLE);

  if (name == nil && object == nil)
    {
      WILDCARD = listPurge(WILDCARD, observer);
    }

  if (name == nil)
    {
      GSIMapEnumerator_t	e0;
      GSIMapNode		n0;

      /*
       * 首先尝试删除此对象的所有命名集合
       * First try removing all named items set for this object.
       */
      e0 = GSIMapEnumeratorForMap(NAMED);
      n0 = GSIMapEnumeratorNextNode(&e0);
      while (n0 != 0)
	{
	  GSIMapTable		m = (GSIMapTable)n0->value.ptr;
	  NSString		*thisName = (NSString*)n0->key.obj;

	  n0 = GSIMapEnumeratorNextNode(&e0);
	  if (object == nil)
	    {
	      GSIMapEnumerator_t	e1 = GSIMapEnumeratorForMap(m);
	      GSIMapNode		n1 = GSIMapEnumeratorNextNode(&e1);

	      /*
           * object和name都为空，遍历当前名称下的键入的所有
	       * Nil object and nil name, so we step through all the maps
	       * keyed under the current name and remove all the objects
	       * that match the observer.
	       */
	      while (n1 != 0)
		{
		  GSIMapNode	next = GSIMapEnumeratorNextNode(&e1);

		  purgeMapNode(m, n1, observer);
		  n1 = next;
		}
	    }
	  else
	    {
	      GSIMapNode	n1;

	      /*
           * name为空，object不为空
	       * Nil name, but non-nil object - we locate the map for the
	       * specified object, and remove all the items that match
	       * the observer.
	       */
	      n1 = GSIMapNodeForSimpleKey(m, (GSIMapKey)object);
	      if (n1 != 0)
		{
		  purgeMapNode(m, n1, observer);
		}
	    }
	  /*
	   * If we removed all the observations keyed under this name, we
	   * must remove the map table too.
	   */
	  if (m->nodeCount == 0)
	    {
	      mapFree(TABLE, m);
	      GSIMapRemoveKey(NAMED, (GSIMapKey)(id)thisName);
	    }
	}

      /*
       * Now remove unnamed items
       */
      if (object == nil)
	{
	  e0 = GSIMapEnumeratorForMap(NAMELESS);
	  n0 = GSIMapEnumeratorNextNode(&e0);
	  while (n0 != 0)
	    {
	      GSIMapNode	next = GSIMapEnumeratorNextNode(&e0);

	      purgeMapNode(NAMELESS, n0, observer);
	      n0 = next;
	    }
	}
      else
	{
	  n0 = GSIMapNodeForSimpleKey(NAMELESS, (GSIMapKey)object);
	  if (n0 != 0)
	    {
	      purgeMapNode(NAMELESS, n0, observer);
	    }
	}
    }
  else
    {
      GSIMapTable		m;
      GSIMapEnumerator_t	e0;
      GSIMapNode		n0;

      /*
       * Locate the map table for this name.
       */
      n0 = GSIMapNodeForKey(NAMED, (GSIMapKey)((id)name));
      if (n0 == 0)
	{
	  unlockNCTable(TABLE);
	  return;		/* Nothing to do.	*/
	}
      m = (GSIMapTable)n0->value.ptr;

      if (object == nil)
	{
	  e0 = GSIMapEnumeratorForMap(m);
	  n0 = GSIMapEnumeratorNextNode(&e0);

	  while (n0 != 0)
	    {
	      GSIMapNode	next = GSIMapEnumeratorNextNode(&e0);

	      purgeMapNode(m, n0, observer);
	      n0 = next;
	    }
	}
      else
	{
	  n0 = GSIMapNodeForSimpleKey(m, (GSIMapKey)object);
	  if (n0 != 0)
	    {
	      purgeMapNode(m, n0, observer);
	    }
	}
      if (m->nodeCount == 0)
	{
	  mapFree(TABLE, m);
	  GSIMapRemoveKey(NAMED, (GSIMapKey)((id)name));
	}
    }
  unlockNCTable(TABLE);
}

/**
 * Deregisters observer from all notifications.  This should be called before
 * the observer is deallocated.
*/
- (void) removeObserver: (id)observer
{
  if (observer == nil)
    return;

  [self removeObserver: observer name: nil object: nil];
}


/**
 * 执行发送通知的私有方法，在通知返回时或者返回之前会释放掉，来避免内存溢出。
 * Private method to perform the actual posting of a notification.
 * Release the notification before returning, or before we raise
 * any exception ... to avoid leaks.
 */
#pragma mark - 发送通知的核心函数，主要做了三件事：查找通知、发送、释放资源
- (void) _postAndRelease: (NSNotification*)notification
{
  Observation	*o;
  unsigned	count;
  NSString	*name = [notification name];
  id		object;
  GSIMapNode	n;
  GSIMapTable	m;
  GSIArrayItem	i[64];
  GSIArray_t	b;
  GSIArray	a = &b;
    //step1：从named、nameless、wildcard表中查找对应的通知

  if (name == nil)
    {
      RELEASE(notification);
      [NSException raise: NSInvalidArgumentException
		  format: @"Tried to post a notification with no name."];
    }
  object = [notification object];

  /*
   * 当我们遍历这个观察表时，我们会先锁定这张表。当观察者被垃圾回收时，对象的弱指针被归零。因此为了避免一致性问题，我们在复制所有感兴趣的观察对象时禁用GC。如果在栈上有超过64个观察者的情况下，我们在数组中使用扫描内存。
   * Lock the table of observations while we traverse it.
   *
   * The table of observations contains weak pointers which are zeroed when
   * the observers get garbage collected.  So to avoid consistency problems
   * we disable gc while we copy all the observations we are interested in.
   * We use scanned memory in the array in the case where there are more
   * than the 64 observers we allowed room for on the stack.
   */
  GSIArrayInitWithZoneAndStaticCapacity(a, _zone, 64, i);
  lockNCTable(TABLE);

  /*
   * 查找既没有指定名称也没有指定对象的所有观察者。
   * Find all the observers that specified neither NAME nor OBJECT.
   */
  for (o = WILDCARD = purgeCollected(WILDCARD); o != ENDOBS; o = o->next)
    {
      GSIArrayAddItem(a, (GSIArrayItem)o);
    }

  /*
   * 查找指定对象但是没有指定名称的观察者。
   * Find the observers that specified OBJECT, but didn't specify NAME.
   */
  if (object)
    {
      n = GSIMapNodeForSimpleKey(NAMELESS, (GSIMapKey)object);
      if (n != 0)
	{
	  o = purgeCollectedFromMapNode(NAMELESS, n);
	  while (o != ENDOBS)
	    {
	      GSIArrayAddItem(a, (GSIArrayItem)o);
	      o = o->next;
	    }
	}
    }

  /*
   * 找到NAME的观察者，除了那些带有不匹配通知对象的非nil对象的观察者。
   * Find the observers of NAME, except those observers with a non-nil OBJECT
   * that doesn't match the notification's OBJECT).
   */
  if (name)
    {
      n = GSIMapNodeForKey(NAMED, (GSIMapKey)((id)name));
      if (n)
	{
	  m = (GSIMapTable)n->value.ptr;
	}
      else
	{
	  m = 0;
	}
      if (m != 0)
	{
	  /*
	   * First, observers with a matching object.
	   */
	  n = GSIMapNodeForSimpleKey(m, (GSIMapKey)object);
	  if (n != 0)
	    {
	      o = purgeCollectedFromMapNode(m, n);
	      while (o != ENDOBS)
		{
		  GSIArrayAddItem(a, (GSIArrayItem)o);
		  o = o->next;
		}
	    }

	  if (object != nil)
	    {
	      /*
	       * Now observers with a nil object.
	       */
	      n = GSIMapNodeForSimpleKey(m, (GSIMapKey)nil);
	      if (n != 0)
		{
	          o = purgeCollectedFromMapNode(m, n);
		  while (o != ENDOBS)
		    {
		      GSIArrayAddItem(a, (GSIArrayItem)o);
		      o = o->next;
		    }
		}
	    }
	}
    }

  /* Finished with the table ... we can unlock it,
   */
  unlockNCTable(TABLE);

  /*
   * 这里发送所有的通知，即调用performSelector执行相应方法，从这里可以看出是同步的。
   * Now send all the notifications.
   */
  count = GSIArrayCount(a);
  while (count-- > 0)
    {
      o = GSIArrayItemAtIndex(a, count).ext;
      if (o->next != 0)
	{
          NS_DURING
            {
              [o->observer performSelector: o->selector
                                withObject: notification];
            }
          NS_HANDLER
            {
              NSLog(@"Problem posting notification: %@", localException);
            }
          NS_ENDHANDLER
	}
    }
    /**
     对NSTable上锁，然后移除数组上的所有元素并清除这个数组,最后解锁。
     */
  lockNCTable(TABLE);
  GSIArrayEmpty(a);
  unlockNCTable(TABLE);

    //释放资源
  RELEASE(notification);
}


/**
 * Posts notification to all the observers that match its NAME and OBJECT.<br />
 * The GNUstep implementation calls -postNotificationName:object:userInfo: to
 * perform the actual posting.
 */
- (void) postNotification: (NSNotification*)notification
{
  if (notification == nil)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Tried to post a nil notification."];
    }
  [self _postAndRelease: RETAIN(notification)];
}

/**
 * Creates and posts a notification using the
 * -postNotificationName:object:userInfo: passing a nil user info argument.
 */
- (void) postNotificationName: (NSString*)name
		       object: (id)object
{
  [self postNotificationName: name object: object userInfo: nil];
}

/**
 * The preferred method for posting a notification.
 * <br />
 * 由于性能原因，不会在发送给观察者的每条消息中都包装一个异常处理程序。
 * 如果一个观察者抛出异常，列表中随后的观察者都不会收到通知。
 * For performance reasons, we don't wrap an exception handler round every
 * message sent to an observer.  This means that, if one observer raises
 * an exception, later observers in the lists will not get the notification.
 */
#pragma mark - 发送过程
/**
 从三个存储容器中：named、nameless、wildcard去查找对应的obs对象，然后通过performSelector：逐一调用响应方法，这就完成了发送流程。
 核心点：
 1. 同步发送
 2. 遍历所有列表：即注册多次通知就会响应多次
 */
- (void) postNotificationName: (NSString*)name
		       object: (id)object
		     userInfo: (NSDictionary*)info
{
  GSNotification	*notification;

  notification = (id)NSAllocateObject(concrete, 0, NSDefaultMallocZone());
  notification->_name = [name copyWithZone: [self zone]];
  notification->_object = [object retain];
  notification->_info = [info retain];
    
    //进行发送操作
  [self _postAndRelease: notification];
}

@end

