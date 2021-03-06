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


#import <Foundation/Foundation.h>
#import "PaddleGPU.h"

NS_ASSUME_NONNULL_BEGIN
// 解析metal Error Domain
FOUNDATION_EXPORT NSString * _Nonnull const PaddleGPUParseMetalErrorDomain;

// PaddleGPU的MetalLib路径解析相关状态码
typedef NS_ENUM(NSInteger, PaddleGPUMetalLibCode) {
    PaddleGPUMetalLibCodeNotExistZipPlist   = 0,// 无外层zip plist
    PaddleGPUMetalLibCodeZipPlistError      = 1,// 外层zip plist 错误
    PaddleGPUMetalLibCodeNotExistZip        = 2,// 外层zip 不存在
    PaddleGPUMetalLibCodeBundlePlistError   = 3,// 内层bundle plist 错误
    PaddleGPUMetalLibCodeRemoveBundleError  = 4,// 删除内层bundle 失败
    PaddleGPUMetalLibCodeUnzipError         = 5,// 解压zip 失败
    PaddleGPUMetalLibCodeNotExistBundle     = 6 // 不存在内层bundle
};

/// 获取PaddleGPU 自定义的MetalLib
@interface PaddleGPU (MetalResource)

/**
 获取Paddle自定义的MetalLib路径
 @param error 错误信息，具体的错误code是TPaddleGPUMetalLibCode中的枚举值
 @return paddle自定义的MetalLib路径
*/
+ (NSString *)pm_customMetalLibResourceWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
