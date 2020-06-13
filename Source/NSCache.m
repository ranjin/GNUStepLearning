/* Implementation for NSCache for GNUStep
   Copyright (C) 2009 Free Software Foundation, Inc.

   Written by:  David Chisnall <csdavec@swan.ac.uk>
   Created: 2009

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

#import "common.h"

#define	EXPOSE_NSCache_IVARS	1

#import "Foundation/NSArray.h"
#import "Foundation/NSCache.h"
#import "Foundation/NSMapTable.h"
#import "Foundation/NSEnumerator.h"

/**
 * _GSCachedObject is effectively used as a structure containing the various
 * things that need to be associated with objects stored in an NSCache.  It is
 * an NSObject subclass so that it can be used with OpenStep collection
 * classes.
 */
@interface _GSCachedObject : NSObject
{
  @public
  id object;
  NSString *key;
  int accessCount;
  NSUInteger cost;
  BOOL isEvictable;
}
@end

@interface NSCache (EvictionPolicy)

//在缓存中控制收回策略的方法
/** The method controlling eviction policy in an NSCache. */
- (void) _evictObjectsToMakeSpaceForObjectWithCost: (NSUInteger)cost;
@end

@implementation NSCache
- (id) init
{
  if (nil == (self = [super init]))
    {
      return nil;
    }
  ASSIGN(_objects,[NSMapTable strongToStrongObjectsMapTable]);
  _accesses = [NSMutableArray new];
  return self;
}

- (NSUInteger) countLimit
{
  return _countLimit;
}

- (id) delegate
{
  return _delegate;
}

- (BOOL) evictsObjectsWithDiscardedContent
{
  return _evictsObjectsWithDiscardedContent;
}

- (NSString*) name
{
  return _name;
}

- (id) objectForKey: (id)key
{
  _GSCachedObject *obj = [_objects objectForKey: key];

  if (nil == obj)
    {
      return nil;
    }
  if (obj->isEvictable)
    {
      // Move the object to the end of the access list.
      [_accesses removeObjectIdenticalTo: obj];
      [_accesses addObject: obj];
    }
  obj->accessCount++;
  _totalAccesses++;
  return obj->object;
}

- (void) removeAllObjects
{
  NSEnumerator *e = [_objects objectEnumerator];
  _GSCachedObject *obj;

  while (nil != (obj = [e nextObject]))
    {
      [_delegate cache: self willEvictObject: obj->object];
    }
  [_objects removeAllObjects];
  [_accesses removeAllObjects];
  _totalAccesses = 0;
}

- (void) removeObjectForKey: (id)key
{
  _GSCachedObject *obj = [_objects objectForKey: key];

  if (nil != obj)
    {
      [_delegate cache: self willEvictObject: obj->object];
      _totalAccesses -= obj->accessCount;
      [_objects removeObjectForKey: key];
      [_accesses removeObjectIdenticalTo: obj];
    }
}

- (void) setCountLimit: (NSUInteger)lim
{
  _countLimit = lim;
}

- (void) setDelegate:(id)del
{
  _delegate = del;
}

- (void) setEvictsObjectsWithDiscardedContent:(BOOL)b
{
  _evictsObjectsWithDiscardedContent = b;
}

- (void) setName: (NSString*)cacheName
{
  ASSIGN(_name, cacheName);
}

- (void) setObject: (id)obj forKey: (id)key cost: (NSUInteger)num
{
  _GSCachedObject *oldObject = [_objects objectForKey: key];
  _GSCachedObject *newObject;

    //先根据key值查找有无旧值，有则先移除，后设置新值。
  if (nil != oldObject)
    {
      [self removeObjectForKey: oldObject->key];
    }
    //根据传过来的cost进行缓存淘汰。
  [self _evictObjectsToMakeSpaceForObjectWithCost: num];
    //创建一个新的缓存对象，将属性赋值进去。
  newObject = [_GSCachedObject new];
  // Retained here, released when obj is dealloc'd
    //创建
  newObject->object = RETAIN(obj);
  newObject->key = RETAIN(key);
  newObject->cost = num;
  if ([obj conformsToProtocol: @protocol(NSDiscardableContent)])
    {
      newObject->isEvictable = YES;
      [_accesses addObject: newObject];
    }
    //将这个新创建的对象set进NSMapTable当中去。
  [_objects setObject: newObject forKey: key];
  RELEASE(newObject);
    
    //总占用数更新
  _totalCost += num;
}

- (void) setObject: (id)obj forKey: (id)key
{
  [self setObject: obj forKey: key cost: 0];
}

- (void) setTotalCostLimit: (NSUInteger)lim
{
  _costLimit = lim;
}

- (NSUInteger) totalCostLimit
{
  return _costLimit;
}

/**
 * This method is the one that handles the eviction policy.  This
 * implementation uses a relatively simple LRU/LFU hybrid.  The NSCache
 * documentation from Apple makes it clear that the policy may change, so we
 * could in future have a class cluster with pluggable policies for different
 * caches or some other mechanism.
 */

//根据穿过来
- (void)_evictObjectsToMakeSpaceForObjectWithCost: (NSUInteger)cost
{
  NSUInteger spaceNeeded = 0;
    //获取到缓存映射表的数量
  NSUInteger count = [_objects count];

    //如果总开销大于0 && 存储对象的总成本+消耗的成本 > 总开销
  if (_costLimit > 0 && _totalCost + cost > _costLimit)
    {
        
      spaceNeeded = _totalCost + cost - _costLimit;
    }

    //只有我们需要空间的时候才会被驱逐。
  // Only evict if we need the space.
    //计算出需要驱逐的空间大小：总开销+本子set的开销-限制的大小
  if (count > 0 && (spaceNeeded > 0 || count >= _countLimit))
    {
      NSMutableArray *evictedKeys = nil;
      // Round up slightly.
        //计算出一个平均访问次数：取平均值的百分之二十，用了一个二八定律。它的淘汰策略的根本原理也就是我们经常说的LRU。
      NSUInteger averageAccesses = ((_totalAccesses / (double)count) * 0.2) + 1;
      NSEnumerator *e = [_accesses objectEnumerator];
      _GSCachedObject *obj;

        //如果是需要驱逐的
      if (_evictsObjectsWithDiscardedContent)
	{
	  evictedKeys = [[NSMutableArray alloc] init];
	}
      while (nil != (obj = [e nextObject]))
	{
        //不要驱逐经常访问的对象
	  // Don't evict frequently accessed objects.
        //循环处理，发送通知。直到达到计算出来的所需空间。最后更新占用数等属性。
	  if (obj->accessCount < averageAccesses && obj->isEvictable)
	    {
	      [obj->object discardContentIfPossible];
	      if ([obj->object isContentDiscarded])
		{
		  NSUInteger cost = obj->cost;

		  // Evicted objects have no cost.
		  obj->cost = 0;
		  // Don't try evicting this again in future; it's gone already.
		  obj->isEvictable = NO;
		  // Remove this object as well as its contents if required
		  if (_evictsObjectsWithDiscardedContent)
		    {
		      [evictedKeys addObject: obj->key];
		    }
		  _totalCost -= cost;
            
            //如果我们释放了足够的空间，就完事了
		  // If we've freed enough space, give up
		  if (cost > spaceNeeded)
		    {
		      break;
		    }
		  spaceNeeded -= cost;
		}
	    }
	}
        //如果需要的话，驱逐其内容已被丢弃的所有对象
      // Evict all of the objects whose content we have discarded if required
      if (_evictsObjectsWithDiscardedContent)
	{
	  NSString *key;

	  e = [evictedKeys objectEnumerator];
	  while (nil != (key = [e nextObject]))
	    {
	      [self removeObjectForKey: key];
	    }
	}
    [evictedKeys release];
    }
}

- (void) dealloc
{
  [_name release];
  [_objects release];
  [_accesses release];
  [super dealloc];
}
@end

@implementation _GSCachedObject
- (void) dealloc
{
  [object release];
  [key release];
  [super dealloc];
}
@end
