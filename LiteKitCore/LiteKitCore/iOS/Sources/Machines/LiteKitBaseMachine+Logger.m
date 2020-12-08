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


#import "LiteKitBaseMachine+Logger.h"
#import <objc/runtime.h>

@implementation LiteKitMachine (Logger)

- (void)setLogger:(id<LiteKitLoggerProtocol>)logger {
    objc_setAssociatedObject(self, @selector(logger), logger, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id <LiteKitLoggerProtocol>)logger {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setupMachineLoggerFromMachineLoggerName:(NSString *)loggerClassName {
    if ([loggerClassName isKindOfClass:[NSString class]] &&
        loggerClassName.length > 0 &&
        NSClassFromString(loggerClassName) &&
        [NSClassFromString(loggerClassName) instancesRespondToSelector:@selector(setLogTag:)]) {
        id <LiteKitLoggerProtocol> logger = [NSClassFromString(loggerClassName) new];
        [logger setLogTag:LiteKitMachineLoggerTag];
        [self setLogger:logger];
    } else {
#if __has_include("LiteKitLogger.h")
    id <LiteKitLoggerProtocol> logger = [[LiteKitLogger alloc] initWithTag:LiteKitMachineLoggerTag];
    [self setLogger:logger];
#endif
    }
}


@end