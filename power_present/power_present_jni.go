package main

/*
#include <jni.h>
#include <stdlib.h>
#include <string.h>

static char* CopyString(JNIEnv *env, jstring value) {
    if (value == NULL) return NULL;
    const char *chars = (*env)->GetStringUTFChars(env, value, NULL);
    if (chars == NULL) return NULL;
    char *copy = strdup(chars);
    (*env)->ReleaseStringUTFChars(env, value, chars);
    return copy;
}

static void FreeString(JNIEnv *env, char *str) {
    if (str != NULL) {
        free(str);
    }
}
*/
import "C"
import (
    "fmt"
)

var activeService *PowerPresentService

func getService() *PowerPresentService {
    if activeService == nil {
        activeService = NewPowerPresentService("session-1", "peer-1")
    }
    return activeService
}

//export Java_com_shiva2232_orbitx_PowerPresentBridge_init
func Java_com_shiva2232_orbitx_PowerPresentBridge_init(env *C.JNIEnv, clazz C.jclass) {
    service := getService()
    service.Log("PowerPresent native initialized")
}

//export Java_com_shiva2232_orbitx_PowerPresentBridge_loadUrl
func Java_com_shiva2232_orbitx_PowerPresentBridge_loadUrl(env *C.JNIEnv, clazz C.jclass, jurl C.jstring) {
    urlC := C.CopyString(env, jurl)
    if urlC == nil {
        return
    }
    url := C.GoString(urlC)
    C.FreeString(urlC)

    service := getService()
    service.Log(fmt.Sprintf("PowerPresent loadUrl %s", url))
}

//export Java_com_shiva2232_orbitx_PowerPresentBridge_sendGesture
func Java_com_shiva2232_orbitx_PowerPresentBridge_sendGesture(env *C.JNIEnv, clazz C.jclass, jaction C.jstring, x C.jfloat, y C.jfloat) {
    actionC := C.CopyString(env, jaction)
    if actionC == nil {
        return
    }
    action := C.GoString(actionC)
    C.FreeString(actionC)

    service := getService()
    service.Log(fmt.Sprintf("PowerPresent gesture %s x=%f y=%f", action, float32(x), float32(y)))
}

func main() {}
