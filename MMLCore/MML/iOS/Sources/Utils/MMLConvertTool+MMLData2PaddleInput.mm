//
//  MMLConvertTool+MMLData2PaddleInput.m
//  MML
//
//  Created by Baidu. Co.,Ltd. on 2019/11/21.
//  Copyright © 2019 Baidu. All rights reserved.
//

#import "MMLConvertTool+MMLData2PaddleInput.h"
#include <opencv2/core/utility.hpp>
#include <opencv2/imgproc.hpp>
#import "MMLPaddleConfig.h"
#import <CoreVideo/CoreVideo.h>
#import "MMLDataProcess.h"

using namespace cv;
using namespace std;

@implementation MMLConvertTool(MMLInputMatrix)
#pragma mark - MMLInputMatrix converters
+ (MMLInputMatrix *)inputMatrixConvertFromImage:(UIImage *)image {
    MMLInputMatrix *returnData = [self mml_createInputMatrixWithImage:image];
    return returnData;
}

+ (MMLInputMatrix *)inputMatrixConvertFromImageURL:(NSString *)imageURL {
    UIImage *image = [UIImage imageWithContentsOfFile:imageURL];
    MMLInputMatrix *returnData = [self mml_createInputMatrixWithImage:image];
    
    return returnData;
}

+ (MMLInputMatrix *)inputMatrixConvertFromCVPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    UIImage *image = [self mml_pixelBufferToImage:pixelBuffer];
    MMLInputMatrix *returnData = [self mml_createInputMatrixWithImage:image];
    return returnData;
}

+ (MMLInputMatrix *)inputMatrixConvertFromMultiArray:(MLMultiArray *)multiArray {
    UIImage *image = [self mml_mulArrayToImage:multiArray];
    MMLInputMatrix *returnData = [self mml_createInputMatrixWithImage:image];
    return returnData;
}

+ (MMLInputMatrix *)inputMatrixConvertFromMMLShapedData:(MMLShapedData *)shapedData {
    if ( nil == shapedData || [shapedData.dim count] < 4 ) {
        return nil;
    }
    MMLInputMatrix *returnData = [[MMLInputMatrix alloc] initWithWith:shapedData.dim[3].intValue
                                                            andHeight:shapedData.dim[2].intValue
                                                           andChannel:shapedData.dim[1].intValue
                                                       andInputPixels:shapedData.data];
    return returnData;
}

#pragma mark - methods
+ (UIImage *)mml_mulArrayToImage:(MLMultiArray *)aMLArray{
    if (aMLArray.shape.count < 5) {
        return nil;
    }
    
    NSInteger channelAxis = 2;
    NSInteger heightAxis = 3;
    NSInteger widthAxis = 4;
    
    NSInteger height = aMLArray.shape[heightAxis].intValue;
    NSInteger width = aMLArray.shape[widthAxis].intValue;
    
    NSInteger channel = aMLArray.shape[channelAxis].intValue;
    if (channel>3) {
        //最多只能处理4通道（RGBA）
        channel = 4;
    }
    
    NSInteger cStride = aMLArray.strides[channelAxis].intValue;
    
    NSInteger count = height * width * channel;
    UInt8 *pixels = (UInt8 *)alloca(sizeof(UInt8)*count);
    
    double *ptr = (double *)aMLArray.dataPointer ;
    
    double *channel1 = channel>1 ? ptr+cStride*1 : NULL;
    double *channel2 = channel>2 ? ptr+cStride*2 : NULL;
    double *channel3 = channel>3 ? ptr+cStride*3 : NULL;
    for (int i = 0; i<width * height; i++) {
        pixels[i*channel] = ptr[i];
        if (channel1 != NULL) { pixels[i*channel+1] = channel1[i]; }
        if (channel2 != NULL) { pixels[i*channel+2] = channel2[i]; }
        if (channel3 != NULL) { pixels[i*channel+3] = channel3[i]; }
    }
    
    CVPixelBufferRef pixelBuffer = NULL;
    OSType pixelFormatType;
    if (channel == 1) {
        pixelFormatType = kCVPixelFormatType_OneComponent8;
    } else {
        pixelFormatType = kCVPixelFormatType_32BGRA;
    }
    NSDictionary *options = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVReturn status = CVPixelBufferCreateWithBytes(kCFAllocatorDefault,
                                                   width,
                                                   height,
                                                   pixelFormatType,
                                                   pixels,
                                                   width,
                                                   NULL,
                                                   NULL,
                                                   (__bridge CFDictionaryRef) options,
                                                   &pixelBuffer);
    
    UIImage *image = [self mml_pixelBufferToImage:pixelBuffer];
    CVBufferRelease(pixelBuffer);
    
    return image;
}

+ (UIImage *)mml_pixelBufferToImage:(CVPixelBufferRef)pixelBuffer {
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    
    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
    CGImageRef videoImage = [temporaryContext
                             createCGImage:ciImage
                             fromRect:CGRectMake(0, 0, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer))];
    
    UIImage *uiImage = [UIImage imageWithCGImage:videoImage];
    CGImageRelease(videoImage);
    
    return uiImage;
}

+ (MMLInputMatrix *)mml_createInputMatrixWithImage:(UIImage *)image {
    if (!image) {
        return nil;
    }
    // uiimage to mat
    Mat inputImage;
    inputImage = [MMLDataProcess mml_CVMatFromUIImage:image];

    float *image_data = NULL;
    
    int w = inputImage.cols;
    int h = inputImage.rows;
    int c = inputImage.channels();
    
    switch (c) {
        case 4: {
            image_data = (float *)malloc(w * h * sizeof(float) * 4);
            
            // split
            Mat YCbCr;
            cvtColor(inputImage, YCbCr, CV_RGB2YCrCb, 0);
            
            vector<Mat> channels;
            split(YCbCr, channels);
            
            Mat Y = [self mml_samplingChannel:channels.at(0) samplingRate:255];
            [MMLDataProcess mml_convertCVMatData:Y toFloatData:image_data];
            Mat Cr = [self mml_samplingChannel:channels.at(1) samplingRate:255];
            [MMLDataProcess mml_convertCVMatData:Cr toFloatData:image_data+(w * h)];
            Mat Cb = [self mml_samplingChannel:channels.at(2) samplingRate:255];
            [MMLDataProcess mml_convertCVMatData:Cb toFloatData:image_data+(w * h * 2)];

            Mat alpha;
            extractChannel(inputImage, alpha, 3);
            alpha = [self mml_samplingChannel:alpha samplingRate:255];
            [MMLDataProcess mml_convertCVMatData:alpha toFloatData:image_data+(w * h * 3)];
            
            break;
        }

        case 3: {
            image_data = (float *)malloc(w * h * sizeof(float) * 3);
            
            // split
            Mat YCbCr;
            cvtColor(inputImage, YCbCr, CV_RGB2YCrCb, 0);
            
            vector<Mat> channels;
            split(YCbCr, channels);
 
            Mat Y = [self mml_samplingChannel:channels.at(0) samplingRate:255];
            [MMLDataProcess mml_convertCVMatData:Y toFloatData:image_data];
            Mat Cr = [self mml_samplingChannel:channels.at(1) samplingRate:255];
            [MMLDataProcess mml_convertCVMatData:Cr toFloatData:image_data+(w * h * sizeof(float))];
            Mat Cb = [self mml_samplingChannel:channels.at(2) samplingRate:255];
            [MMLDataProcess mml_convertCVMatData:Cb toFloatData:image_data+(w * h * sizeof(float) * 2)];
            break;
        }

        case 1: {
            image_data = (float *)malloc(w * h * sizeof(float) * 1);
            
            Mat YCbCr;
            cvtColor(inputImage, YCbCr, CV_RGB2YCrCb, 0);
            
            vector<Mat> channels;
            split(YCbCr, channels);
            
            Mat Y = [self mml_samplingChannel:channels.at(0) samplingRate:255];
            [MMLDataProcess mml_convertCVMatData:Y toFloatData:image_data];
        }
            
        default:
            break;
    }
    
    MMLInputMatrix *returnMatrix = [[MMLInputMatrix alloc] initWithWith:w
                                                              andHeight:h
                                                             andChannel:c
                                                         andInputPixels:image_data];
    
    return returnMatrix;
}



+ (Mat)mml_samplingChannel:(Mat)samplingMat samplingRate:(NSInteger)samplingRate {
    Mat pixel;
    samplingMat.convertTo(pixel, CV_32FC1, 1.f / samplingRate);
    return pixel;
}

@end