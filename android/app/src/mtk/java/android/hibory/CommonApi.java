// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

package android.hibory;

/**
 * JNI binding for the board vendor's (Hibory) libHibory_CommonApi.so on FP08 / MT8768 terminals.
 * Package and method names must match the native library's exported symbols exactly.
 * Only the calls needed to power the built-in palm scanner are declared.
 */
public class CommonApi {
    static {
        System.loadLibrary("Hibory_CommonApi");
    }

    public native int setGpioDir(int gpio, int dir);

    public native int setGpioOut(int gpio, int value);

    /** 1 = route the USB controller to the internal scanner (host mode), 0 = external port. */
    public native int setUsbHost(int on);
}
