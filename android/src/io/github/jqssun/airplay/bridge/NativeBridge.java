// JNI ABI of android-airplay-server v0.0.31 (GPL-3.0).
// Keep this package and method signatures aligned with the pinned native binary.
package io.github.jqssun.airplay.bridge;

import java.util.Map;

public final class NativeBridge {
    static { System.loadLibrary("airplay_native"); }
    public native long nativeInit(Object callback, byte[] hardwareAddress, String name,
                                  String keyFile, boolean nohold, boolean requirePin);
    public native int nativeStart(long handle, int port);
    public native void nativeStop(long handle);
    public native void nativeDestroy(long handle);
    public native void nativeSetDisplaySize(long handle, int width, int height, int fps);
    public native void nativeSetPlist(long handle, String key, int value);
    public native void nativeSetH265Enabled(long handle, boolean enabled);
    public native void nativeSetCodecs(long handle, boolean alac, boolean aac);
    public native void nativeSetHlsEnabled(long handle, boolean enabled);
    public native void nativeSetAudioEnabled(long handle, boolean enabled);
    public native Map<String,String> nativeGetRaopTxtRecords(long handle);
    public native Map<String,String> nativeGetAirplayTxtRecords(long handle);
    public native String nativeGetRaopServiceName(long handle);
    public native String nativeGetServerName(long handle);
    public native void nativeSetDefaultStreamValues(int sampleRate, int framesPerBurst);
    public native boolean nativeServerAudioConfigure(long handle, int cushionMs, int percentile,
            int bufferFrames, boolean softwareAlac, boolean realtime, boolean lowLatency, boolean log);
    public native boolean nativeServerAudioStart(long handle);
    public native void nativeServerAudioStop(long handle);
    public native void nativeServerAudioFormat(long handle, int compressionType, int samplesPerFrame);
}
