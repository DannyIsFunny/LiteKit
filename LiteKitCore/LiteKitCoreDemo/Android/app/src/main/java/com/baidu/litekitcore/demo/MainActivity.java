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

package com.baidu.litekitcore.demo;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;


import com.baidu.litekitcore.demo.utils.FileUtil;
import com.baidu.litekitcore.LiteKitBaseMachine;
import com.baidu.litekitcore.LiteKitData;
import com.baidu.litekitcore.LiteKitMachineConfig;
import com.baidu.litekitcore.LiteKitMachineService;
import com.baidu.litekitcore.LiteKitPaddleConfig;
import com.baidu.litekitcore.LiteKitPaddleLiteConfig;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.util.ArrayList;

public class MainActivity extends AppCompatActivity {

    private static final String TAG = "litekitcore-java";
    private static final int modelInputBatchSize = 1;
    private static final int modelInputChannel = 3;
    private static final int modelInputWidth = 256;
    private static final int modelInputHeight = 256;

    // Used to load the 'native-lib' library on application startup.
    static {
        System.loadLibrary("native-lib");
    }

    Bitmap image = null;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        for (int i = 0; i < 20; ++i) {
            doRun();
        }
        Toast.makeText(this, "litekitcore, successful", Toast.LENGTH_LONG).show();
    }

    /**
     * 完整的litekitcore java api调用示例代码，从
     * 读取输入 --> 预处理 --> 创建LiteKit推理引擎 --> feed input data --> run --> fetch --> 后处理 --> 释放
     */
    void doRun() {
        // 读取输入图片
        try {
            InputStream is = getApplicationContext().getAssets().open("images/test.jpg");
            image = BitmapFactory.decodeStream(is);
            is.close();
        } catch (IOException e) {
            Log.e(TAG, e.toString());
            System.exit(-1);
        }
        // 预处理数据
        float[] inputData = createInputData(image);
        if (inputData.length != modelInputBatchSize * modelInputChannel * modelInputHeight * modelInputWidth) {
            Log.e(TAG, "input data error");
            System.exit(-1);
        }
        // 创建LiteKitMachine
        LiteKitMachineConfig machineConfig = new LiteKitMachineConfig();
        LiteKitPaddleConfig paddleConfig = new LiteKitPaddleConfig();
        paddleConfig.liteConfig = new LiteKitPaddleLiteConfig();
        machineConfig.modelPath = modelPath();
        machineConfig.machineType = LiteKitMachineConfig.MachineType.LiteKitPaddleLite;
        machineConfig.engineConifg = paddleConfig;
        LiteKitBaseMachine machine = LiteKitMachineService.loadMachineWithConfig(machineConfig);
        // 组装LiteKitData输入
        ArrayList<LiteKitData> input = new ArrayList<>();
        LiteKitData data = new LiteKitData(inputData, modelInputBatchSize, modelInputChannel, modelInputHeight, modelInputWidth, 0);
        input.add(data);
        // run
        ArrayList<LiteKitData> output = machine.predictWithInputData(input);
        // 后处理数据
        float[] result = postprocess(output.get(0).output.fetchFloatData(), output.get(1).output.fetchFloatData(), output.get(2).output.fetchFloatData(),
                output.get(3).output.fetchFloatData(), output.get(4).output.fetchFloatData(), image.getWidth(), image.getHeight());
        RectF handBoxRext = new RectF(result[0], result[1], result[0] + result[2], result[1] + result[3]);
        draw(handBoxRext);
        machine.releaseMachine();
    }

    /**
     * 注意保存Bitmap到本地sdcard时, 需要先获取读写权限
     */
    private void draw(RectF handBoxRext) {
        Bitmap tmp = image.copy(image.getConfig(), true);
        Canvas canvas = new Canvas(tmp);
        Paint paint = new Paint();
        paint.setColor(Color.BLUE);
        canvas.drawRect(handBoxRext, paint);
    }

    public float[] createInputData(Bitmap image) {
        if (image == null) {
            return null;
        }
        int imgWidth = image.getWidth();
        int imgHeight = image.getHeight();
        if (imgWidth <= 0 || imgHeight <= 0) {
            return null;
        }
        int bytes = image.getByteCount();
        ByteBuffer buf = ByteBuffer.allocate(bytes);
        image.copyPixelsToBuffer(buf);
        byte[] data = buf.array();
        // bitmap 默认格式为 RGBA_8888，而实际在内存中的排布顺序为 R, G, B, A
        return preprocess(data, imgWidth, imgHeight);
    }

    String modelPath() {
        String dir = this.getFilesDir().getAbsolutePath() + File.separator;
        String model_name = "gesture_det_cpu";
        try {
            FileUtil.copyAssetResource2File(this.getApplicationContext(), "models/gesture/" + model_name, dir + model_name);
        } catch (IOException e) {
            Log.e(TAG, e.toString());
            System.exit(-1);
        }
        return dir + model_name;
    }

    public native float[] preprocess(byte[] data, int imgWidth, int imgHeight);

    public native float[] postprocess(float[] output0, float[] output1, float[] output2, float[] output3, float[] output4, int imgWidth, int imgHeight);
}