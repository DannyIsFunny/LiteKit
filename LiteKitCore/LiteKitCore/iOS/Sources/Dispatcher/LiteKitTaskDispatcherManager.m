// Copyright (c) 2019 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


#import "LiteKitTaskDispatcherManager.h"


#define LOCK(lock) dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
#define UNLOCK(lock) dispatch_semaphore_signal(lock);

@interface LiteKitTaskDispatcherManager () 

@property (nonatomic, strong) NSMutableDictionary <NSString *, LiteKitTaskQueue *> *queueMap;

@property (nonatomic, strong) dispatch_semaphore_t lock;

@property (nonatomic, strong, readwrite) NSArray <NSString *> *businessIds;
@end

@implementation LiteKitTaskDispatcherManager

#pragma mark - Init

+ (instancetype)sharedInstance {
    static LiteKitTaskDispatcherManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LiteKitTaskDispatcherManager alloc] init];
    });
    
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _lock = dispatch_semaphore_create(1);
        _queueMap = [NSMutableDictionary dictionary];
    }
    
    return self;
}

#pragma mark - Public
/// 申请一个TaskQueue
/// @param businessId 业务ID
- (LiteKitTaskQueue *)applyLiteKitTaskQueueWithBusinessId:(NSString *)businessId {
    if (!businessId || ![businessId isKindOfClass:[NSString class]]) {
        return nil;
    }
    LiteKitTaskQueue *taskQueue = [self litekit_queueForKey:businessId];
    if (taskQueue) { // 基于该业务ID已经存在相应的绑定
        return taskQueue;
    } else {
        // 创建一个queue
        taskQueue = [[LiteKitTaskQueue alloc] init];
        [self litekit_addQueue:taskQueue forKey:businessId];
        return taskQueue;
    }
}

- (void)removeLiteKitTaskQueueWithBusinessId:(NSString *)businessId {
    LiteKitTaskQueue *queue = [self litekit_queueForKey:businessId];
    [queue releaseMachine];
    [self litekit_deleteQueueForKey:businessId];
}

#pragma mark - Private

- (LiteKitTaskQueue *)litekit_queueForKey:(NSString *)key {
    LOCK(self.lock);
    LiteKitTaskQueue *queue = self.queueMap[key];
    UNLOCK(self.lock);
    return queue;
}

- (void)litekit_addQueue:(LiteKitTaskQueue *)queue forKey:(NSString *)key {
    LOCK(self.lock);
    if (key && [key isKindOfClass:[NSString class]]) {
        self.queueMap[key] = queue;
    }
    UNLOCK(self.lock);
}

- (void)litekit_deleteQueueForKey:(NSString *)key {
    LOCK(self.lock);
    [self.queueMap removeObjectForKey:key];
    UNLOCK(self.lock);
}


#pragma mark - Getter

- (NSArray <NSString *> *)businessIds {
    if (!_businessIds) {
        _businessIds = [self.queueMap allKeys];
    }
    return _businessIds;
}


@end