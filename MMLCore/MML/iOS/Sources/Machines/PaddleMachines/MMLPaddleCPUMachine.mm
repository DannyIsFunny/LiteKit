//
//  MMLPaddleCPUMachine.m
//  MML
//
//  Created by Baidu. Co.,Ltd. on 2020/2/11.
//  Copyright © 2020 Baidu. All rights reserved.
//

#import "MMLPaddleCPUMachine.h"
#import "MMLBaseMachine+Logger.h"
#import "MMLBaseMachine+Performancer.h"

#import "MMLData.h"
#import "PaddleCPU.h"

#include <stdio.h>
#include <string>
#include <iostream>
#include <fstream>

@interface MMLPaddleCPUMachine ()
@property (nonatomic, strong)PaddleCPU *paddleCPU;

@end

@implementation MMLPaddleCPUMachine

- (instancetype)initWithModelDir:(NSString *)modelDir
                       withError:(NSError**)error {
    if (self = [super init]) {
        if ([modelDir isKindOfClass:[NSString class]] &&
            ![modelDir isEqualToString:@""] ) {
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            
            if ( [fileManager fileExistsAtPath:modelDir] ) {
                
                PaddleCPUConfig *config = [[PaddleCPUConfig alloc]init];
                config.modelDir = modelDir;
                
                self.paddleCPU = [[PaddleCPU alloc] initWithConfig:config];
                
                NSError *loadError = nil;
                [self.paddleCPU loadWithError:&loadError];
                
                if (nil != loadError) {
                    // error
                    if (error != NULL) {
                        *error = [NSError errorWithDomain:MMLPaddleMachineInitErrorDomain code:(MMLMachineInitErrorCode)MMLMachineInitFailed userInfo:nil];
                        [self.logger errorLogMsg:[NSString stringWithFormat:@"error with detail msg, load error -- domain:%@, code:%ld, ext:%@", ( *error).domain.description, ( *error).code, ( *error).userInfo]];
                    }
                    self = nil;
                }
            } else {
                if (error != NULL) {
                    *error = [NSError errorWithDomain:MMLPaddleMachineInitErrorDomain code:(MMLMachineInitErrorCode)MMLModelFileNotFound userInfo:nil];
                }
                self = nil;
            }
        } else {
            //error
            if (error != NULL) {
                *error = [NSError errorWithDomain:MMLPaddleMachineInitErrorDomain code:(MMLMachineInitErrorCode)MMLIllegalModelFileURL userInfo:nil];
                [self.logger errorLogMsg:[NSString stringWithFormat:@"error with detail msg, file path error -- domain:%@, code:%ld, ext:%@", ( *error).domain.description, ( *error).code, ( *error).userInfo]];
            }
            self = nil;
        }
    }
    return self;
}


/*
 * @brief Action = 预测API
 * @param - input input容器
 * @param - error 错误容器 （ErrorDomain:MMLMachinPredicateErrorDomain ErrorCode:PPredicateErrorCode）
 * @return MMLPredicateOutputs* 预测结果容器
 */
- (void)predictWithInputData:(MMLData * __nonnull)aInputData completionBlock:(MMLMachinePredictCompletionBlock)aBlock {
    if (aInputData.type != TMMLDataTypeMMLShapedData) {
        NSError *aError = [NSError errorWithDomain:MMLPaddleMachinePredicateErrorDomain code:0 userInfo:nil];
        aBlock(nil, aError);
        return;
    }
    
    NSTimeInterval start = [[NSDate date] timeIntervalSince1970];
    
    MMLShapedData *input = aInputData.mmlShapedData;
    PaddleCPUInput *predictInput = [[PaddleCPUInput alloc] initWithData:input.data
                                                                 dataSize:input.dataSize
                                                                     dims:input.dim];
    
    NSError *predictError = nil;
    PaddleCPUResult *result = [self.paddleCPU predictWithInput:predictInput error:&predictError];
    
    MMLShapedData *outputShapedData = [[MMLShapedData alloc] initWithData:result.data
                                                                 dataSize:result.dataSize
                                                                     dims:result.dim];
    MMLData *predictOutput = [[MMLData alloc] initWithData:outputShapedData type:TMMLDataTypeMMLShapedData];
    
    NSTimeInterval end = [[NSDate date] timeIntervalSince1970];
    [self.logger performanceInfoLogMsg:[NSString stringWithFormat:@"paddle gpu predict time: %f ms", (end - start) * 1000]];
    
    
    aBlock(predictOutput, nil);
}


@end
