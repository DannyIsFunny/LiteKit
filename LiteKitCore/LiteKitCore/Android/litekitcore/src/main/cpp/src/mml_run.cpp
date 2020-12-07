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

#include <jni.h>
#include <string>
#include <map>

#include "common_log.h"
#include "mml_run.h"
#include "mml_inference_api.h"

namespace mmlcore {
using mml_framework::MMLMachineService;
using mml_framework::MMLConfig;

extern "C"
JNIEXPORT void JNICALL
Java_com_baidu_mmlcore_MMLBaseMachine_run(JNIEnv *env, jobject type, jlong nativeMachineHandler) {
  MMLMachineService* service = reinterpret_cast<MMLMachineService*>(nativeMachineHandler);
  int ret = service->run();
  if (ret != 0) {
    LOGE("service run error");
  }
}

}