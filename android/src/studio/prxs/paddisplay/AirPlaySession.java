package studio.prxs.paddisplay;

import android.content.Context;
import android.content.SharedPreferences;
import android.media.AudioManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;
import io.github.jqssun.airplay.bridge.NativeBridge;
import java.io.File;
import java.security.SecureRandom;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/** All lifecycle mutations are serialized; native callbacks never wait for the lifecycle worker. */
public final class AirPlaySession {
    interface Listener extends AirPlayVideo.Listener {void ready(String name);void pin(String code);void waiting();}
    private static final ExecutorService lifecycle=Executors.newSingleThreadExecutor(r->new Thread(r,"SidePad-AirPlay-server"));
    private final Context context;
    private final Listener listener;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final AtomicBoolean closed=new AtomicBoolean();
    private final AtomicInteger connections=new AtomicInteger();
    private final Object audioLock=new Object();
    private final AirPlayVideo video;
    private final AudioManager audio;
    private NativeBridge bridge;
    private long handle;
    private AirPlayDiscovery discovery;
    private volatile String name;
    private boolean audioFocused;
    private final AudioManager.OnAudioFocusChangeListener focusChange=change->{
        if(change==AudioManager.AUDIOFOCUS_LOSS || change==AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)onAudioTeardown();
    };
    AirPlaySession(Context context,Surface surface,Listener listener){
        this.context=context.getApplicationContext();this.listener=listener;
        this.audio=(AudioManager)this.context.getSystemService(Context.AUDIO_SERVICE);
        video=new AirPlayVideo(surface,listener);
    }
    void start(){lifecycle.execute(()->{
        try{
            if(closed.get())return;
            bridge=new NativeBridge();
            name="SidePad · "+Build.MODEL;
            bridge.nativeSetDefaultStreamValues(property(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE),property(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER));
            long next=bridge.nativeInit(this,identity(),name,new File(context.getFilesDir(),"airplay.pem").getAbsolutePath(),false,true);
            if(next==0)throw new IllegalStateException("AirPlay 엔진을 시작하지 못했습니다.");
            synchronized(audioLock){handle=next;}
            if(closed.get()){destroy();return;}
            // Use a known per-session PIN before advertising. Some iOS clients ask for
            // a password without delivering pair-pin-start to the engine's display callback.
            int pin=new SecureRandom().nextInt(10000);
            bridge.nativeSetPlist(next,"pin",10000+pin);
            listener.pin(String.format(java.util.Locale.ROOT,"%04d",pin));
            bridge.nativeSetH265Enabled(next,false);
            bridge.nativeSetHlsEnabled(next,false); // Screen mirroring only; do not advertise an unimplemented HLS player.
            bridge.nativeSetCodecs(next,true,true);
            bridge.nativeSetAudioEnabled(next,true);
            bridge.nativeSetDisplaySize(next,1920,1080,60);
            bridge.nativeSetPlist(next,"maxFPS",60);
            bridge.nativeSetPlist(next,"overscanned",0);
            bridge.nativeServerAudioConfigure(next,0,95,0,false,true,true,false);
            int port=bridge.nativeStart(next,7000);
            if(port<1)throw new IllegalStateException("AirPlay 수신 포트를 열지 못했습니다. 다른 수신 앱을 종료한 뒤 다시 시도하세요.");
            final Map<String,String> raop=bridge.nativeGetRaopTxtRecords(next),airplay=bridge.nativeGetAirplayTxtRecords(next);
            final String raopName=bridge.nativeGetRaopServiceName(next),serverName=bridge.nativeGetServerName(next);
            name=serverName==null?name:serverName;
            main.post(()->{
                if(closed.get())return;
                discovery=new AirPlayDiscovery(context);
                AtomicInteger count=new AtomicInteger();
                AirPlayDiscovery.Listener registered=new AirPlayDiscovery.Listener(){
                    public void registered(String registeredName){if(!closed.get() && count.incrementAndGet()==2){Log.i("SidePad-AirPlay","advertised="+name+" port="+port);listener.ready(name);}}
                    public void failed(String message){if(!closed.get()){listener.error(message);close();}}
                };
                discovery.register(raopName,"_raop._tcp",port,raop,registered);
                discovery.register(name,"_airplay._tcp",port,airplay,registered);
            });
        }catch(Throwable error){
            Log.e("SidePad-AirPlay","start failed",error);
            if(!closed.get())listener.error(error instanceof UnsatisfiedLinkError?"이 패드용 AirPlay 엔진이 빌드에 포함되지 않았습니다.":"AirPlay 시작 실패: "+error.getMessage());
            closed.set(true);video.close();destroy();
        }
    });}
    private int property(String key){try{return Integer.parseInt(audio.getProperty(key));}catch(Exception ignored){return 0;}}
    private byte[] identity(){
        SharedPreferences prefs=context.getSharedPreferences("sidepad-airplay",Context.MODE_PRIVATE);
        String saved=prefs.getString("device-id","");byte[] id=new byte[6];
        if(saved.matches("[0-9a-f]{12}")){for(int i=0;i<6;i++)id[i]=(byte)Integer.parseInt(saved.substring(2*i,2*i+2),16);return id;}
        new SecureRandom().nextBytes(id);id[0]=(byte)((id[0]&0xfc)|2);
        StringBuilder value=new StringBuilder();for(byte b:id)value.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
        prefs.edit().putString("device-id",value.toString()).apply();return id;
    }
    void close(){
        if(!closed.compareAndSet(false,true))return;
        if(discovery!=null)discovery.close();video.close();
        lifecycle.execute(this::destroy);
    }
    private void destroy(){
        long old;synchronized(audioLock){old=handle;handle=0;}
        if(old!=0){
            bridge.nativeStop(old);bridge.nativeServerAudioStop(old);bridge.nativeDestroy(old);
            Log.i("SidePad-AirPlay","server-stopped");
        }
        main.post(()->{if(audioFocused){audio.abandonAudioFocus(focusChange);audioFocused=false;}});
    }
    public void onVideoData(byte[] data,long timeNs,boolean h265){if(!closed.get() && !h265)video.frame(data,timeNs);}
    public void onAudioFormat(int type,int samples,boolean screen){
        if(closed.get())return;
        main.post(()->{if(!closed.get()){audio.requestAudioFocus(focusChange,AudioManager.STREAM_MUSIC,AudioManager.AUDIOFOCUS_GAIN);audioFocused=true;}});
        synchronized(audioLock){if(closed.get() || handle==0)return;bridge.nativeServerAudioStart(handle);bridge.nativeServerAudioFormat(handle,type,samples);}
        Log.i("SidePad-AirPlay","audio-format="+type+" screen="+screen);
    }
    public void onVideoSize(float srcW,float srcH,float w,float h){if(!closed.get())video.size((int)w,(int)h);}
    public void onVolumeChange(float volume){} // Device volume keys control playout; never leave the tablet muted on disconnect.
    public float onClientVolume(){int max=audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);return max==0?-144f:-30f+30f*audio.getStreamVolume(AudioManager.STREAM_MUSIC)/max;}
    public void onAudioTeardown(){synchronized(audioLock){if(!closed.get() && handle!=0)bridge.nativeServerAudioStop(handle);}}
    public void onConnectionInit(){if(!closed.get())connections.incrementAndGet();}
    public void onConnectionDestroy(){if(!closed.get() && connections.updateAndGet(n->Math.max(0,n-1))==0){video.reset();onAudioTeardown();listener.waiting();}}
    public void onConnectionReset(int reason){Log.i("SidePad-AirPlay","connection-reset="+reason);}
    public void onDisplayPin(String pin){if(!closed.get())listener.pin(pin);}
    public void onMetadata(byte[] bytes){}
    public void onCoverArt(byte[] bytes){}
    public void onProgress(long start,long current,long end){}
    public void onDacpId(String id,String activeRemote){}
    public void onMirrorRunning(boolean running){if(!closed.get() && !running){video.reset();listener.waiting();}}
    public void onVideoPlay(String location,float start){}
    public void onVideoScrub(float position){}
    public void onVideoRate(float rate){}
    public void onVideoStop(){}
    public void onVideoSessionPoll(){}
    public void onLog(String message){Log.d("SidePad-AirPlay",message);}
}
