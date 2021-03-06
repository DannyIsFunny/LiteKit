/*
 Copyright © 2020 Baidu, Inc. All Rights Reserved.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
 to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/


#import "LiteKitTaskQueue.h"
#import "LiteKitCommonDefines.h"

NSString * const LiteKitTaskQueueErrorDomain = @"LiteKitTaskQueueErrorDomain";
static NSString * const kLiteKitTaskSerialQueueName = @"__kLiteKitTaskSerialQueueName__";

@interface LiteKitTaskQueue ()
/// 任务队列
@property (nonatomic, strong) NSMutableArray <LiteKitTask *> *taskStack;
/// 任务队列中所有任务的Machine
@property (nonatomic, strong) NSMutableDictionary <NSString *, LiteKitBaseMachine *> *queueMachines;
/// 在单独的线程中执行任务
@property (nonatomic, strong) dispatch_queue_t serial_queue;
/// 日志器
@property (nonatomic, strong) id <LiteKitLoggerProtocol> logger;
/// 是否打开性能数据统计
@property (nonatomic, assign) BOOL openPerformanceProfiler;
/// 队列状态
@property (nonatomic, assign, readwrite) LiteKitTaskQueueStatus queueStatus;
@end

@implementation LiteKitTaskQueue

#pragma mark - Init

- (instancetype)init {
    if (self = [super init]) {
        _serial_queue = dispatch_queue_create(kLiteKitTaskSerialQueueName.UTF8String, DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Dealloc

- (void)dealloc {
    [self litekit_releaseMachineInQueueMachines];
    self.queueMachines = nil;
    self.taskStack = nil;
    self.serial_queue = nil;
    [self.logger warningLogMsg:@"Task Queue dealloc"];
    self.logger = nil;
}

#pragma mark - Public

- (void)setupLoggerName:(NSString *)loggerClassName {
    if ([loggerClassName isKindOfClass:[NSString class]] &&
        loggerClassName.length > 0 &&
        NSClassFromString(loggerClassName) &&
        [NSClassFromString(loggerClassName) instancesRespondToSelector:@selector(setLogTag:)]) {
        self.logger = [NSClassFromString(loggerClassName) new];
        [self.logger setLogTag:LiteKitTaskQueueLoggerTag];
    } else {
#if __has_include("LiteKitLogger.h")
        self.logger = [[LiteKitLogger alloc] initWithTag:LiteKitTaskQueueLoggerTag];
#endif
    }
}

- (void)enablePerformanceProfiler:(BOOL)performanceProfiler {
    self.openPerformanceProfiler = performanceProfiler;
}

- (void)addHighPriorityTasks:(NSArray <LiteKitTask *> *)tasks error:(NSError **)aError {
    [self litekit_internalBatchAddTasks:tasks atHead:YES error:aError];
}

- (void)addTasks:(NSArray <LiteKitTask *> *)tasks error:(NSError **)aError {
    [self litekit_internalBatchAddTasks:tasks atHead:NO error:aError];
}

- (void)removeTasks:(NSArray <LiteKitTask *> *)tasks error:(NSError **)aError {
    if (tasks && [tasks isKindOfClass:[NSArray class]] && tasks.count > 0) {
       dispatch_async(self.serial_queue, ^{
           NSMutableArray *taskStackCopy = [self.taskStack mutableCopy];
           // 循环遍历找出待删除的元素的index
           for (int index = 0; index <= tasks.count - 1; index++) {
               for (int stackIndex = 0; stackIndex < self.taskStack.count; stackIndex++) {
                   LiteKitTask *taskInQueue = [self.taskStack objectAtIndex:stackIndex];
                   if ([taskInQueue.taskID isEqualToString:tasks[index].taskID]) {
                       [taskInQueue cancel];
                       [taskStackCopy removeObjectAtIndex:index];
                       [self litekit_removeMachineByTask:tasks[index]];
                   }
               }
           }
           self.taskStack = [taskStackCopy mutableCopy];
           [self litekit_performTaskQueue];
       });
   } else {
       if (aError != NULL) {
           *aError = [NSError errorWithDomain:LiteKitTaskQueueErrorDomain code:LiteKitTaskQueueParamError userInfo:nil];
           [self.logger errorLogMsg:[NSString stringWithFormat:@"error with detail msg -- domain:%@, code:%ld, ext:%@", (*aError).domain.description, (*aError).code, (*aError).userInfo]];
       }
   }
}

//加到队首
- (void)addHighPriorityTask:(LiteKitTask *)task error:(NSError **)aError {
    [self litekit_internalAddTask:task atHead:YES error:aError];
}

//加入队尾
- (void)addTask:(LiteKitTask *)task error:(NSError **)aError {
    [self litekit_internalAddTask:task atHead:NO error:aError];
}

// 移除单个任务
- (void)removeTask:(LiteKitTask *)task error:(NSError **)aError {
    if (task && [task isKindOfClass:[LiteKitTask class]]) {
        dispatch_async(self.serial_queue, ^{
            NSMutableArray *taskStackCopy = [self.taskStack mutableCopy];
            for (int index = 0; index < self.taskStack.count; index++) {
                LiteKitTask *taskInQueue = [self.taskStack objectAtIndex:index];
                if ([taskInQueue.taskID isEqualToString:task.taskID]) {
                    [taskInQueue cancel];
                    [taskStackCopy removeObjectAtIndex:index];
                }
            }
            self.taskStack = [taskStackCopy mutableCopy];
            
            [self litekit_removeMachineByTask:task];
            [self litekit_performTaskQueue];
        });
    } else {
        if (aError != NULL) {
            *aError = [NSError errorWithDomain:LiteKitTaskQueueErrorDomain code:LiteKitTaskQueueParamError userInfo:nil];
            [self.logger errorLogMsg:[NSString stringWithFormat:@"error with detail msg -- domain:%@, code:%ld, ext:%@", (*aError).domain.description, (*aError).code, (*aError).userInfo]];
        }
    }
}

// 查询任务状态
- (LiteKitTaskStatus)taskStatusByID:(NSString *)taskID {
    LiteKitTaskStatus status = LiteKitTaskStatusWaiting;
    for (LiteKitTask *task in self.taskStack) {
        if ([task.taskID isEqualToString:taskID]) {
            status = task.taskStatus;
            break;
        }
    }
    return status;
}

// 移除所有任务
- (void)removeAllTasks {
    dispatch_async(self.serial_queue, ^{
        [self.taskStack removeAllObjects];
    });
}

/// 释放Machine
- (void)releaseMachine {
    dispatch_async(self.serial_queue, ^{
        [self litekit_releaseMachineInQueueMachines];
    });
}

#pragma mark - Task Scheduling

- (void)litekit_performTaskQueue {
    if (self.queueStatus == LiteKitTaskQueueStatusBusy) {
        return;
    } else {
        if (self.taskStack.count > 0) {
            self.queueStatus = LiteKitTaskQueueStatusBusy;
            [self.logger debugLogMsg:@"队列调度开始"];
            // 先进先出
            LiteKitTask *nextTask = [self.taskStack firstObject];
            if (nextTask.taskStatus == LiteKitTaskStatusFinished ||
                nextTask.taskStatus == LiteKitTaskStatusCanceled) {
                // 出队
                [self litekit_taskFinished:nextTask];
            } else if (nextTask.taskStatus == LiteKitTaskStatusExecuting) { // 任务正在执行
                return;
            } else {
                [self litekit_executeTask:nextTask];
            }
        } else {
            // 队列空闲需要手动clearMachine
            [self litekit_clearMachineInQueueMachines];
        }
    }
}

- (void)litekit_executeTask:(LiteKitTask *)task {
    [self.logger debugLogMsg:@"execute task start"];
    LiteKitBaseMachine *taskMachine = task.machine;
    if (taskMachine) {
        // 执行task
        [self litekit_executeTaskWithMachine:taskMachine task:task];
    } else {
        // 向外抛错
        LiteKitTaskCompletionBlock block = task.taskBlock;
        if (block) {
            NSError *aError = [NSError errorWithDomain:LiteKitTaskQueueErrorDomain code:LiteKitTaskQueueNULLMachine userInfo:nil];
            [self.logger errorLogMsg:[NSString stringWithFormat:@"error with detail msg -- domain:%@, code:%ld, ext:%@", aError.domain.description, aError.code, aError.userInfo]];
            block(nil, aError);
        }
        [self.logger debugLogMsg:@"execute task finish"];
        
        dispatch_async(self.serial_queue, ^{
            [self litekit_taskFinished:task];
        });
    }
}


- (void)litekit_executeTaskWithMachine:(LiteKitBaseMachine *)machine task:(LiteKitTask *)task {
    NSTimeInterval start = [[NSDate date] timeIntervalSince1970];
    __weak typeof (self) weakSelf = self;
    
    if (self.openPerformanceProfiler) {
        [task runPerformanceTaskWithCompletionBlock:^(NSError * _Nullable error) {
            dispatch_async(self.serial_queue, ^{
                NSTimeInterval end = [[NSDate date] timeIntervalSince1970];
                __strong typeof (self) strongSelf = weakSelf;
                if (error) {
                    [strongSelf.logger errorLogMsg:[NSString stringWithFormat:@"error with detail msg -- domain:%@, code:%ld, ext:%@", error.domain.description, error.code, error.userInfo]];
                }
                [strongSelf.logger debugLogMsg:@"execute task finish"];
                [strongSelf.logger performanceInfoLogMsg:[NSString stringWithFormat:@"execute task cost time : %.3f", (end - start) * 1000]];
                [strongSelf litekit_taskFinished:task];
            });
        }];
    } else {
        [task runTaskWithCompletionBlock:^(NSError * _Nullable error) {
            dispatch_async(self.serial_queue, ^{
                NSTimeInterval end = [[NSDate date] timeIntervalSince1970];
               __strong typeof (self) strongSelf = weakSelf;
                if (error) {
                    [strongSelf.logger errorLogMsg:[NSString stringWithFormat:@"error with detail msg -- domain:%@, code:%ld, ext:%@", error.domain.description, error.code, error.userInfo]];
                }
                [strongSelf.logger debugLogMsg:@"execute task finish"];
                [strongSelf.logger performanceInfoLogMsg:[NSString stringWithFormat:@"execute task cost time : %.3f", (end - start) * 1000]];
                [strongSelf litekit_taskFinished:task];
            });
        }];
    }
}

/// 任务出队
/// @param task 待出队的任务
- (void)litekit_taskFinished:(LiteKitTask *)task {
    [self.logger debugLogMsg:@"dequeue the finish task start"];
    if (task && [task isKindOfClass:[LiteKitTask class]]) {
        [self.taskStack removeObject:task];
    }
    [self.logger debugLogMsg:[NSString stringWithFormat:@"dequeue the finish task end, 队列剩余任务数目 == %lu", (unsigned long)self.taskStack.count]];
    self.queueStatus = LiteKitTaskQueueStatusFree;
    
    [self litekit_removeMachineByTask:task];
    [self litekit_performTaskQueue];
}

#pragma mark - Private

- (void)litekit_releaseMachineInQueueMachines {
    for (NSString *machineId in self.queueMachines.allKeys) {
        LiteKitBaseMachine *machine = [self.queueMachines objectForKey:machineId];
        [machine releaseMachine];
    }
}

- (void)litekit_clearMachineInQueueMachines {
    for (NSString *machineId in self.queueMachines.allKeys) {
        LiteKitBaseMachine *machine = [self.queueMachines objectForKey:machineId];
        [machine clearMachine];
    }
}

- (void)litekit_addMachineByTask:(LiteKitTask *)task {
    if (![self.queueMachines objectForKey:task.machine.machineId]) {
        // store service
        if (task.machine && task.machine.machineId) {
            [self.queueMachines setObject:task.machine forKey:task.machine.machineId];
        }
    }
}

- (void)litekit_removeMachineByTask:(LiteKitTask *)task {
    BOOL needRemoveMachineService = YES;
    for (LiteKitTask *taskInStack in self.taskStack) {
        if ([task.machine.machineId isEqualToString:taskInStack.machine.machineId]) {
            needRemoveMachineService = NO;
            break;
        }
    }

    if (needRemoveMachineService && [self.queueMachines objectForKey:task.machine.machineId]) {
        [self.queueMachines removeObjectForKey:task.machine.machineId];
    }
}

- (void)litekit_internalAddTask:(LiteKitTask *)task atHead:(BOOL)atHead error:(NSError **)aError {
    if (task && [task isKindOfClass:[LiteKitTask class]]) {
        dispatch_async(self.serial_queue, ^{
            if (atHead) { // 插到队尾
                [self.taskStack insertObject:task atIndex:0];
            } else { // 插到队首
                [self.taskStack addObject:task];
            }
            
            [self litekit_addMachineByTask:task];
            [self litekit_performTaskQueue];
        });
    } else {
        if (aError != NULL) {
            *aError = [NSError errorWithDomain:LiteKitTaskQueueErrorDomain code:LiteKitTaskQueueParamError userInfo:nil];
            [self.logger errorLogMsg:[NSString stringWithFormat:@"error with detail msg -- domain:%@, code:%ld, ext:%@", (*aError).domain.description, (*aError).code, (*aError).userInfo]];
        }
    }
}

- (void)litekit_internalBatchAddTasks:(NSArray <LiteKitTask *> *)tasks atHead:(BOOL)atHead error:(NSError **)aError {
    if (tasks && [tasks isKindOfClass:[NSArray class]] && tasks.count > 0) {
        dispatch_async(self.serial_queue, ^{
            if (atHead) {
                [self.taskStack insertObjects:tasks atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, tasks.count)]];
            } else {
                [self.taskStack addObjectsFromArray:tasks];
            }
            
            for (NSInteger index = 0; index <= tasks.count - 1; index++) {
                [self litekit_addMachineByTask:tasks[index]];
            }
            [self litekit_performTaskQueue];
        });
    } else {
        if (aError != NULL) {
            *aError = [NSError errorWithDomain:LiteKitTaskQueueErrorDomain code:LiteKitTaskQueueParamError userInfo:nil];
            [self.logger errorLogMsg:[NSString stringWithFormat:@"error with detail msg -- domain:%@, code:%ld, ext:%@", (*aError).domain.description, (*aError).code, (*aError).userInfo]];
        }
    }
}


#pragma mark - Getter

- (NSMutableArray <LiteKitTask *> *)taskStack {
    if (!_taskStack) {
        _taskStack = [[NSMutableArray alloc] init];
    }
    return _taskStack;
}

- (NSMutableDictionary <NSString *, LiteKitBaseMachine *> *)queueMachines {
    if (!_queueMachines) {
        _queueMachines = [NSMutableDictionary dictionaryWithCapacity:1];
    }
    return _queueMachines;
}

@end
