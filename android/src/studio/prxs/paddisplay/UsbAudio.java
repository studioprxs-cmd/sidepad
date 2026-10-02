package studio.prxs.paddisplay;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioDeviceInfo;
import android.media.AudioFocusRequest;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import java.io.DataInputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

/** Dedicated audio channel; never blocks the video or pointer receivers. */
final class UsbAudio implements Runnable {
    private static final int RATE=48000, FRAME_BYTES=4;
    private final String token;
    private final AudioManager manager;
    private final AtomicBoolean active=new AtomicBoolean(true);
    private volatile Socket socket;
    private volatile float focusVolume=1;
    private AudioTrack track;
    private AudioFocusRequest focus;
    UsbAudio(Context context,String token){
        this.token=token;manager=(AudioManager)context.getSystemService(Context.AUDIO_SERVICE);
    }
    void stop(){active.set(false);try{if(socket!=null)socket.close();}catch(Exception ignored){}}
    private void openTrack() throws Exception {
        if(track!=null)return;
        AudioAttributes attributes=new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build();
        focus=new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener(change->{
                focusVolume=change==AudioManager.AUDIOFOCUS_GAIN?1f:(change==AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK?.2f:0f);
            },new Handler(Looper.getMainLooper())).build();
        focusVolume=manager.requestAudioFocus(focus)==AudioManager.AUDIOFOCUS_REQUEST_GRANTED?1f:0f;
        int minimum=AudioTrack.getMinBufferSize(RATE,AudioFormat.CHANNEL_OUT_STEREO,AudioFormat.ENCODING_PCM_16BIT);
        if(minimum<=0)throw new Exception("48 kHz stereo output unavailable");
        track=new AudioTrack.Builder().setAudioAttributes(attributes)
            .setAudioFormat(new AudioFormat.Builder().setSampleRate(RATE).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setTransferMode(AudioTrack.MODE_STREAM).setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .setBufferSizeInBytes(Math.max(minimum,960*FRAME_BYTES)).build();
        if(track.getState()!=AudioTrack.STATE_INITIALIZED)throw new Exception("AudioTrack initialization failed");
        for(AudioDeviceInfo device:manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)){
            if(device.getType()==AudioDeviceInfo.TYPE_BUILTIN_SPEAKER){track.setPreferredDevice(device);break;}
        }
        track.setBufferSizeInFrames(960);
        if(android.os.Build.VERSION.SDK_INT>=31)track.setStartThresholdInFrames(240);
        track.setVolume(focusVolume);track.play();
        Log.i("PadDisplay","audio-output=PCM16 stereo rate=48000 buffer-frames="+track.getBufferSizeInFrames()
            +" performance="+track.getPerformanceMode());
    }
    private void closeTrack(){
        if(track!=null){try{track.pause();track.flush();}catch(Exception ignored){}track.release();track=null;}
        if(focus!=null){manager.abandonAudioFocusRequest(focus);focus=null;}
    }
    @Override public void run(){
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO);
        while(active.get()){
            try{
                Socket current=new Socket();socket=current;current.setTcpNoDelay(true);
                current.connect(new InetSocketAddress("127.0.0.1",28767),3000);
                current.getOutputStream().write(("PADAUDIO/1 "+token+"\n").getBytes(StandardCharsets.UTF_8));
                DataInputStream input=new DataInputStream(current.getInputStream());
                byte[] pcm=new byte[65536];long frames=0,logAt=SystemClock.uptimeMillis();int peak=0;
                while(active.get()){
                    int type=input.readUnsignedByte(),length=input.readInt();
                    if(type==10 && length==1){
                        int enabled=input.readUnsignedByte();
                        if(enabled==0)closeTrack();else if(enabled==1)openTrack();else throw new Exception("Invalid audio state");
                        Log.i("PadDisplay","audio-enabled="+(enabled==1));continue;
                    }
                    if(type!=9 || length<=0 || length>pcm.length || length%FRAME_BYTES!=0)throw new Exception("Invalid PCM packet");
                    input.readFully(pcm,0,length);
                    if(track==null)continue;
                    // Catch up after an exceptional USB stall instead of accumulating old sound.
                    if(input.available()>RATE*FRAME_BYTES/10){track.pause();track.flush();track.play();continue;}
                    track.setVolume(focusVolume);
                    for(int i=0;i<length;i+=2){int sample=(short)((pcm[i]&255)|(pcm[i+1]<<8));peak=Math.max(peak,Math.abs(sample));}
                    int offset=0;
                    while(offset<length && active.get()){
                        int written=track.write(pcm,offset,length-offset,AudioTrack.WRITE_BLOCKING);
                        if(written<=0)throw new Exception("Audio output write failed: "+written);offset+=written;
                    }
                    frames+=offset/FRAME_BYTES;
                    long now=SystemClock.uptimeMillis();
                    if(now-logAt>=5000){
                        AudioDeviceInfo route=track.getRoutedDevice();
                        Log.i("PadDisplay","audio frames="+frames+" played="+Integer.toUnsignedLong(track.getPlaybackHeadPosition())
                            +" peak="+peak+" route="+(route==null?-1:route.getType())+" underruns="+track.getUnderrunCount());
                        logAt=now;peak=0;
                    }
                }
            }catch(Exception error){if(active.get())Log.w("PadDisplay","Audio reconnect: "+error);}
            finally{closeTrack();try{if(socket!=null)socket.close();}catch(Exception ignored){}}
            if(active.get())try{Thread.sleep(1000);}catch(InterruptedException ignored){}
        }
    }
}
